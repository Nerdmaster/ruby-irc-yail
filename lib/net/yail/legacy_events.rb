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

    @legacy_handlers ||= Hash.new

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
    @legacy_handlers ||= Hash.new
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
  def handle_numeric(number, fullactor, actor, target, text)
    # All numerics share the same args, and rarely care about anything but
    # text, so let's make it easier by passing a hash instead of a list
    args = {:fullactor => fullactor, :actor => actor, :target => target}
    base_event = :"incoming_numeric_#{number}"
    if Array === @legacy_handlers[base_event]
      return handle(base_event, text, args)
    else
      # No handler = report and don't worry about it
      @log.info "Unknown raw #{number.to_s} from #{fullactor}: #{text}"
      return false
    end
  end

  # Gets some input, sends stuff off to a handler.  Yay.
  def legacy_process_event(event)
    # HACK TODO TODO: need to deal with other event handling here - particularly outgoing events
    return false unless Net::YAIL::IncomingEvent === event

    # Allow global handler to break the chain, filter the line, whatever.  For
    # this release, it's a hack.  2.0 will be better.
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
        return handle(event.type, event.text)

      when :incoming_numeric
        # Lovely - I passed in a "nick" - which, according to spec, is NEVER part of a numeric reply
        handle_numeric(event.numeric, event.servername, nil, event.target, event.text)

      when :incoming_invite
        return handle(event.type, event.fullname, event.nick, event.channel)

      # Fortunately, the legacy handler for all five "message" types is the same!
      when :incoming_msg, :incoming_ctcp, :incoming_act, :incoming_notice, :incoming_ctcpreply
        # Legacy handling requires merger of target and channel....
        target = event.target if event.pm?
        target = event.channel if !target

        # Notices come from server sometimes, so... another merger for legacy fun!
        nick = event.server? ? '' : event.nick
        return handle(event.type, event.from, nick, target, event.text)

      # This is a bit painful for right now - just use some hacks to make it work semi-nicely,
      # but let's not put hacks into the core Event object.  Modes need reworking soon anyway.
      #
      # NOTE: text is currently the mode settings ('+b', for instance) - very bad.  TODO: FIX FIX FIX!
      when :incoming_mode
        # Modes can come from the server, so legacy system again regularly sent nil data....
        nick = event.server? ? '' : event.nick
        return handle(event.type, event.from, nick, event.channel, event.text, event.targets.join(' '))

      when :incoming_topic_change
        return handle(event.type, event.fullname, event.nick, event.channel, event.text)

      when :incoming_join
        return handle(event.type, event.fullname, event.nick, event.channel)

      when :incoming_part
        return handle(event.type, event.fullname, event.nick, event.channel, event.text)

      when :incoming_kick
        return handle(event.type, event.fullname, event.nick, event.channel, event.target, event.text)

      when :incoming_quit
        return handle(event.type, event.fullname, event.nick, event.text)

      when :incoming_nick
        return handle(event.type, event.fullname, event.nick, event.text)

      when :incoming_error
        return handle(event.type, event.text)

      # Unknown line!
      else
        # This should really never happen, but isn't technically an error per se
        @log.warn 'Unknown line: %s!' % event.raw.inspect
        return handle(:incoming_miscellany, event.raw)
    end
  end
end

end
end
