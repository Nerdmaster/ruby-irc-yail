module Net
module IRCEvents

# This module contains all the "magic" methods that need to happen by default.  User could overwrite
# some of these, but really really shouldn't.
module Magic
  private

  # We were welcomed, so we need to set up initial nickname and set that we
  # registered so nick change failure doesn't cause DEATH!
  def magic_welcome(event)
    # TODO: Ditch this call to report - move to report lib if necessary
    report "#{event.from} welcome message: #{event.text}"
    if (event.text =~ /(\S+)!\S+$/)
      @me = $1
    elsif (event.text =~ /(\S+)$/)
      @me = $1
    end

    @registered = true
    mode @me, 'i'
  end

  # Ping must have a PONG, though crazy user can handle this her own way if she likes
  def magic_ping(event); @socket.puts "PONG :#{event.text}"; end

  # If bot changes his name, @me must change - this must be a filter, not the callback!
  def magic_nick(event)
    @me = event.text.dup if event.nick.downcase == @me.downcase
  end

  # User calls msg, sends a simple message out to the event's target (user or channel)
  def magic_out_msg(event)
    raw_privmsg(event.target, event.text)
  end

  def magic_out_ctcp(event)
    raw_privmsg(event.target, "\001#{event.text}\001")
  end

  def magic_out_act(event)
    raw_privmsg(event.target, "\001ACTION #{event.text}\001")
  end

  # All PRIVMSG events eventually hit this - it's a legacy thing, and kinda dumb, but there you
  # have it.  Just sends a raw PRIVMSG out to the socket.
  def magic_out_privmsg(event)
    raw("PRIVMSG #{event.target} :#{event.text}", false)
  end
end

end
end
