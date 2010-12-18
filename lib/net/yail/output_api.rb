module Net

# All output APIs live here.  In most cases, an outgoing handler will get a
# call, but will not be able to stop the socket output since that's sorta
# an essential part of this whole library.
#
# ==Argument Duping
#
# Output APIs dup incoming args before sending them off to handlers.  This
# is a mechanism that I think could be done better, but I can't figure a good
# way to do it at the moment.  The reason this is necessary is for a specific
# situation where a bot has an array of response messages, and needs to filter
# those messages.  A call to "msg(messages[rand(10)])" with a handler on :outgoing_msg
# that does something like <code>text.gsub!('a', '@')</code> (like a leetspeek
# filter) shouldn't destroy the original data in the messages array.
#
# This could be left up to the programmer, but it seems like something that
# a library should own - protecting the programmer for having to remember that
# sort of crap, especially if the app is calling msg, act, ctcp, etc. in
# various ways from multiple points in the code....
#
# ==Apologies, good sirs
# 
# If a method exists in this module, and it isn't the +raw+ method, chances
# are it's got a handler in the form of :outgoing_<method name>.  I am hoping
# I document all of those in the main Net::YAIL code, but if I miss one, I
# apologize.
module IRCOutputAPI
  # Spits a raw string out to the server - in case a subclass wants to do
  # something special on *all* output, please make all output go through this
  # method.  Don't use puts manually.  I will kill violaters.  Legally
  # speaking, that is.
  def raw(line, report = true)
    @socket.puts line
    report "bot: #{line.inspect}" if report
  end

  # Buffers the given event to be sent out when we are able to send something out to the given
  # target.  If buffering isn't turned on, the event will be processed in the next loop of outgoing
  # messages.
  def buffer_output(event)
    @privmsg_buffer_mutex.synchronize do
      @privmsg_buffer[event.target] ||= Array.new
      @privmsg_buffer[event.target].push event
    end
  end

  # Buffers an :outgoing_msg event.  Could be used to send any privmsg, but you're betting off
  # using act and ctcp shortcut methods for those types.  Target is a channel or username, text
  # is the message.
  def msg(target, text)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :msg, :target => target, :text => text)
  end

  # Buffers an :outgoing_ctcp event.  Target is user or channel, text is message.
  def ctcp(target, text)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :ctcp, :target => target, :text => text)
  end

  # Buffers an :outgoing_act event.  Target is user or channel, text is message.
  def act(target, text)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :act, :target => target, :text => text)
  end

  # Creates an output command and its handler.  If a block is given, that is used for the handler,
  # otherwise we take the last string in the args list and use that as a format string for building
  # the raw output.
  #
  # I hate the hackiness here, but it's so much easier than building all the methods manually,
  # and things like define_method seem to fall short with how much crap this needs to do.
  def create_command(command, *args, &block)
    handler = block_given? ? block : nil
    output_format = args.pop.gsub(/:(\w+)/, '#{event.\1}') unless handler

    args_string = args.collect {|arg| "#{arg} = ''"}.join(",")
    event_string = args.collect {|arg| ":#{arg} => #{arg}"}.join(",")
    command_code = %Q|
      def #{command}(#{args_string})
        dispatch Net::YAIL::OutgoingEvent.new(:type => #{command.inspect}, #{event_string})
      end
    |

    # Create the command function
    self.class.class_eval command_code

    # Not all commands are super-easy to handle with a single string, so we set up the handler
    # from the block if we got one
    if handler
      set_callback(command, block)
    else
      command_handler = :"magic_out_#{command}"
      handler_code = %Q|
        def #{command_handler}(event)
          raw "#{output_format}", false
        end
      |

      self.class.class_eval handler_code
      # At least setting the callback isn't a giant pile of dumb
      set_callback(command, command_handler)
    end
  end

  # Calls :outgoing_join handler and then raw JOIN message for a given channel
  def join(target, pass = '')
    # Dup strings so handler can filter safely
    target = target.dup
    pass = pass.dup

    handle(:outgoing_join, target, pass)

    text = "JOIN #{target}"
    text += " #{pass}" unless pass.empty?
    raw text
  end

  # Calls :outgoing_part handler and then raw PART for leaving a given channel
  # (with an optional message)
  def part(target, text = '')
    # Dup strings so handler can filter safely
    target = target.dup
    text = text.dup

    handle(:outgoing_part, target, text)

    request = "PART #{target}";
    request += " :#{text}" unless text.to_s.empty?
    raw request
  end

  # Calls :outgoing_quit handler and then raw QUIT message with an optional
  # reason
  def quit(text = '')
    # Dup strings so handler can filter safely
    text = text.dup

    handle(:outgoing_quit, text)

    request = "QUIT";
    request += " :#{text}" unless text.to_s.empty?
    raw request
  end

  # Calls :outgoing_nick handler and then sends raw NICK message to change
  # nickname.
  def nick(new_nick)
    # Dup strings so handler can filter safely
    new_nick = new_nick.dup

    handle(:outgoing_nick, new_nick)

    raw "NICK :#{new_nick}"
  end

  # Identifies ourselves to the server.  Calls :outgoing_user and sends raw
  # USER command.
  def user(username, myaddress, address, realname)
    # Dup strings so handler can filter safely
    username = username.dup
    myaddress = myaddress.dup
    address = address.dup
    realname = realname.dup

    handle(:outgoing_user, username, myaddress, address, realname)

    raw "USER #{username} #{myaddress} #{address} :#{realname}"
  end

  # Sends a password to the server.  This *must* be sent before NICK/USER.
  # Calls :outgoing_pass and sends raw PASS command.
  def pass(password)
    # Dupage
    password = password.dup

    handle(:outgoing_pass, password)
    raw "PASS #{password}"
  end

  # Sends an op request.  Calls :outgoing_oper and raw OPER command.
  def oper(user, password)
    # Dupage
    user = user.dup
    password = password.dup

    handle(:outgoing_oper, user, password)
    raw "OPER #{user} #{password}"
  end

  # Gets or sets the topic.  Calls :outgoing_topic and raw TOPIC command
  def topic(channel, new_topic = nil)
    # Dup for filter safety in outgoing handler
    channel = channel.dup
    new_topic = new_topic.dup unless new_topic.nil?

    handle(:outgoing_topic, channel, new_topic)
    output = "TOPIC #{channel}"
    output += " :#{new_topic}" unless new_topic.to_s.empty?
    raw output
  end

  # Gets a list of users and channels if channel isn't specified.  If channel
  # is specified, only shows users in that channel.  Will not show invisible
  # users or channels.  Calls :outgoing_names and raw NAMES command.
  def names(channel = nil)
    channel = channel.dup unless channel.nil?

    handle(:outgoing_names, channel)
    output = "NAMES"
    output += " #{channel}" unless channel.to_s.empty?
    raw output
  end

  # I don't know what the server param is for, but it's in the RFC.  If
  # channel is blank, lists all visible, otherwise just lists the channel in
  # question.  Calls :outgoing_list and raw LIST command.
  def list(channel = nil, server = nil)
    channel = channel.dup unless channel.nil?
    server = server.dup unless server.nil?

    handle(:outgoing_list, channel, server)
    output = "LIST"
    output += " #{channel}" if channel
    output += " #{server}" if server
    raw output
  end

  # Invites a user to a channel.  Calls :outgoing_invite and raw INVITE
  # command.
  def invite(nick, channel)
    channel = channel.dup
    server = server.dup

    handle(:outgoing_invite, nick, channel)
    raw "INVITE #{nick} #{channel}"
  end

  # Kicks the given user from the channel with the optional comment.  Calls
  # :outgoing_kick and issues a raw KICK command.
  def kick(nick, channel, comment = nil)
    nick = nick.dup
    channel = channel.dup
    comment = comment.dup unless comment.nil?

    handle(:outgoing_kick, nick, channel, comment)
    output = "KICK #{channel} #{nick}"
    output += " :#{comment}" unless comment.to_s.empty?
    raw output
  end

end

end
