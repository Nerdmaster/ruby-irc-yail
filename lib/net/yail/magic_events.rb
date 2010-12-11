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
    $stderr.puts "me: #{@me.inspect}"
    $stderr.puts "Event info: #{event.inspect}"
    @me = event.text.dup if event.nick.downcase == @me.downcase
  end
end

end
end
