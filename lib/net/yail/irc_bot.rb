require 'rubygems'
require 'net/yail'
require 'net/yail/report_events'

# My abstraction from adapter to a real bot.
class IRCBot
  include Net::IRCEvents::Reports

  attr_reader :irc

  # Creates a new bot.  Options are anything you can pass to the Net::YAIL constructor:
  # * <tt>:irc_network</tt>: Name/IP of the IRC server - backward-compatibility hack, and is
  #   ignored if :address is passed in
  # * <tt>:address</tt>: Name/IP of the IRC server
  # * <tt>:port</tt>: Port number, defaults to 6667
  # * <tt>:username</tt>: Username reported to server
  # * <tt>:realname</tt>: Real name reported to server
  # * <tt>:nicknames</tt>: Array of nicknames to cycle through
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
    @start_time = Time.now
    @options = options

    # Set up some friendly defaults
    @options[:address]    ||= @options.delete(:irc_network)
    @options[:channels]   ||= []
    @options[:port]       ||= 6667
    @options[:username]   ||= 'IRCBot'
    @options[:realname]   ||= 'IRCBot'
    @options[:nicknames]  ||= ['IRCBot1', 'IRCBot2', 'IRCBot3']
  end

  # Returns a string representing uptime
  def get_uptime_string
    uptime = (Time.now - @start_time).to_i
    seconds = uptime % 60
    minutes = (uptime / 60) % 60
    hours = (uptime / 3600) % 24
    days = (uptime / 86400)

    str = []
    str.push("#{days} day(s)") if days > 0
    str.push("#{hours} hour(s)") if hours > 0
    str.push("#{minutes} minute(s)") if minutes > 0
    str.push("#{seconds} second(s)") if seconds > 0

    return str.join(', ')
  end

  # Creates the socket connection and registers the (very simple) default
  # welcome handler.  Subclasses should build their hooks in
  # add_custom_handlers to allow auto-creation in case of a restart.
  def connect_socket
    @irc = Net::YAIL.new(@options)
    setup_reporting(@irc)

    # Simple hook for welcome to allow auto-joining of the channel
    @irc.on_welcome self.method(:welcome)

    add_custom_handlers
  end

  # To be subclassed - this method is a nice central location to allow the
  # bot to register its handlers before this class takes control and hits
  # the IRC network.
  def add_custom_handlers
    raise "You must define your handlers in add_custom_handlers, or else " +
        "explicitly override with an empty method."
  end

  # Enters the socket's listening loop(s)
  def start_listening
    # If socket's already dead (probably couldn't connect to server), don't
    # try to listen!
    if @irc.dead_socket
      $stderr.puts "Dead socket, can't start listening!"
    end

    @irc.start_listening
  end

  # Tells us the main app wants to just wait until we're done with all
  # thread processing, or get a kill signal, or whatever.  For now this is
  # basically an endless loop that lets the threads do their thing until
  # the socket dies.  If a bot wants, it can handle :irc_loop to do regular
  # processing.
  def irc_loop
    while true
      until @irc.dead_socket
        sleep 15
        @irc.dispatch Net::YAIL::CustomEvent.new(:type => :irc_loop)
        Thread.pass
      end

      # Disconnected?  Wait a little while and start up again.
      sleep 30
      @irc.stop_listening
      self.connect_socket
      start_listening
    end
  end

  private
  # Basic handler for joining our channels upon successful registration
  def welcome(event)
    @options[:channels].each {|channel| @irc.join(channel) }
  end

  ################
  # Helpful wrappers
  ################

  # Wraps Net::YAIL.log
  def log
    @irc.log
  end

  # Wraps Net::YAIL.me
  def bot_name
    @irc.me
  end

  # Wraps Net::YAIL.msg
  def msg(*args)
    @irc.msg(*args)
  end

  # Wraps Net::YAIL.act
  def act(*args)
    @irc.act(*args)
  end

  # Wraps Net::YAIL.join
  def join(*args)
    @irc.join(*args)
  end

  # Wraps Net::YAIL.report
  def report(*args)
    @irc.report(*args)
  end

  # Wraps Net::YAIL.nick
  def nick(*args)
    @irc.nick(*args)
  end
end
