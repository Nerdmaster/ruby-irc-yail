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
require 'net/yail/dispatch'

# This tells us our version info.
require 'net/yail/yail-version'

# Finally, real classes to include!
require 'net/yail/event'
require 'net/yail/handler'

# If a thread crashes, I want the app to die.  My threads are persistent, not
# temporary.
Thread.abort_on_exception = true

module Net

# This library is based on the initial release of IRCSocket with a tiny bit
# of plagarism of Ruby-IRC.
#
# Need an example?  For a separate project you can play with that relies on Net::YAIL, check out
# https://github.com/Nerdmaster/superloud.  This is based on the code in the examples directory,
# but is easier to clone, run, and tinker with because it's a separate github project.
#
# My aim here is to build something that is still fairly simple to use, but
# powerful enough to build a decent IRC program.
#
# This is far from complete, but it does successfully power a relatively
# complicated bot, so I believe it's solid and "good enough" for basic tasks.
#
# =Events overview
#
# YAIL at its core is an event handler with some logic specific to IRC socket messages.  BaseEvent
# is the parent of all event objects.  An event is run through various pre-callback filters, a
# single callback, and post-callback filters.  Up until the callback is hit, the handler
# "chain" can be stopped by calling the event's .handled! method.  It is generally advised against
# doing this, as it will stop things like post-callback stats gathering and similar plugin-friendly
# features, but it does make sense in certain situations (an "ignore user" module, for instance).
#
# The life of a typical event, such as the one generated when a server message is parsed into a Net::YAIL::IncomingEvent object:
#
# * If the event hasn't been handled, the event's callback is run
# * If the event hasn't been handled, legacy handlers are run if any are registered (TO BE REMOVED IN 2.0)
#   * Legacy handlers can return true to end the chain, much like calling <tt>BaseEvent#handle!</tt> on an event object
# * If the event hasn't been handled, all "after filters" are run (these cannot set an event as having been handled)
#
# ==Callbacks and Filters
#
# Callbacks and filters are basically handlers for a given event.  The difference in a callback
# and filter is explained above (1 callback per event, many filters), but at their core they are
# just code that handles some aspect of the event.
#
# Handler methods must receive a block of code.  This can be passed in as a simple Ruby block, or
# manually created via Proc.new, lambda, Foo.method(:bar), etc.  The <tt>method</tt> parameter of
# all the handler methods is optional so that, as mentioned, a block can be used instead of a Proc.
#
# The handlers, when fired, will yield the event object containing all relevant data for the event.
# See the examples below for a basic idea.
#
# To register an event's callback, you have the following options:
# * <tt>set_callback(event_type, method = nil, &block)</tt>: Sets the event type's callback, clobbering any
#   existing callback for that event type.
# * <tt>on_xxx(method = nil, &block)</tt>: For incoming events only, this is a shortcut for <tt>set_callback</tt>.
#   The "xxx" must be replaced by the incoming event's short type name.  For example,
#   <tt>on_welcome {|event| ...}</tt> would be used in place of <tt>set_callback(:incoming_welcome, xxx)</tt>.
#
# To register a before- or after-callback filter, the following methods are available:
# * <tt>before_filter(event_type, method = nil, &block)</tt>: Sets a before-callback filter, adding it to
#   the current list of before-callback filters for the given event type.
# * <tt>after_filter(event_type, method = nil, &block)</tt>: Sets an after-callback filter, adding it to
#   the current list of after-callback filters for the given event type.
# * <tt>hearing_xxx(method = nil, &block)</tt>: Adds a before-callback filter for the given incoming event
#   type, such as <tt>hearing_msg {|event| ...}</tt>
# * <tt>heard_xxx(method = nil, &block)</tt>: Adds an after-callback filter for the given incoming event
#   type, such as <tt>heard_msg {|event| ...}</tt>
# * <tt>saying_xxx(method = nil, &block)</tt>: Adds a before-callback filter for the given outgoing event
#   type, such as <tt>saying_mode {|event| ...}</tt>
# * <tt>said_xxx(method = nil, &block)</tt>: Adds an after-callback filter for the given outgoing event
#   type, such as <tt>said_act {|event| ...}</tt>
#
# ===Conditional Filtering
#
# For some situations, you want your filter to only be called if a certain condition is met.  Enter conditional filtering!
# By using this exciting feature, you can set up handlers and callbacks which only trigger when certain conditions are
# met.  Be warned, though, this can get confusing....
#
# Conditions can be added to any filter method, but should **never** be used on the callback, since *there can be only one*.
# To add a filter, you simply supply a hash with a key of either `:if` or `:unless`, and a value which is either another
# hash of conditions, or a proc.
#
# If a proc is sent, it will be a method that is called and passed the event object.  If the proc returns true, an `:if`
# condition is met and un `:unless` condition is not met.  If a condition is not met, the filter is skipped entirely.
#
# If a hash is sent, each key is expected to be an attribute on the event object.  It's similar to a lambda where you
# return true if each attribute equals the value in the hash.  For instance, `:if => {:message => "food", :nick => "Simon"}`
# is the same as `:if => lambda {|e| e.message == "food" && e.nick == "Simon"}`.
#
# ==Incoming events
#
# *All* incoming events will have, at the least, the following methods:
# * <tt>raw</tt>: The raw text sent by the IRC server
# * <tt>msg</tt>: The parsed IRC message (Net::YAIL::MessageParser instance)
# * <tt>server?</tt>: Boolean flag.  True if the message was generated by the server alone, false if it
#   was generated by some kind of user action (such as a PRIVMSG sent from somebody else)
# * <tt>from</tt>: Originator of message: user's nickname if a user message, server name otherwise
#
# Additionally, *all messages originated by another IRC user* will have these methods:
# * <tt>fullname</tt>: The full username ("Nerdmaster!jeremy@nerdbucket.com", for instance)
# * <tt>nick</tt>: The short nickname of a user ("Nerdmaster", for instance) - this will be the
#   same as <tt>event.from</tt>, but obviously only for user-initiated events.
#
# Messages sent by the server that weren't initiated by a user will have <tt>event.servername</tt>,
# which is merely the name of the server, and will be the same as <tt>event.from</tt>.
#
# When in doubt, you can always build a filter for a particular event that spits out all its
# non-base methods:
#     yail.hearing_xxx {|e| puts e.public_methods - Net::YAIL::BaseEvent.instance_methods}
#
# This should be a comprehensive list of all incoming events and what additional attributes the
# object will expose.
#
# * <tt>:incoming_any</tt>: A catch-all handler useful for reporting or doing top-level filtering.
#   Before- and after-callback filters can run for all events by adding them to :incoming_any, but
#   you cannot register a callback, as the event's type determines its callback.  :incoming_any
#   before-callback filters can stop an event from happening on a global scale, so be careful when
#   deciding to do anything "clever" here.
# * <tt>:incoming_error</tt>: A server error of some kind happened.  <tt>event.message</tt> gives you the message sent
#   by the server.
# * <tt>:incoming_ping</tt>: PING from server.  YAIL handles this by default, so if you override the
#   handler, you MUST send a PONG response or the server will close your connection.  <tt>event.message</tt>
#   may have a PING "message" in it.  The return PONG should send out the same message as the PING
#   received.
# * <tt>:incoming_topic_change</tt>: The topic of a channel was changed.  <tt>event.channel</tt> gives you the
#   channel in which the change occurred, while <tt>event.message</tt> gives you the message, i.e. the new topic.
# * <tt>:incoming_numeric_###</tt>: If you want, you can set up your handlers for numeric events by number,
#   but you'll have a much easier time looking at the eventmap.yml file included in the lib/net/yail
#   directory.  You can create an incoming handler for any event in that file.  The event names will
#   be <tt>:incoming_xxx</tt>, where "xxx" is the text of the event.  For instance, you could use
#   <tt>set_callback(:incoming_liststart) {|event| ...}</tt> to handle the 321 numeric message, or just
#   <tt>on_liststart {|event| ...}</tt>.  Exposes <tt>event.target</tt>, <tt>event.parameters</tt>,
#   <tt>event.message</tt>, and <tt>event.numeric</tt>.  You may have to experiment with different
#   numerics to see what this data actually means for a given event.
# * <tt>:incoming_invite</tt>: INVITE message sent from a user to request your presence in another channel.
#   Exposes <tt>event.channel</tt>, the channel in question, and <tt>event.target</tt>, which should always be
#   your nickname.
# * <tt>:incoming_join</tt>: A user joined a channel.  <tt>event.channel</tt> tells you the channel.
# * <tt>:incoming_part</tt>: A user left a channel.  <tt>event.channel</tt> tells you the channel, and
#   <tt>event.message</tt> will contain a message if the user gave one.
# * <tt>:incoming_kick</tt>: A user was kicked from a channel.  <tt>event.channel</tt> tells you
#   the channel, <tt>event.target</tt> tells you the nickname of the kicked party, and
#   <tt>event.message</tt> will contain a message if the kicking party gave one.
# * <tt>:incoming_quit</tt>: A user quit the server.  <tt>event.message</tt> will have details, if the
#   user provided a quit message.
# * <tt>:incoming_nick</tt>: A user changed nicknames.  <tt>event.message</tt> will contain the new
#   nickname.
# * <tt>:incoming_mode</tt>: A user or server can initiate this, and this is the most screwy event
#   in YAIL.  This needs an overhaul and will hopefully change by 2.0, but for now I take the raw
#   mode strings, such as "+bivv" and put them in <tt>event.message</tt>.  All arguments of the
#   mode strings get stored as individual records in the <tt>event.targets</tt> array.  For modes
#   like "+ob", the first entry in targets will be the user given ops, and the second will be the
#   ban string.  I hope to overhaul this prior to 2.0, so if you rely on mode parsing, be warned.
# * <tt>:incoming_msg</tt>: A "standard" PRIVMSG event (i.e., not CTCP).  <tt>event.message</tt> will
#   contain the message, obviously.  If the message is to a channel, <tt>event.channel</tt>
#   will contain the channel name, <tt>event.target</tt> will be nil, and <tt>event.pm?</tt> will
#   be false.  If the message is sent to a user (the client running Net::YAIL),
#   <tt>event.channel</tt> will be nil, <tt>event.target</tt> will have the user name, and
#   <tt>event.pm?</tt> will be true.
# * <tt>:incoming_ctcp</tt>: The behavior of <tt>event.target</tt>, <tt>event.channel</tt>, and
#   <tt>event.pm?</tt> will remain the same as for <tt>:incoming_msg</tt> events.
#   <tt>event.message</tt> will contain the CTCP message.
# * <tt>:incoming_act</tt>: The behavior of <tt>event.target</tt>, <tt>event.channel</tt>, and
#   <tt>event.pm?</tt> will remain the same as for <tt>:incoming_msg</tt> events.
#   <tt>event.message</tt> will contain the ACTION message.
# * <tt>:incoming_notice</tt>: The behavior of <tt>event.target</tt>, <tt>event.channel</tt>, and
#   <tt>event.pm?</tt> will remain the same as for <tt>:incoming_msg</tt> events.
#   <tt>event.message</tt> will contain the NOTICE message.
# * <tt>:incoming_ctcp_reply</tt>: The behavior of <tt>event.target</tt>, <tt>event.channel</tt>,
#   and <tt>event.pm?</tt> will remain the same as for <tt>:incoming_msg</tt> events.
#   <tt>event.message</tt> will contain the CTCP reply message.
# * <tt>:incoming_unknown</tt>: This should NEVER happen, but just in case, it's there.  Enjoy!
#
# ==Output API
#
# All output API calls create a Net::YAIL::OutgoingEvent object and dispatch that event.  After
# before-callback filters are processed, assuming the event wasn't handled, the callback will send
# the message out to the IRC socket.  If you choose to override the callback for outgoing events,
# rather than using filters, you will have to print the data to the socket yourself.
#
# The parameters for the API calls will match what the outgoing event object exposes as attributes,
# so if there were an API call for "foo(bar, baz)", it would generate an outgoing event of type
# :outgoing_foo.  The data you passed in as "bar" would be available via <tt>event.bar</tt> in a handler.
#
# There is also an :outgoing_any event type that can be used for global filtering much like the
# :incoming_any filtering.
#
# The <tt>:outgoing_begin_connection</tt> event callback should never be overwritten.  It exists so
# you can add filters before or after the initial flurry of messages to the server (USER, PASS, and
# NICK), but it is really an internal "helper" event.  Overwriting it means you will need to write
# your own code to log in to the server.
#
# This should be a comprehensive list of all outgoing methods and parameters:
#
# * <tt>msg(target, message)</tt>: Send a PRIVMSG to the given target (channel or nickname)
# * <tt>ctcp(target, message)</tt>: Sends a PRIVMSG to the given target with its message wrapped in
#   ASCII character 1, signifying use of client-to-client protocol.
# * <tt>act(target, message)</tt>: Sends a PRIVMSG to the given target with its message wrapped in the
#   CTCP "action" syntax.  A lot of IRC clients use "/me" to do this command.
# * <tt>privmsg(target, message)</tt>: Sends a raw, unbuffered PRIVMSG to the given target - primarily
#   useful for filtering, as msg, act, and ctcp all eventually call this handler.
# * <tt>notice(target, message)</tt>: Sends a notice message to the given target
# * <tt>ctcpreply(target, message)</tt>: Sends a notice message wrapped in ASCII 1 to signify a CTCP reply.
# * <tt>mode(target, [modes, [objects]])</tt>: Sets or requests modes for the given target
#   (channel or user).  The list of modes, if present, is applied to the target and objects if
#   present.  Modes in YAIL need some work, but here are some basic examples:
#   * <tt>mode("#channel", "+b", "Nerdmaster!*@*")</tt>: bans anybody with the nickname
#     "Nerdmaster" from subsequently joining #channel.
#   * <tt>mode("#channel")</tt>: Requests a list of modes on #channel
#   * <tt>mode("#channel", "-k")</tt>: Removes the key for #channel
# * <tt>join(channel, [password])</tt>: Joins the given channel with an optional password (channel key)
# * <tt>part(channel, [message])</tt>: Leaves the given channel, with an optional message specified on part
# * <tt>quit([message])</tt>: Leaves the server with an optional message.  Note that some servers will
#   not display your quit message due to spam issues.
# * <tt>nick(nick)</tt>: Changes your nickname, and updates YAIL @me variable if successful
# * <tt>user(username, hostname, servername, realname)</tt>: Sets up your information upon joining
#   a server.  YAIL should generally take care of this for you in the default :outgoing_begin_connection
#   callback.
# * <tt>pass(password)</tt>: Sends a server password, not to be confused with a channel key.
# * <tt>oper(user, password)</tt>: Authenticates a user as an IRC operator for the server.
# * <tt>topic(channel, [new_topic])</tt>: With no new_topic, returns the topic for a given channel.
#   If new_topic is present, sets the topic instead.
# * <tt>names([channel])</tt>: Gets a list of all users on the network or a specific channel if specified.
#   The channel parameter can actually contain a comma-separated list of channels if desired.
# * <tt>list([channel, [server]]</tt>: Shows all channels on the server.  <tt>channel</tt> can
#   contain a comma-separated list of channels, which will restrict the list to the given channels.
#   If <tt>server</tt> is present, the request is forwarded to the given server.
# * <tt>invite(nick, channel)</tt>: Invites a user to the given channel.
# * <tt>kick(nick, channel, [message])</tt>: Kicks the given user from the given channel with an optional message
# * <tt>whois(nick, [server]): Issues a WHOIS command for the given nickname with an optional server.
#
# =Simple Example
#
# You should grab the source from github (https://github.com/Nerdmaster/ruby-irc-yail) and look at
# the examples directory for more interesting (but still simple) examples.  But to get you started,
# here's a really dumb, contrived example:
#
#     require 'rubygems'
#     require 'net/yail'
#
#     irc = Net::YAIL.new(
#       :address    => 'irc.someplace.co.uk',
#       :username   => 'Frakking Bot',
#       :realname   => 'John Botfrakker',
#       :nicknames  => ['bot1', 'bot2', 'bot3']
#     )
#
#     # Automatically join #foo when the server welcomes us
#     irc.on_welcome {|event| irc.join("#foo") }
#
#     # Store the last message and person who spoke - this is a filter as it doesn't need to be
#     # "the" definitive code run for the event
#     irc.hearing_msg {|event| @last_message = {:nick => event.nick, :message => event.message} }
#
#     # Loops forever until CTRL+C
#     irc.start_listening!
class YAIL
  include Net::IRCEvents::Magic
  include Net::IRCEvents::Defaults
  include Net::IRCOutputAPI
  include Net::IRCEvents::LegacyEvents
  include Dispatch

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

    #############################################
    # TODO: DEPRECATED!!
    #
    # TODO: Delete this!
    #############################################
    @legacy_handlers = Hash.new

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
      @log.level = Logger::INFO

      if (options[:silent] || options[:loud])
        @log.warn '[DEPRECATED] - passing :silent and :loud options to constructor are deprecated as of 1.4.1'
      end

      # Convert old-school options into logger stuff
      @log.level = Logger::DEBUG if @log_loud
      @log.level = Logger::FATAL if @log_silent
    end

    # Read in map of event numbers and names.  Yes, I stole this event map
    # file from RubyIRC and made very minor changes....  They stole it from
    # somewhere else anyway, so it's okay.
    eventmap = "#{File.dirname(__FILE__)}/yail/eventmap.yml"
    @event_number_lookup = File.open(eventmap) { |file| YAML::load(file) }.invert

    if @io
      @socket = @io
    else
      prepare_tcp_socket
    end

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
    # TODO: This REALLY doesn't belong here!  This is saying everybody who uses the lib wants
    #       CTRL+C to end the app at the YAIL level.  Not necessarily true outside bot-land.
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
    # Set up callbacks for slightly more important things than reporting - note that these should
    # eventually be changed as they don't belong in the core of YAIL.  Note that since these are
    # callbacks, the user can very easily overwrite them, at least.
    on_nicknameinuse self.method(:_nicknameinuse)
    on_namreply self.method(:_namreply)

    # Set up truly core handlers/filters - these shouldn't be overridden unless users like to get
    # their hands dirty
    set_callback(:outgoing_begin_connection, self.method(:out_begin_connection))
    on_ping self.method(:magic_ping)

    # Nick change magically setting @me is necessary as a filter - user can handle the event and do
    # anything he wants, but this should still run.
    hearing_nick self.method(:magic_nick)

    # Welcome magic also sets @me magically, so it's a filter
    hearing_welcome self.method(:magic_welcome)

    # Outgoing handlers are what make this app actually work - users who override these have to
    # do so very explicitly (no "on_xxx" magic) and will probably break stuff.  Use filters instead!

    # These three need magic to buffer their output, so can't use our simpler create_command system
    set_callback :outgoing_msg, self.method(:magic_out_msg)
    set_callback :outgoing_ctcp, self.method(:magic_out_ctcp)
    set_callback :outgoing_act, self.method(:magic_out_act)

    # WHOIS is tricky due to how weird its argument positioning is, so can't use create_command, either
    set_callback :outgoing_whois, self.method(:magic_out_whois)

    # All PRIVMSG events eventually hit this - it's a legacy thing, and kinda dumb, but there you
    # have it.  Just sends a raw PRIVMSG out to the socket.
    create_command :privmsg, "PRIVMSG :target ::message", :target, :message

    # The rest of these should be fairly obvious
    create_command :notice, "NOTICE :target ::message", :target, :message
    create_command :ctcpreply, "NOTICE :target :\001:message\001", :target, :message
    create_command :mode,   "MODE", :target, " :target", :modes, " :modes", :objects, " :objects"
    create_command :join,   "JOIN :channel", :channel, :password, " :password"
    create_command :part,   "PART :channel", :channel, :message, " ::message"
    create_command :quit,   "QUIT", :message, " ::message"
    create_command :nick,   "NICK ::nick", :nick
    create_command :user,   "USER :username :hostname :servername ::realname", :username, :hostname, :servername, :realname
    create_command :pass,   "PASS :password", :password
    create_command :oper,   "OPER :user :password", :user, :password
    create_command :topic,  "TOPIC :channel", :channel, :topic, " ::topic"
    create_command :names,  "NAMES", :channel, " :channel"
    create_command :list,   "LIST", :channel, " :channel", :server, " :server"
    create_command :invite, "INVITE :nick :channel", :nick, :channel
    create_command :kick,   "KICK :channel :nick", :nick, :channel, :message, " ::message"
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
    return @socket.readpartial(OpenSSL::Buffering::BLOCK_SIZE).split($/).collect {|message| message}
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
      # Message must have one of \r or \n at the end of it, otherwise it's a partial command and
      # we need to hang onto it to join it with the next message
      if message !~ /[\r\n]+$/
        @prepend_message ||= ""
        @prepend_message += message.dup
        next
      end

      # If we had a partial message recently, attach it to the new message and clear it out
      if @prepend_message
        message = @prepend_message + message
        @prepend_message = nil
      end

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
      # Possible fix for SSL one-message-behind issue from BP - thanks!
      #
      # If SSL, we just assume we're ready so we're always grabbing the latest message(s) from the
      # socket.  I don't know if this will have any side-effects, but it seems to work in at least
      # one situation, sooo....
      ready = true if @ssl
      unless ready
        # if no data is coming in, don't block the socket!  To allow for mocked IO objects, allow
        # a non-IO to let us know if it's ready
        ready = @socket.kind_of?(IO) ? Kernel.select([@socket], nil, nil, 0) : @socket.ready?
      end

      read_incoming_data if ready

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
          event = Net::YAIL::IncomingEvent.parse(lines.shift)
          dispatch(event)
        end

        lines = nil
      end

      sleep 0.05
    end
  end

  # Grabs one message for each target in the private message buffer, removing
  # messages from @privmsg_buffer.  Returns an array of events to process
  def pop_privmsgs
    privmsgs = []

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

        privmsgs.push @privmsg_buffer[target].shift
      end
    end

    return privmsgs
  end

  # Checks for new private messages, and dispatches all that are gathered from pop_privmsgs, if any
  def check_privmsg_output
    privmsgs = pop_privmsgs
    @next_message_time = Time.now + @throttle_seconds unless privmsgs.empty?
    privmsgs.each {|event| dispatch event}
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
  def before_filter(event_type, method = nil, conditions = {}, &block)
    filter = block_given? ? block : method
    if filter
      event_type = numeric_event_type_convert(event_type)
      @before_filters[event_type] ||= Array.new
      @before_filters[event_type].unshift(Net::YAIL::Handler.new(filter, conditions))
    end
  end

  # Sets up the callback for the given incoming event type.  Note that unlike Net::YAIL 1.4.x and prior, there is no
  # longer a concept of multiple callbacks!  Use filters for that kind of functionality.  Think this way: the callback
  # is the action that takes place when an event hits.  Filters are for functionality related to the event, but not
  # the definitive callback - logging, filtering messages, stats gathering, ignoring messages from a set user, etc.
  def set_callback(event_type, method = nil, conditions = {}, &block)
    callback = block_given? ? block : method
    event_type = numeric_event_type_convert(event_type)
    @callback[event_type] = Net::YAIL::Handler.new(callback, conditions)
    @callback.delete(event_type) unless callback
  end

  # Prepends the given block or method to the after_filters array for the given type.  After-filters are called after
  # the event callback has run, and cannot stop other after-filters from running.  Best used for logging or statistics
  # gathering.
  def after_filter(event_type, method = nil, conditions = {}, &block)
    filter = block_given? ? block : method
    if filter
      event_type = numeric_event_type_convert(event_type)
      @after_filters[event_type] ||= Array.new
      @after_filters[event_type].unshift(Net::YAIL::Handler.new(filter, conditions))
    end
  end

  # Reports may not get printed in the proper order since I scrubbed the
  # IRCSocket report capturing, but this is way more straightforward to me.
  def report(*lines)
    @log.warn '[DEPRECATED] - Net::YAIL#report is deprecated and will be removed in 2.0 - use the logger (e.g., "@irc.log.info") instead'
    lines.each {|line| @log.info line}
  end

  # Converts events that are numerics into the internal "incoming_numeric_xxx" format
  def numeric_event_type_convert(type)
    if (type.to_s =~ /^incoming_(.*)$/)
      number = @event_number_lookup[$1].to_i
      type = :"incoming_numeric_#{number}" if number > 0
    end

    return type
  end

  # Handles magic listener setup methods: on_xxx, hearing_xxx, heard_xxx, saying_xxx, and said_xxx
  def method_missing(name, *args, &block)
    method = nil
    event_type = nil

    case name.to_s
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
    conditions = args.shift || {}

    # If we didn't match a magic method signature, or we don't have the expected parameters, call
    # parent's method_missing.  Just to be safe, we also return, in case YAIL one day subclasses
    # from something that handles some method_missing stuff.
    return super if method.nil? || event_type.nil? || args.length > 0

    self.send(method, event_type, filter_or_callback_method, conditions)
  end
end

end
