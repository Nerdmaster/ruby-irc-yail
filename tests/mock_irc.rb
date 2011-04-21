# An IO-like class that does IRC-like magic for us
class MockIRC
  SERVER = "fakeirc.org"
  USERHOST = "fakey@nerdbucket.com"

  # Init - just call super and set up a couple vars
  def initialize(*args)
    super
    @connected = false
    @logged_in = false
    @closed = false
    @server = ''
    @output = []
    @mutex = Mutex.new
  end

  # All output sent to the IO uses puts in YAIL.  I hope.
  def puts(*args)
    @mutex.synchronize do
      for string in args
        handle_command(string.strip)
      end
    end
    return nil
  end

  # Lets us know if we are an open "socket" or not - if the socket is closed *and* we're out of
  # output, we are done
  def eof
    @mutex.synchronize do
      return @output.empty? && @closed
    end
  end

  alias_method :eof?, :eof

  # Pulls the first element off of @output
  def gets
    output = nil
    @mutex.synchronize do
      output = @output.shift
    end

    puts "WTF NO DATA!" if !output

    return output
  end

  # Hack to let YAIL know if we have data to read
  def ready?
    return @output.empty? ? nil : true
  end

  # All the magic goes here
  def handle_command(cmd)
    unless @connected
      handle_connected(cmd)
      return
    end

    unless @logged_in
      handle_nick(cmd)
      return
    end

    # TODO: Handle other commands
    case cmd
      when /^QUIT/
        add_output ":#{SERVER} NOTICE #{@nick} :See ya, jerk"
        @closed = true

      when /^NICK/    then handle_nick(cmd)
      when /^JOIN/    then handle_join(cmd)
      when /^MODE/    then handle_mode(cmd)
    end
  end

  # Handles a connection command (USER) or errors
  def handle_connected(cmd)
    if cmd =~ /^USER (\S+) (\S+) (\S+) :(.*)$/
      add_output ":#{SERVER} NOTICE AUTH :*** Looking up your hostname..."
      @connected = true
      return
    end

    add_output ":#{SERVER} ERROR :You need to authenticate or something"
  end

  # Dumb handling of a MODE command
  def handle_mode(cmd)
    # Eventually this could be used to make really interesting mode messages
    cmd =~ /^MODE(\s+\S+)?(\s+\S+)?(\s+\S+)?$/

    add_output ":#{@nick}!#{USERHOST} MODE#{$2}#{$3}"
  end

  # Handles a NICK request, but no error if no nick set - not sure what a real server does here
  def handle_nick(cmd)
    unless cmd =~ /^NICK :(.*)$/
      return
    end

    nick = $1

    if "InUseNick" == nick
      add_output ":#{SERVER} 433 * #{nick} :Nickname is already in use."
      return
    end

    oldnick = @nick
    @nick = nick

    unless @logged_in
      add_output "NOTICE AUTH :*** Looking up your hostname",
                 ":#{SERVER} NOTICE #{@nick} :*** You are exempt from user limits. congrats.",
                 ":#{SERVER} 001 #{@nick} :Welcome to the Fakey-fake Internet Relay Chat Network #{@nick}",
                 ":#{SERVER} 002 #{@nick} :Your host is #{SERVER}[0.0.0.0/6667], running version mock-irc-1.7.7",
                 ":#{SERVER} 003 #{@nick} :This server was created Nov 21 2009 at 21:20:48",
                 ":#{SERVER} 004 #{@nick} #{SERVER} mock-irc-1.7.7 foobar barbaz bazfoo",
                 ":#{SERVER} 005 #{@nick} CALLERID CASEMAPPING=rfc1459 DEAF=D KICKLEN=160 MODES=4 NICKLEN=15 PREFIX=(ohv)@%+ STATUSMSG=@%+ TOPICLEN=350 NETWORK=Fakeyfake MAXLIST=beI:25 MAXTARGETS=4 CHANTYPES=#& :are supported by this server",
                 ":#{SERVER} 251 #{@nick} :There are 0 users and 24 invisible on 1 servers",
                 ":#{SERVER} 254 #{@nick} 3 :channels formed",
                 ":#{SERVER} 255 #{@nick} :I have 24 clients and 0 servers",
                 ":#{SERVER} 265 #{@nick} :Current local users: 24  Max: 30",
                 ":#{SERVER} 266 #{@nick} :Current global users: 24  Max: 33",
                 ":#{SERVER} 250 #{@nick} :Highest connection count: 30 (30 clients) (4215 connections received)",
                 ":#{SERVER} 375 #{@nick} :- #{SERVER} Message of the Day - ",
                 ":#{SERVER} 372 #{@nick} :-           BOO!",
                 ":#{SERVER} 372 #{@nick} :-     Did I scare you?",
                 ":#{SERVER} 372 #{@nick} :-        BOO again!",
                 ":#{SERVER} 376 #{@nick} :End of /MOTD command."
      @logged_in = true
      return
    end

    # Hostmask is faked, but otherwise this is the message we send in response to a nick change
    add_output ":#{oldnick}!#{USERHOST} NICK :#{@nick}"
  end

  def handle_join(cmd)
    unless cmd =~ /^JOIN (\S*)( (\S*))?$/
      return
    end

    channel = $1
    pass = $2
    if "#banned" == channel
      add_output ":#{SERVER} 474 #{@nick} #{channel}:Cannot join channel (+b)"
      return
    end

    add_output ":#{@nick}!#{USERHOST} JOIN :#{channel}",
               ":#{SERVER} 332 #{@nick} #{channel} :This is a topic, y'all!",
               ":#{SERVER} 333 #{@nick} #{channel} user!user@user.com 1291781166",
               ":#{SERVER} 353 #{@nick} = #{channel} :#{@nick} @Nerdmaster another_bot",
               ":#{SERVER} 366 #{@nick} #{channel} :End of /NAMES list."
  end

  # Sets up our internal string to add the given string arguments for a gets call to pull
  def add_output(*args)
    args.each {|arg| @output.push(arg + "\n")}
  end
end
