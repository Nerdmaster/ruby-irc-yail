module Net
module IRCEvents

# This module contains all the default events handling that hasn't yet been cleaned up for 2.0
module Defaults
  private

  # Nickname change failed: already in use.  This needs a rewrite to at
  # least hit a "failed too many times" handler of some kind - for a bot,
  # quitting may be fine, but for something else, we may want to prompt a
  # user or try again in 20 minutes or something.  Note that we only fail
  # when the adapter hasn't gotten logged in yet - an attempt at changing
  # nick after registration (welcome message) just generates a report.
  #
  # TODO: This should really not even be here.  Client should have full control over whether or not
  # they want this.  Base IRC bot class should have this, but not the core YAIL lib.
  def _nicknameinuse(event)
    event.message =~ /^(\S+)/
    report "Nickname #{$1} is already in use."

    if (!@registered)
      begin
        nextnick = @nicknames[(0...@nicknames.length).find { |i| @nicknames[i] == $1 } + 1]
        if (nextnick != nil)
          nick nextnick
        else
          report '*** All nicknames in use. ***'
          raise ArgumentError.new("All nicknames in use")
        end
      rescue
        report '*** Nickname selection error. ***'
        raise
      end
    end
  end

  # Names line
  #
  # TODO: Either store this data silently or ditch this code - this verbosity doesn't belong in a core lib
  def _namreply(event)
    event.message =~ /^(@|\*|=) (\S+) :?(.+)$/
    channeltype = {'@' => 'Secret', '*' => 'Private', '=' => 'Normal'}[$1]
    report "{#{$2}} #{channeltype} channel nickname list: #{$3}"
    @nicklist = $3.split(' ')
    @nicklist.collect!{|name| name.sub(/^\W*/, '')}
    report "First nick: #{@nicklist[0]}"
  end

end

end
end
