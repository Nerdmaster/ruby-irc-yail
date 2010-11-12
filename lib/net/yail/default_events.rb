module Net
module IRCEvents

# This module contains all the default events handling - mainly for
# reporting things or simple logic.  In 2.0, most of these will be removed.
module Defaults
  private

  def r_msg(fullactor, actor, target, text)
    report "{#{target}} <#{actor}> #{text}"
  end

  def r_act(fullactor, actor, target, text)
    report "{#{target}} * #{actor} #{text}"
  end

  def r_notice(fullactor, actor, target, text)
    report "{#{target}} -#{actor}- #{text}"
  end

  def r_ctcp(fullactor, actor, target, text)
    report "{#{target}} [#{actor} #{text}]"
  end

  def r_ctcpreply(fullactor, actor, target, text)
    report "{#{target}} [Reply: #{actor} #{text}]"
  end

  def r_mode(fullactor, actor, target, modes, objects)
    report "{#{target}} #{actor} sets mode #{modes} #{objects}"
  end

  def r_join(fullactor, actor, target)
    report "{#{target}} #{actor} joins"
  end

  def r_part(fullactor, actor, target, text)
    report "{#{target}} #{actor} parts (#{text})"
  end

  def r_kick(fullactor, actor, target, object, text)
    report "{#{target}} #{actor} kicked #{object} (#{text})"
  end

  def r_quit(fullactor, actor, text)
    report "#{actor} quit (#{text})"
  end

  # Reports nick change unless nickname is us - we check nickname here since
  # the magic method changes @me to the new nickname.
  def r_nick(fullactor, actor, nickname)
    report "#{actor} changed nick to #{nickname}" unless nickname == @me
  end

  def r_bannedfromchan(text, args)
    text =~ /^(\S*) :Cannot join channel/
    report "Banned from channel #{$1}"
  end

  def r_badchannelkey(text, args)
    text =~ /^(\S*) :Cannot join channel/
    report "Bad channel key (password) for #{$1}"
  end

  def r_welcome(*args)
    report "*** Logged in as #{@me}. ***"
  end

  def r_miscellany(line)
    report "serv: #{line}"
  end

  # Nickname change failed: already in use.  This needs a rewrite to at
  # least hit a "failed too many times" handler of some kind - for a bot,
  # quitting may be fine, but for something else, we may want to prompt a
  # user or try again in 20 minutes or something.  Note that we only fail
  # when the adapter hasn't gotten logged in yet - an attempt at changing
  # nick after registration (welcome message) just generates a report.
  #
  # TODO: This should really not even be here.  Client should have full control over whether or not
  # they want this.  Base IRC bot class should have this, but not the core YAIL lib.
  def _nicknameinuse(text, args)
    text =~ /^(\S+)/
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

  # Channel URL
  def r_channelurl(text, args)
    text =~ /^(\S+) :?(.+)$/
    report "{#{$1}} URL is #{$2}"
  end

  # Channel topic
  def r_topic(text, args)
    text =~ /^(\S+) :?(.+)$/
    report "{#{$1}} Topic is: #{$2}"
  end

  # Channel topic setter
  def r_topicinfo(text, args)
    text =~ /^(\S+) (\S+) (\d+)$/
    report "{#{$1}} Topic set by #{$2} on #{Time.at($3.to_i).asctime}"
  end

  # Names line
  #
  # TODO: Either store this data silently or ditch this code - this verbosity doesn't belong in a core lib
  def _namreply(text, args)
    text =~ /^(@|\*|=) (\S+) :?(.+)$/
    channeltype = {'@' => 'Secret', '*' => 'Private', '=' => 'Normal'}[$1]
    report "{#{$2}} #{channeltype} channel nickname list: #{$3}"
    @nicklist = $3.split(' ')
    @nicklist.collect!{|name| name.sub(/^\W*/, '')}
    report "First nick: #{@nicklist[0]}"
  end

  # End of names
  def r_endofnames(text, args)
    text =~ /^(\S+)/
    report "{#{$1}} Nickname list complete"
  end

  # MOTD line
  def r_motd(text, args)
    text =~ /^:?(.+)$/
    report "*MOTD* #{$1}"
  end

  # Beginning of MOTD
  def r_motdstart(text, args)
    text =~ /^:?(.+)$/
    report "*MOTD* #{$1}"
  end

  # End of MOTD
  def r_endofmotd(text, args)
    report "*MOTD* End of MOTD"
  end

  # We dun connected to a server!  Just sends password (if one is set) and
  # user/nick.  This isn't quite "essential" to a working IRC app, but this data
  # *must* be sent at some point, so be careful before skipping this handler.
  def out_begin_connection(username, address, realname)
    pass(@password) if @password
    user(username, '0.0.0.0', address, realname)
    nick(@nicknames[0])
  end

  # Incoming invitation
  def r_invite(fullactor, actor, target)
    report "[#{actor}] INVITE to #{target}"
  end

end

end
end
