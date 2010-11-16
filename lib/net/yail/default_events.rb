module Net
module IRCEvents

# This module contains all the default events handling - mainly for
# reporting things or simple logic.  In 2.0, most of these will be removed.
module Defaults
  private

  def r_msg(event)
    report "{%s} <%s> %s" % [event.target || event.channel, event.nick, event.text]
  end

  def r_act(event)
    report "{%s} * %s %s" % [event.target || event.channel, event.nick, event.text]
  end

  def r_notice(event)
    report "{%s} -%s- %s" % [event.target || event.channel, event.nick, event.text]
  end

  def r_ctcp(event)
    report "{%s} [%s %s]" % [event.target || event.channel, event.nick, event.text]
  end

  def r_ctcpreply(event)
    report "{%s} [Reply: %s %s]" % [event.target || event.channel, event.nick, event.text]
  end

  def r_mode(event)
    report "{%s} %s sets mode %s %s" % [event.channel, event.nick, event.text, event.targets.join(' ')]
  end

  def r_join(event)
    report "{#{event.channel}} #{event.nick} joins"
  end

  def r_part(event)
    report "{#{event.channel}} #{event.nick} parts (#{event.text})"
  end

  def r_kick(event)
    report "{#{event.channel}} #{event.nick} kicked #{event.target} (#{event.text})"
  end

  def r_quit(event)
    report "#{event.nick} quit (#{event.text})"
  end

  # Incoming invitation
  def r_invite(event)
    report "[#{event.nick}] INVITE to #{event.target}"
  end

  # Reports nick change unless nickname is us - we check nickname here since
  # the magic method changes @me to the new nickname.
  def r_nick(event)
    report "#{event.nick} changed nick to #{event.text}" unless nickname == @me
  end

  def r_bannedfromchan(event)
    event.text =~ /^(\S*) :Cannot join channel/
    report "Banned from channel #{$1}"
  end

  def r_badchannelkey(event)
    event.text =~ /^(\S*) :Cannot join channel/
    report "Bad channel key (password) for #{$1}"
  end

  def r_welcome(*args)
    report "*** Logged in as #{@me}. ***"
  end

  # Channel URL
  def r_channelurl(event)
    event.text =~ /^(\S+) :?(.+)$/
    report "{#{$1}} URL is #{$2}"
  end

  # Channel topic
  def r_topic(event)
    event.text =~ /^(\S+) :?(.+)$/
    report "{#{$1}} Topic is: #{$2}"
  end

  # Channel topic setter
  def r_topicinfo(event)
    event.text =~ /^(\S+) (\S+) (\d+)$/
    report "{#{$1}} Topic set by #{$2} on #{Time.at($3.to_i).asctime}"
  end

  # End of names
  def r_endofnames(event)
    event.text =~ /^(\S+)/
    report "{#{$1}} Nickname list complete"
  end

  # MOTD line
  def r_motd(event)
    event.text =~ /^:?(.+)$/
    report "*MOTD* #{$1}"
  end

  # Beginning of MOTD
  def r_motdstart(event)
    event.text =~ /^:?(.+)$/
    report "*MOTD* #{$1}"
  end

  # End of MOTD
  def r_endofmotd(event)
    report "*MOTD* End of MOTD"
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
  def _nicknameinuse(event)
    event.text =~ /^(\S+)/
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
    event.text =~ /^(@|\*|=) (\S+) :?(.+)$/
    channeltype = {'@' => 'Secret', '*' => 'Private', '=' => 'Normal'}[$1]
    report "{#{$2}} #{channeltype} channel nickname list: #{$3}"
    @nicklist = $3.split(' ')
    @nicklist.collect!{|name| name.sub(/^\W*/, '')}
    report "First nick: #{@nicklist[0]}"
  end

  # We dun connected to a server!  Just sends password (if one is set) and
  # user/nick.  This isn't quite "essential" to a working IRC app, but this data
  # *must* be sent at some point, so be careful before skipping this handler.
  def out_begin_connection(event)
    pass(@password) if @password
    user(event.username, '0.0.0.0', event.address, event.realname)
    nick(@nicknames[0])
  end

end

end
end
