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

  # Creates an output command and its handler.  output_base is a template of the command without
  # any conditional arguments (for simple commands this is the full template).  args is a list of
  # argument symbols to determine how the event is built and handled.  If an argument symbol is
  # followed by a string, that string is conditionally appended to the output in the handler if the
  # event has data for that argument.
  #
  # I hate the hackiness here, but it's so much easier to build the commands and handlers with an
  # ugly one-liner than manually, and things like define_method seem to fall short with how much
  # crap this needs to do.
  def create_command(command, output_base, *opts)
    event_opts = lambda {|text| text.gsub(/:(\w+)/, '#{event.\1}') }

    output_base = event_opts.call(output_base)

    # Create a list of actual arg symbols and templates for optional args
    args = []
    optional_arg_templates = {}
    last_symbol = nil
    for opt in opts
      case opt
      when Symbol
        args.push opt
        last_symbol = opt
      when String
        raise ArgumentError.new("create_command optional argument must have an argument symbol preceding them") unless last_symbol
        optional_arg_templates[last_symbol] = event_opts.call(opt)
        last_symbol = nil
      end
    end

    # Format strings for command args and event creation
    event_string = args.collect {|arg| ":#{arg} => #{arg}"}.join(",")
    event_string = ", #{event_string}" unless event_string.empty?
    args_string = args.collect {|arg| "#{arg} = ''"}.join(",")

    # Create the command function
    command_code = %Q|
      def #{command}(#{args_string})
        dispatch Net::YAIL::OutgoingEvent.new(:type => #{command.inspect}#{event_string})
      end
    |
    self.class.class_eval command_code

    # Create the handler piece by piece - wow how ugly this is!
    command_handler = :"magic_out_#{command}"
    handler_code = %Q|
      def #{command_handler}(event)
        output_string = "#{output_base}"
    |
    for arg in args
      if optional_arg_templates[arg]
        handler_code += %Q|
          output_string += "#{optional_arg_templates[arg]}" unless event.#{arg}.to_s.empty?
        |
      end
    end
    handler_code += %Q|
        raw output_string
      end
    |

    self.class.class_eval handler_code

    # At least setting the callback isn't a giant pile of dumb
    set_callback :"outgoing_#{command}", self.method(command_handler)
  end
end

end
