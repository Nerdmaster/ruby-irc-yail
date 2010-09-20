require 'net/yail/message_parser.rb'

module Net
class YAIL

  # Base event class for stuff shared by any type of event.  Note that :type and :handled
  # apply to *all* events, so they're explicitly defined here.
  class BaseEvent
    attr_reader :type, :handled

    # Creates an event object and sets up some sane defaults for common elements
    def initialize()
      @handled = false
      @type = nil
    end

    # Unintuitive name to avoid accidental use - we don't want it to be the norm to stop the event
    # handling chain anymore!  Filters + callback should make that a rarity.
    def end_chain; @handled = true; end

    # Cheesy shortcut to @handled in "boolean" form
    def handled?; return @handled; end
  end

  # The outgoing event class - outgoing events haven't got much in
  # common, so this class is primarily to facilitate the new system.
  class OutgoingEvent < BaseEvent
    # Outgoing events in our system are always :outgoing_xxx
    def type
      return :"outgoing_#{@type.to_s}"
    end
  end

  # This is the incoming event class.  For all situations where the server
  # sent us some kind of event, this class handles all the data.
  #
  # All events will have a :raw attribute that stores the exact text sent from
  # the IRC server.  Other possible pieces of data are as follows:
  # * fullname: Rarely needed, full text of origin of an action
  # * nick: Nickname of originator of an event
  # * channel: Where applicable, the name of the channel in which the event
  #   happened.
  # * text: Actual message/emote/notice/etc
  # * target: User targeted for various commands - PRIVMSG/NOTICE recipient, KICK victim, etc
  # * pm?: Set to true if the event is a "private" event (not sent to the
  #   channel).  Useful primarily for message types of events (PRIVMSG).
  #
  # To more easily call the right user event, we store each event type and its "parent" where it
  # makes sense.  This ensures that a user currently handling :incoming_ctcp won't be totally
  # screwed when we add in :incoming_userinfo and such.  Top-level handlers aren't in here, which
  # is vital to avoid trying to hack around numerics (not to mention a bunch of fairly useless
  # data)
  #
  # Look at the source for specifics of which IRC events set up what data.  Or try to parse the
  # lovely RFCs....
  #
  # For convenience, the event stores its MessageParser object so users can access raw data as
  # necessary (for numeric messages, this is often useful)
  class IncomingEvent < BaseEvent
    attr_reader :raw, :msg
    private_class_method :new

    # Sets up data and accessors
    def initialize(data = {})
      super()

      # Don't modify incoming element!
      @data = data.dup
      @raw = @data.delete(:raw)
      @msg = @data.delete(:msg)
      @type = @data.delete(:type)

      # Give useful accessors in a hacky but fun way!  I can't decide if I prefer the pain of
      # using method_missing or the pain of not knowing how to do this without a string eval....
      for key in @data.keys
        key = key.to_s
        self.instance_eval("def #{key}; return @data[:#{key}]; end")
      end
    end

    # Helps us debug
    def to_s
      return super().gsub('IncomingEvent', "IncomingEvent[#{@type.to_s}]")
    end

    # Incoming events in our system are always :incoming_xxx
    def type; return :"incoming_#{@type.to_s}"; end

    # Effectively our event "factory" - uses Net::YAIL::MessageParser and returns an event
    # object - usually just one, but TODO: some lines actually contain multiple messages.  When
    # EventManager or similar is implemented, we'll just register events and this will be a non-issue
    def self.parse(line)
      # Parse with MessageParser to get raw IRC info
      raw = line.dup
      msg = Net::YAIL::MessageParser.new(line)
      data = { :raw => raw, :msg => msg, :parent => nil }

      # Not all messages from the server identify themselves as such, so we just assume it's from
      # the server unless we explicitly see a nick
      data[:server?] = true

      # Sane defaults for most messages
      if msg.servername
        data[:from] = data[:servername] = msg.servername
      elsif msg.prefix && msg.nick
        data[:from] = data[:fullname] = msg.prefix
        data[:nick] = msg.nick
        data[:server?] = false
      end

      case msg.command
        when 'ERROR'
          data[:type] = :error
          data[:text] = msg.params.last
          event = new(data)

        when 'PING'
          data[:type] = :ping
          data[:text] = msg.params.last
          event = new(data)

        when 'TOPIC'
          data[:type] = :topic_change
          data[:channel] = msg.params.first
          data[:text] = msg.params.last
          event = new(data)

        when /^\d{3}$/
          # Get base event for the "numeric" type - so many of these exist, and so few are likely
          # to be handled directly.  Sadly, some hackery has to happen here to make "text" backward-
          # compatible since old YAIL auto-joined all parameters into one string.
          data[:type] = :numeric
          params = msg.params.dup
          data[:target] = params.shift
          data[:parameters] = params
          data[:text] = params.join(' ')
          data[:numeric] = msg.command.to_i
          event = new(data)

          # Create child event for the specific numeric
          data[:type] = msg.command.to_sym
          data[:parent] = event
          event = new(data)

        when 'INVITE'
          data[:type] = :invite
          data[:channel] = msg.params.last

          # This should always be us, but still worth capturing just in case
          data[:target] = msg.params.first
          event = new(data)
  
        # This can encompass three possible messages, so further refining happens here - the last param
        # is always the message itself, so we look for patterns there.
        when 'PRIVMSG'
          event = privmsg_events(msg, data)
  
        # This can encompass two possible messages, again based on final param
        when 'NOTICE'
          event = notice_events(msg, data)
  
        when 'MODE'
          event = mode_events(msg, data)

        when 'JOIN'
          data[:type] = :join
          data[:channel] = msg.params.last
          event = new(data)

        when 'PART'
          data[:type] = :part
          data[:channel] = msg.params.first
          data[:text] = msg.params.last
          event = new(data)

        when 'KICK'
          data[:type] = :kick
          data[:channel] = msg.params[0]
          data[:target] = msg.params[1]
          data[:text] = msg.params[2]
          event = new(data)

        when 'QUIT'
          data[:type] = :quit
          data[:text] = msg.params.first
          event = new(data)

        when 'NICK'
          data[:type] = :nick
          data[:text] = msg.params.first
          event = new(data)
  
        # Unknown line!  If this library is complete, we should *never* see this situation occur,
        # so it'll be up to the caller to decide what to do.
        else
          data[:type] = :unknown
          event = new(data)
      end

      return event
    end

    protected

    # Parses a MODE to its events - basic, backward-compatible :mode event for now, but
    # TODO: eventually get set up for multiple atomic mode messages (need event manager first)
    def self.mode_events(msg, data)
      data[:type]     = :mode
      data[:channel]  = msg.params.shift
      data[:text]     = msg.params.shift
      data[:targets]  = msg.params
      event = new(data)
    end

    # Parses basic data for the "message" constructs: PRIVMSG and NOTICE
    def self.parse_message_data(msg, data)
      # Defaults so all messages have a fairly standard interface
      data[:pm?] = false
      data[:target] = nil
      data[:channel] = msg.params.first

      # If this isn't a channel message, set up PM data - keep channel, just set it to nil so the
      # API is consistent
      unless msg.params.first =~ /^[!&#+]/
        data[:channel] = nil
        data[:pm?] = true
        data[:target] = msg.params.first
      end
    end

    # Parses a PRIVMSG to its events - CTCP stuff needs parents, ACT stuff needs two-parent
    # hierarchy
    def self.privmsg_events(msg, data)
      # Parse common elements
      parse_message_data(msg, data)

      # Get base event
      data[:type] = :msg
      data[:text] = msg.params.last
      event = new(data)

      # Is this CTCP?
      if event.text =~ /^\001(.+?)\001$/
        data[:type] = :ctcp
        data[:text] = $1
        data[:parent] = event
        
        event = new(data)
      end

      # CTCP action?
      if :ctcp == data[:type] && event.text =~ /^ACTION (.+)$/
        data[:type] = :act
        data[:text] = $1
        data[:parent] = event

        event = new(data)
      end

      return event
    end

    # Parses a NOTICE to its events - CTCP replies come through here
    def self.notice_events(msg, data)
      # Parse common elements
      parse_message_data(msg, data)

      # Get base event
      data[:type] = :notice
      data[:text] = msg.params.last
      event = new(data)

      if event.text =~ /^\001(.+?)\001$/
        data[:type] = :ctcp_reply
        data[:text] = $1
        data[:parent] = event

        event = new(data)
      end

      return event
    end

  end
end
end
