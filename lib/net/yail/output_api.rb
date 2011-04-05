module Net

# This module is responsible for the raw socket output, buffering of all "message" types of
# events, and exposing the magic to create a new output command + handler.  All output methods
# are documented in the main Net::YAIL documentation.
module IRCOutputAPI
  # Spits a raw string out to the server - in case a subclass wants to do
  # something special on *all* output, please make all output go through this
  # method.  Don't use puts manually.  I will kill violaters.  Legally
  # speaking, that is.
  def raw(line)
    @socket.puts "#{line}\r\n"
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
  # using act and ctcp shortcut methods for those types.  Target is a channel or username, message
  # is the message.
  def msg(target, message)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :msg, :target => target, :message => message)
  end

  # Buffers an :outgoing_ctcp event.  Target is user or channel, message is message.
  def ctcp(target, message)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :ctcp, :target => target, :message => message)
  end

  # Buffers an :outgoing_act event.  Target is user or channel, message is message.
  def act(target, message)
    buffer_output Net::YAIL::OutgoingEvent.new(:type => :act, :target => target, :message => message)
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
