module Net
module IRCEvents

# All code here is going to be removed completely at some point, and only exists here to serve the 1.x branch
# (and remind me how awful the old system really was)
module LegacyEvents

  # DEPRECATED
  #
  # Event handler hook.  Kinda hacky.  Calls your event(s) before the default
  # event.  Default stuff will happen if your handler doesn't return true.
  def prepend_handler(event, *procs, &block)
    raise "Cannot change handlers while threads are listening!" if @ioloop_thread

    @log.warn "[DEPRECATED] - Net::YAIL#prepend_handler is deprecated as of 1.5.0 - please see documentation on the new " +
        "event handling model methods - http://ruby-irc-yail.nerdbucket.com/"

    # Allow blocks as well as procs
    if block_given?
      procs.push(block)
    end

    # See if this is a word for a numeric - only applies to incoming events
    if (event.to_s =~ /^incoming_(.*)$/)
      number = @event_number_lookup[$1].to_i
      event = :"incoming_numeric_#{number}" if number > 0
    end

    @legacy_handlers[event] ||= Array.new
    until procs.empty?
      @legacy_handlers[event].unshift(procs.pop)
    end
  end

  # Handles the given event (if it's in the @legacy_handlers array) with the
  # arguments specified.
  #
  # The @legacy_handlers must be a hash where key = event to handle and value is
  # a Proc object (via Class.method(:name) or just proc {...}).
  # This should be fine if you're setting up handlers with the prepend_handler
  # method, but if you get "clever," you're on your own.
  def handle(event, *arguments)
    # Don't bother with anything if there are no handlers registered.
    return false unless Array === @legacy_handlers[event]

    @log.debug "+++EVENT HANDLER: Handling event #{event} via #{@legacy_handlers[event].inspect}:"

    # Call all hooks in order until one breaks the chain.  For incoming
    # events, we want something to break the chain or else it'll likely
    # hit a reporter.  For outgoing events, we tend to report them anyway,
    # so no need to worry about ending the chain except when the bot wants
    # to take full control over them.
    result = false
    for handler in @legacy_handlers[event]
      result = handler.call(*arguments)
      break if result == true
    end

    # Let the new system deal with legacy handlers that wanted to end the chain
    return result
  end

  # Since numerics are so many and so varied, this method will auto-fallback
  # to a simple report if no handler was defined.
  def handle_numeric(number, fullactor, actor, target, message)
    # All numerics share the same args, and rarely care about anything but
    # message, so let's make it easier by passing a hash instead of a list
    args = {:fullactor => fullactor, :actor => actor, :target => target}
    base_event = :"incoming_numeric_#{number}"
    if Array === @legacy_handlers[base_event]
      return handle(base_event, message, args)
    else
      # No handler = report and don't worry about it
      @log.info "Unknown raw #{number.to_s} from #{fullactor}: #{message}"
      return false
    end
  end

  # Gets some input, sends stuff off to a handler.  Yay.
  def legacy_process_event(event)
    # Allow global handler to break the chain, filter the line, whatever.  When we ditch these legacy
    # events, this code will finally die!
    if (Net::YAIL::IncomingEvent === event && Array === @legacy_handlers[:incoming_any])
      for handler in @legacy_handlers[:incoming_any]
        result = handler.call(event.raw)
        return true if true == result
      end
    end

    # Partial conversion to using events - we still have a horrible case statement, but
    # we're at least using the event object.  Slightly less hacky than before.

    # Except for this - we still have to handle numerics the crappy way until we build the proper
    # dispatching of events
    event = event.parent if event.parent && :incoming_numeric == event.parent.type

    case event.type
      # Ping is important to handle quickly, so it comes first.
      when :incoming_ping
        return handle(event.type, event.message)

      when :incoming_numeric
        # Lovely - I passed in a "nick" - which, according to spec, is NEVER part of a numeric reply
        handle_numeric(event.numeric, event.servername, nil, event.target, event.message)

      when :incoming_invite
        return handle(event.type, event.fullname, event.nick, event.channel)

      # Fortunately, the legacy handler for all five "message" types is the same!
      when :incoming_msg, :incoming_ctcp, :incoming_act, :incoming_notice, :incoming_ctcpreply
        # Legacy handling requires merger of target and channel....
        target = event.target if event.pm?
        target = event.channel if !target

        # Notices come from server sometimes, so... another merger for legacy fun!
        nick = event.server? ? '' : event.nick
        return handle(event.type, event.from, nick, target, event.message)

      # This is a bit painful for right now - just use some hacks to make it work semi-nicely,
      # but let's not put hacks into the core Event object.  Modes need reworking soon anyway.
      #
      # NOTE: message is currently the mode settings ('+b', for instance) - very bad.  TODO: FIX FIX FIX!
      when :incoming_mode
        # Modes can come from the server, so legacy system again regularly sent nil data....
        nick = event.server? ? '' : event.nick
        return handle(event.type, event.from, nick, event.channel, event.message, event.targets.join(' '))

      when :incoming_topic_change
        return handle(event.type, event.fullname, event.nick, event.channel, event.message)

      when :incoming_join
        return handle(event.type, event.fullname, event.nick, event.channel)

      when :incoming_part
        return handle(event.type, event.fullname, event.nick, event.channel, event.message)

      when :incoming_kick
        return handle(event.type, event.fullname, event.nick, event.channel, event.target, event.message)

      when :incoming_quit
        return handle(event.type, event.fullname, event.nick, event.message)

      when :incoming_nick
        return handle(event.type, event.fullname, event.nick, event.message)

      when :incoming_error
        return handle(event.type, event.message)

      when :outgoing_privmsg, :outgoing_msg, :outgoing_ctcp, :outgoing_act, :outgoing_notice, :outgoing_ctcpreply
        return handle(event.type, event.target, event.message)

      when :outgoing_mode
        return handle(event.type, event.target, event.modes, event.objects)

      when :outgoing_join
        return handle(event.type, event.channel, event.password)

      when :outgoing_part
        return handle(event.type, event.channel, event.message)

      when :outgoing_quit
        return handle(event.type, event.message)

      when :outgoing_nick
        return handle(event.type, event.nick)

      when :outgoing_user
        return handle(event.type, event.username, event.hostname, event.servername, event.realname)

      when :outgoing_pass
        return handle(event.type, event.password)

      when :outgoing_oper
        return handle(event.type, event.user, event.password)

      when :outgoing_topic
        return handle(event.type, event.channel, event.topic)

      when :outgoing_names
        return handle(event.type, event.channel)

      when :outgoing_list
        return handle(event.type, event.channel, event.server)

      when :outgoing_invite
        return handle(event.type, event.nick, event.channel)

      when :outgoing_kick
        return handle(event.type, event.nick, event.channel, event.reason)

      when :outgoing_begin_connection
        return handle(event.type, event.username, event.address, event.realname)

      # Unknown line - if an incoming event, we need to log it as that shouldn't be able to happen,
      # but we don't want to kill somebody's app for it.  An outgoing event that's part of the
      # system should NEVER hit this, so we throw an error in that case.  Custom events just get
      # handled with no arguments, to allow for things like :irc_loop.
      else
        case event
          when Net::YAIL::IncomingEvent
            @log.warn 'Unknown line: %s!' % event.raw.inspect
            @log.warn "Please report this to the github repo at https://github.com/Nerdmaster/ruby-irc-yail/issues"
            return handle(:incoming_miscellany, event.raw)
          when Net::YAIL::OutgoingEvent
            raise "Unknown outgoing event: #{event.inspect}"
          else
            handle(event.type)
        end
    end
  end
end

end
end
