require 'socket'
require 'thread'
require 'yaml'
require 'logger'

# To make this library seem smaller, a lot of code has been split up and put
# into semi-logical files.  I don't really like this hacky solution, but I
# cannot figure out a nicer way to keep the code as clean as I like.
require 'net/yail/magic_events'
require 'net/yail/default_events'
require 'net/yail/output_api'
require 'net/yail/legacy_events'

# This tells us our version info.
require 'net/yail/yail-version'

# Finally, a real class to include!
require 'net/yail/event'

# If a thread crashes, I want the app to die.  My threads are persistent, not
# temporary.
Thread.abort_on_exception = true

module Net

# This library is based on the initial release of IRCSocket with a tiny bit
# of plagarism of Ruby-IRC.
#
# My aim here is to build something that is still fairly simple to use, but
# powerful enough to build a decent IRC program.
#
# This is far from complete, but it does successfully power a relatively
# complicated bot, so I believe it's solid and "good enough" for basic tasks.
#
# TODO: update this with useful docs or point to useful docs
class YAIL 
  include Net::IRCEvents::Magic
  include Net::IRCEvents::Defaults
  include Net::IRCOutputAPI
  include Net::IRCEvents::LegacyEvents

  attr_reader(
    :me,                # Nickname on the IRC server
    :registered,        # If true, we've been welcomed
    :nicknames,         # Array of nicknames to try when logging on to server
    :dead_socket,       # True if @socket.eof? or read/connect fail
    :socket             # TCPSocket instance
  )
  attr_accessor(
    :throttle_seconds,
    :log
  )

  def silent
    @log.warn '[DEPRECATED] - Net::YAIL#silent is deprecated as of 1.4.1 - .log can be used instead'
    return @log_silent
  end
  def silent=(val)
    @log.warn '[DEPRECATED] - Net::YAIL#silent= is deprecated as of 1.4.1 - .log can be used instead'
    @log_silent = val
  end

  def loud
    @log.warn '[DEPRECATED] - Net::YAIL#loud is deprecated as of 1.4.1 - .log can be used instead'
    return @log_loud
  end
  def loud=(val)
    @log.warn '[DEPRECATED] - Net::YAIL#loud= is deprecated as of 1.4.1 - .log can be used instead'
    @log_loud = val
  end

  # Makes a new instance, obviously.
  #
  # Note: I haven't done this everywhere, but for the constructor, I felt
  # it needed to have hash-based args.  It's just cleaner to me when you're
  # taking this many args.
  #
  # Options:
  # * <tt>:address</tt>: Name/IP of the IRC server
  # * <tt>:port</tt>: Port number, defaults to 6667
  # * <tt>:username</tt>: Username reported to server
  # * <tt>:realname</tt>: Real name reported to server
  # * <tt>:nicknames</tt>: Array of nicknames to cycle through
  # * <tt>:io</tt>: TCP replacement object to use, should already be connected and ready for sending
  #   the "connect" data (:outgoing_begin_connection handler does this)
  #   If this is passed, :address and :port are ignored.
  # * <tt>:silent</tt>: DEPRECATED - Sets Logger level to FATAL and silences most non-Logger
  #   messages.
  # * <tt>:loud</tt>: DEPRECATED - Sets Logger level to DEBUG. Spits out too many messages for your own good,
  #   and really is only useful when debugging YAIL.  Defaults to false, thankfully.
  # * <tt>:throttle_seconds</tt>: Seconds between a cycle of privmsg sends.
  #   Defaults to 1.  One "cycle" is defined as sending one line of output to
  #   *all* targets that have output buffered.
  # * <tt>:server_password</tt>: Very optional.  If set, this is the password
  #   sent out to the server before USER and NICK messages.
  # * <tt>:log</tt>: Optional, if set uses this logger instead of the default (Ruby's Logger).
  #   If set, :loud and :silent options are ignored.
  # * <tt>:log_io</tt>: Optional, ignored if you specify your own :log - sends given object to
  #   Logger's constructor.  Must be filename or IO object.
  # * <tt>:use_ssl</tt>: Defaults to false.  If true, attempts to use SSL for connection.
  def initialize(options = {})
    @me                 = ''
    @nicknames          = options[:nicknames]
    @registered         = false
    @username           = options[:username]
    @realname           = options[:realname]
    @address            = options[:address]
    @io                 = options[:io]
    @port               = options[:port] || 6667
    @log_silent         = options[:silent] || false
    @log_loud           = options[:loud] || false
    @throttle_seconds   = options[:throttle_seconds] || 1
    @password           = options[:server_password]
    @ssl                = options[:use_ssl] || false

    # Shared resources for threads to try and coordinate....  I know very
    # little about thread safety, so this stuff may be a terrible disaster.
    # Please send me better approaches if you are less stupid than I.
    @input_buffer = []
    @input_buffer_mutex = Mutex.new
    @privmsg_buffer = {}
    @privmsg_buffer_mutex = Mutex.new

    # Buffered output is allowed to go out right away.
    @next_message_time = Time.now

    # Setup callback/filter hashes
    @before_filters = Hash.new
    @after_filters = Hash.new
    @callback = Hash.new

    # Special handling to avoid mucking with Logger constants if we're using a different logger
    if options[:log]
      @log = options[:log]
    else
      @log = Logger.new(options[:log_io] || STDERR)
      @log.level = Logger::WARN
 
      # Convert old-school options into logger stuff
      @log.level = Logger::DEBUG if @log_loud
      @log.level = Logger::FATAL if @log_silent
    end

    if (options[:silent] || options[:loud])
      @log.warn '[DEPRECATED] - passing :silent and :loud options to constructor are deprecated as of 1.4.1 - instead access <yail object>.log.level'
    end

    # Read in map of event numbers and names.  Yes, I stole this event map
    # file from RubyIRC and made very minor changes....  They stole it from
    # somewhere else anyway, so it's okay.
    eventmap = "#{File.dirname(__FILE__)}/yail/eventmap.yml"
    @event_number_lookup = File.open(eventmap) { |file| YAML::load(file) }.invert

    prepare_tcp_socket

    set_defaults
  end

  # Starts listening for input and builds the perma-threads that check for
  # input, output, and privmsg buffering.
  def start_listening
    # We don't want to spawn an extra listener
    return if Thread === @ioloop_thread

    # Don't listen if socket is dead
    return if @dead_socket

    # Exit a bit more gracefully than just crashing out - allow any :outgoing_quit filters to run,
    # and even give the server a second to clean up before we fry the connection
    #
    # TODO: perhaps this should be in a callback so user can override TERM/INT handling
    quithandler = lambda { quit('Terminated by user'); sleep 1; stop_listening; exit }
    trap("INT", quithandler)
    trap("TERM", quithandler)

    # Begin the listening thread
    @ioloop_thread = Thread.new {io_loop}
    @input_processor = Thread.new {process_input_loop}
    @privmsg_processor = Thread.new {process_privmsg_loop}

    # Let's begin the cycle by telling the server who we are.  This should start a TERRIBLE CHAIN OF EVENTS!!!
    dispatch OutgoingEvent.new(:type => :begin_connection, :username => @username, :address => @address, :realname => @realname)
  end

  # This starts the connection, threading, etc. as start_listening, but *forces* the user into
  # and endless loop.  Great for a simplistic bot, but probably not universally desired.
  def start_listening!
    start_listening
    while !@dead_socket
      # This is more for CPU savings than actually needing a delay - CPU spikes if we never sleep
      sleep 0.05
    end
  end

  # Kills and clears all threads.  See note above about my lack of knowledge
  # regarding threads.  Please help me if you know how to make this system
  # better.  DEAR LORD HELP ME IF YOU CAN!
  def stop_listening
    return unless Thread === @ioloop_thread

    # Do thread-ending in a new thread or else we're liable to kill the
    # thread that's called this method
    Thread.new do
      # Kill all threads if they're really threads
      [@ioloop_thread, @input_processor, @privmsg_processor].each {|thread| thread.terminate if Thread === thread}

      @socket.close
      @socket = nil
      @dead_socket = true

      @ioloop_thread = nil
      @input_processor = nil
      @privmsg_processor = nil
    end
  end

  private

  # Sets up all default filters and callbacks
  def set_defaults
    # Set up reporting filters - this needs to be dropped, but for now centralizing it is best to avoid
    # breaking the API (2.x WILL fix this, I swear!  ...unless it doesn't, of course)
    incoming_reporting = [
      :msg, :act, :notice, :ctcp, :ctcpreply, :mode, :join, :part, :kick,
      :quit, :nick, :welcome, :bannedfromchan, :badchannelkey, :channelurl, :topic,
      :topicinfo, :endofnames, :motd, :motdstart, :endofmotd, :invite
    ]
    for event in incoming_reporting
      after_filter(:"incoming_#{event}", self.method(:"r_#{event}") )
    end

    # Set up callbacks for slightly more important things than reporting - note that these should
    # eventually be changed as they don't belong in the core of YAIL.  Note that since these are
    # callbacks, the user can very easily overwrite them, at least.
    on_nicknameinuse self.method(:_nicknameinuse)
    on_namreply self.method(:_namreply)

    # Set up truly core handlers/filters - these shouldn't be overridden unless users like to get
    # their hands dirty
    set_callback(:outgoing_begin_connection, self.method(:out_begin_connection))
    on_ping self.method(:magic_ping)
    on_welcome self.method(:magic_welcome)

    # Nick change magically setting @me is necessary as a filter - user can handle the event and do
    # anything he wants, but this should still run.
    hearing_nick self.method(:magic_nick)
  end

  # Prepares @socket for use and defaults @dead_socket to false
  def prepare_tcp_socket
    @dead_socket = false

    # Build our socket - if something goes wrong, it's immediately a dead socket.
    begin
      @socket = TCPSocket.new(@address, @port)
      setup_ssl if @ssl
    rescue StandardError => boom
      @log.fatal "+++ERROR: Unable to open socket connection in Net::YAIL.initialize: #{boom.inspect}"
      @dead_socket = true
      raise
    end
  end

  # If user asked for SSL, this is where we set it all up
  def setup_ssl
    require 'openssl'
    ssl_context = OpenSSL::SSL::SSLContext.new()
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @socket = OpenSSL::SSL::SSLSocket.new(@socket, ssl_context)
    @socket.sync = true
    @socket.connect
  end

  # Depending on protocol (SSL vs. not), reads atomic messages from socket.  This could be the
  # start of more generic message reading for other protocols, but for now reads a single line
  # for IRC and any number of lines from SSL IRC.
  def read_socket_messages
    # Simple non-ssl socket == return a single line
    return [@socket.gets] unless @ssl

    # SSL socket == return all lines available
    return @socket.readpartial(Buffering::BLOCK_SIZE).split($/).collect {|message| message}
  end

  # Reads incoming data - should only be called by io_loop, and only when
  # we've already ensured that data is, in fact, available.
  def read_incoming_data
    begin
      messages = read_socket_messages.compact
    rescue StandardError => boom
      @dead_socket = true
      @log.fatal "+++ERROR in read_incoming_data -> @socket.gets: #{boom.inspect}"
      raise
    end

    # If we somehow got no data here, the socket is closed.  Run away!!!
    if !messages || messages.empty?
      @dead_socket = true
      return
    end

    # Chomp and push each message
    for message in messages
      message.chomp!
      @log.debug "+++INCOMING: #{message.inspect}"

      # Only synchronize long enough to push our incoming string onto the
      # input buffer
      @input_buffer_mutex.synchronize do
        @input_buffer.push(message)
      end
    end
  end

  # This should be called from a thread only!  Does nothing but listens
  # forever for incoming data, and calling filters/callback due to this listening
  def io_loop
    loop do
      # if no data is coming in, don't block the socket!
      read_incoming_data if Kernel.select([@socket], nil, nil, 0)

      # Check for dead socket
      @dead_socket = true if @socket.eof?

      sleep 0.05
    end
  end

  # This again is a thread-only method.  Loops forever, handling input
  # whenever the @input_buffer var has any.
  def process_input_loop
    lines = nil
    loop do
      # Only synchronize long enough to copy and clear the input buffer.
      @input_buffer_mutex.synchronize do
        lines = @input_buffer.dup
        @input_buffer.clear
      end

      if lines
        # Now actually handle the data we copied, secure in the knowledge
        # that our reader thread is no longer going to wait on us.
        until lines.empty?
          event = Net::YAIL::IncomingEvent.parse(line)
          dispatch(event)
        end

        lines = nil
      end

      sleep 0.05
    end
  end

  # Grabs one message for each target in the private message buffer, removing
  # messages from @privmsg_buffer.  Returns a hash array of target -> text
  def pop_privmsgs
    privmsgs = {}

    # Only synchronize long enough to pop the appropriate messages.  By
    # the way, this is UGLY!  I should really move some of this stuff....
    @privmsg_buffer_mutex.synchronize do
      for target in @privmsg_buffer.keys
        # Clean up our buffer to avoid a bunch of empty elements wasting
        # time and space
        if @privmsg_buffer[target].nil? || @privmsg_buffer[target].empty?
          @privmsg_buffer.delete(target)
          next
        end

        privmsgs[target] = @privmsg_buffer[target].shift
      end
    end

    return privmsgs
  end

  # Checks for new private messages, and outputs all that are gathered from
  # pop_privmsgs, if any
  def check_privmsg_output
    privmsgs = pop_privmsgs
    @next_message_time = Time.now + @throttle_seconds unless privmsgs.empty?

    for (target, out_array) in privmsgs
      report(out_array[1]) unless out_array[1].to_s.empty?
      raw("PRIVMSG #{target} :#{out_array.first}", false)
    end
  end

  # Our final thread loop - grabs the first privmsg for each target and
  # sends it on its way.
  def process_privmsg_loop
    loop do
      check_privmsg_output if @next_message_time <= Time.now && !@privmsg_buffer.empty?

      sleep 0.05
    end
  end

  ##################################################
  # EVENT HANDLING ULTRA SUPERSYSTEM DELUXE!!!
  ##################################################

  public
  # Prepends the given block or method to the before_filters array for the given type.  Before-filters are called
  # before the event callback has run, and can stop the event (and other filters) from running by calling the event's
  # end_chain() method.  Filters shouldn't do this very often!  Before-filtering can modify output text before the
  # event callback runs, ignore incoming events for a given user, etc.
  def before_filter(event_type, method = nil, &block)
    filter = block_given? ? block : method
    if filter
      @before_filters[event_type] ||= Array.new
      @before_filters[event_type].unshift(filter)
    end
  end

  # Sets up the callback for the given incoming event type.  Note that unlike Net::YAIL 1.4.x and prior, there is no
  # longer a concept of multiple callbacks!  Use filters for that kind of functionality.  Think this way: the callback
  # is the action that takes place when an event hits.  Filters are for functionality related to the event, but not
  # the definitive callback - logging, filtering messages, stats gathering, ignoring messages from a set user, etc.
  def set_callback(event_type, method = nil, &block)
    callback = block_given? ? block : method
    @callback[event_type] = callback
    @callback.delete(event_type) unless callback
  end

  # Prepends the given block or method to the after_filters array for the given type.  After-filters are called after
  # the event callback has run, and cannot stop other after-filters from running.  Best used for logging or statistics
  # gathering.
  def after_filter(event_type, method = nil, &block)
    filter = block_given? ? block : method
    if filter
      @before_filters[event_type] ||= Array.new
      @before_filters[event_type].unshift(filter)
    end
  end

  # Reports may not get printed in the proper order since I scrubbed the
  # IRCSocket report capturing, but this is way more straightforward to me.
  def report(*lines)
    lines.each {|line| $stdout.puts "(#{Time.now.strftime('%H:%M.%S')}) #{line}"}
  end

  # Given an event, calls pre-callback filters, callback, and post-callback filters.  Uses hacky
  # :incoming_any event if event object is of IncomingEvent type.
  def dispatch(event)
    # Add all before-callback stuff to our chain, then the callback itself last
    chain = []
    chain.push @before_filters[:incoming_any] if Net::YAIL::IncomingEvent === event
    chain.push @before_filters[event.type]
    chain.push @callback[event.type]
    chain.flatten!
    chain.compact!

    # Run each filter in the chain, exiting early if event was handled
    for filter in chain
      filter.call(event)
      return if event.handled?
    end

    # Legacy handler - return if true, since that's how the old system works
    return if legacy_process_event(event)

    # Add all after-callback stuff to a new chain
    chain = []
    chain.push @after_filters[event.type]
    chain.push @after_filters[:incoming_any] if Net::YAIL::IncomingEvent === event
    chain.flatten!
    chain.compact!

    # Run all after-filters blindly - none can affect callback, so after-filters can't set handled to true
    chain.each {|filter| filter.call(event)}
  end

  # Handles magic listener setup methods: on_xxx, hearing_xxx, heard_xxx, saying_xxx, and said_xxx
  def method_missing(name, *args, &block)
    method = nil
    event_type = nil

    case name
      when /^on_(.*)$/
        method = :set_callback
        event_type = :"incoming_#{$1}"

      when /^hearing_(.*)$/
        method = :before_filter
        event_type = :"incoming_#{$1}"

      when /^heard_(.*)$/
        method = :after_filter
        event_type = :"incoming_#{$1}"

      when /^saying_(.*)$/
        method = :before_filter
        event_type = :"outgoing_#{$1}"

      when /^said_(.*)$/
        method = :after_filter
        event_type = :"outgoing_#{$1}"
    end

    # Magic methods MUST have an arg or a block!
    filter_or_callback_method = block_given? ? block : args.shift

    # If we didn't match a magic method signature, or we don't have the expected parameters, call
    # parent's method_missing.  Just to be safe, we also return, in case YAIL one day subclasses
    # from something that handles some method_missing stuff.
    unless (method && event_type) || args.length.zero?
      super
      return
    end

    self.call(method, filter_or_callback_method)
  end
end

end
