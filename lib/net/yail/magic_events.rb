module Net
module IRCEvents

# This module contains all the "magic" methods that need to happen by default.  User could overwrite
# some of these, but really really shouldn't.
module Magic
  private

  # We were welcomed, so we need to set up initial nickname and set that we
  # registered so nick change failure doesn't cause DEATH!
  def magic_welcome(text, args)
    # TODO: Ditch this call to report - move to report lib if necessary
    report "#{args[:fullactor]} welcome message: #{text}"
    if (text =~ /(\S+)!\S+$/)
      @me = $1
    elsif (text =~ /(\S+)$/)
      @me = $1
    end

    @registered = true
    mode @me, 'i'
  end

  # Ping must have a PONG, though crazy user can handle this her own way if she likes
  def magic_ping(text); @socket.puts "PONG :#{text}"; end

  # If bot changes his name, @me must change - this must be a filter, not the callback!
  def magic_nick(fullactor, actor, nickname); @me = nickname.dup if actor.downcase == @me.downcase; end
end

end
end
