module Net
module IRCEvents

# This is the module for reporting a bunch of crap, included basically for legacy compatibility
module Reports
  # Set up reporting filters - allows users who want it to keep reporting in their app relatively
  # easily while getting rid of it for everybody else
  def setup_reporting
    incoming_reporting = [
      :msg, :act, :notice, :ctcp, :ctcpreply, :mode, :join, :part, :kick,
      :quit, :nick, :welcome, :bannedfromchan, :badchannelkey, :channelurl, :topic,
      :topicinfo, :endofnames, :motd, :motdstart, :endofmotd, :invite
    ]
    for event in incoming_reporting
      after_filter(:"incoming_#{event}", self.method(:"r_#{event}") )
    end

    outgoing_reporting = [
      :msg, :act, :ctcp
    ]
    for event in outgoing_reporting
      after_filter(:"outgoing_#{event}", self.method(:"r_out_#{event}") )
    end
  end

  private
  def r_msg(event)
    report "{%s} <%s> %s" % [event.target || event.channel, event.nick, event.text]
  end

  def r_act(event)
    report "{%s} * %s %s" % [event.target || event.channel, event.nick, event.text]
  end

  def r_notice(event)
    nick = event.server? ? '' : event.nick
    report "{%s} -%s- %s" % [event.target || event.channel, nick, event.text]
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

  # Sent a privmsg (non-ctcp)
  def r_out_msg(event)
    report "{#{target}} <#{@me}> #{text}"
  end

  # Sent a ctcp
  def r_out_ctcp(event)
    report "{#{target}} [#{@me} #{text}]"
  end

  # Sent ctcp action
  def r_out_act(event)
    report "{#{target}} <#{@me}> #{text}"
  end
end

end
end
