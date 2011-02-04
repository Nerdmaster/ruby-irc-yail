module Net
module IRCEvents

# This module contains all the "magic" methods that need to happen by default.  User could overwrite
# some of these, but really really shouldn't.
module Magic
  private

  # We dun connected to a server!  Just sends password (if one is set) and
  # user/nick.  This isn't quite "essential" to a working IRC app, but this data
  # *must* be sent at some point, so be careful before clobbering this handler.
  def out_begin_connection(event)
    pass(@password) if @password
    user(event.username, '0.0.0.0', event.address, event.realname)
    nick(@nicknames[0])
  end

  # We were welcomed, so we need to set up initial nickname and set that we
  # registered so nick change failure doesn't cause DEATH!
  def magic_welcome(event)
    # TODO: Ditch this call to report - move to report lib if necessary
    report "#{event.from} welcome message: #{event.message}"
    if (event.message =~ /(\S+)!\S+$/)
      @me = $1
    elsif (event.message =~ /(\S+)$/)
      @me = $1
    end

    @registered = true
    mode @me, 'i'
  end

  # Ping must have a PONG, though crazy user can handle this her own way if she likes
  def magic_ping(event); @socket.puts "PONG :#{event.message}"; end

  # If bot changes his name, @me must change - this must be a filter, not the callback!
  def magic_nick(event)
    @me = event.message.dup if event.nick.downcase == @me.downcase
  end

  # User calls msg, sends a simple message out to the event's target (user or channel)
  def magic_out_msg(event)
    privmsg(event.target, event.message)
  end

  # CTCP
  def magic_out_ctcp(event)
    privmsg(event.target, "\001#{event.message}\001")
  end

  # CTCP ACTION
  def magic_out_act(event)
    privmsg(event.target, "\001ACTION #{event.message}\001")
  end

end

end
end
