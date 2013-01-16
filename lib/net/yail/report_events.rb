module Net
module IRCEvents

# This is the module for reporting a bunch of crap, included basically for legacy compatibility
# and bots that need to be easy to use / debug right off the bat
module Reports
  # Set up reporting filters - allows users who want it to keep reporting in their app relatively
  # easily while getting rid of it for everybody else
  def setup_reporting(yail)
    @yail = yail

    incoming_reporting = [
      :msg, :act, :notice, :ctcp, :ctcpreply, :mode, :join, :part, :kick,
      :quit, :nick, :welcome, :bannedfromchan, :badchannelkey, :channelurl, :topic,
      :topicinfo, :endofnames, :motd, :motdstart, :endofmotd, :invite
    ]
    for event in incoming_reporting
      yail.after_filter(:"incoming_#{event}", self.method(:"r_#{event}") )
    end

    outgoing_reporting = [
      :msg, :act, :ctcp, :ctcpreply, :notice
    ]
    for event in outgoing_reporting
      yail.after_filter(:"outgoing_#{event}", self.method(:"r_out_#{event}") )
    end

    generic_out_report = [
      :join, :mode, :part, :quit, :nick, :user, :pass, :oper, :topic, :names, :list, :invite, :kick
    ]
    for event in generic_out_report
      yail.after_filter(:"outgoing_#{event}", self.method(:r_out_generic))
    end
  end

  private
  def r_msg(event)
    @yail.log.info "{%s} <%s> %s" % [event.target || event.channel, event.nick, event.message]
  end

  def r_act(event)
    @yail.log.info "{%s} * %s %s" % [event.target || event.channel, event.nick, event.message]
  end

  def r_notice(event)
    nick = event.server? ? '' : event.nick
    @yail.log.info "{%s} -%s- %s" % [event.target || event.channel, nick, event.message]
  end

  def r_ctcp(event)
    @yail.log.info "{%s} [%s %s]" % [event.target || event.channel, event.nick, event.message]
  end

  def r_ctcpreply(event)
    @yail.log.info "{%s} [Reply: %s %s]" % [event.target || event.channel, event.nick, event.message]
  end

  def r_mode(event)
    @yail.log.info "{%s} %s sets mode %s %s" % [event.channel, event.from, event.message, event.targets.join(' ')]
  end

  def r_join(event)
    @yail.log.info "{#{event.channel}} #{event.nick} joins"
  end

  def r_part(event)
    @yail.log.info "{#{event.channel}} #{event.nick} parts (#{event.message})"
  end

  def r_kick(event)
    @yail.log.info "{#{event.channel}} #{event.nick} kicked #{event.target} (#{event.message})"
  end

  def r_quit(event)
    @yail.log.info "#{event.nick} quit (#{event.message})"
  end

  # Incoming invitation
  def r_invite(event)
    @yail.log.info "[#{event.nick}] INVITE to #{event.target}"
  end

  # Reports nick change unless nickname is us - we check nickname here since
  # the magic method changes @yail.me to the new nickname.
  def r_nick(event)
    @yail.log.info "#{event.nick} changed nick to #{event.message}" unless event.nick == @yail.me
  end

  def r_bannedfromchan(event)
    event.message =~ /^(\S*) :Cannot join channel/
    @yail.log.info "Banned from channel #{$1}"
  end

  def r_badchannelkey(event)
    event.message =~ /^(\S*) :Cannot join channel/
    @yail.log.info "Bad channel key (password) for #{$1}"
  end

  def r_welcome(event)
    @yail.log.info "*** Logged in as #{@yail.me}. ***"
  end

  # Channel URL
  def r_channelurl(event)
    event.message =~ /^(\S+) :?(.+)$/
    @yail.log.info "{#{$1}} URL is #{$2}"
  end

  # Channel topic
  def r_topic(event)
    event.message =~ /^(\S+) :?(.+)$/
    @yail.log.info "{#{$1}} Topic is: #{$2}"
  end

  # Channel topic setter
  def r_topicinfo(event)
    event.message =~ /^(\S+) (\S+) (\d+)$/
    @yail.log.info "{#{$1}} Topic set by #{$2} on #{Time.at($3.to_i).asctime}"
  end

  # End of names
  def r_endofnames(event)
    event.message =~ /^(\S+)/
    @yail.log.info "{#{$1}} Nickname list complete"
  end

  # MOTD line
  def r_motd(event)
    event.message =~ /^:?(.+)$/
    @yail.log.info "*MOTD* #{$1}"
  end

  # Beginning of MOTD
  def r_motdstart(event)
    event.message =~ /^:?(.+)$/
    @yail.log.info "*MOTD* #{$1}"
  end

  # End of MOTD
  def r_endofmotd(event)
    @yail.log.info "*MOTD* End of MOTD"
  end

  # Sent a privmsg (non-ctcp)
  def r_out_msg(event)
    @yail.log.info "{#{event.target}} <#{@yail.me}> #{event.message}"
  end

  # Sent a ctcp
  def r_out_ctcp(event)
    @yail.log.info "{#{event.target}} [#{@yail.me} #{event.message}]"
  end

  # Sent ctcp action
  def r_out_act(event)
    @yail.log.info "{#{event.target}} <#{@yail.me}> #{event.message}"
  end

  def r_out_notice(event)
    @yail.log.info "{#{event.target}} -#{@yail.me}- #{event.message}"
  end

  def r_out_ctcpreply(event)
    @yail.log.info "{#{event.target}} [Reply: #{@yail.me} #{event.message}]"
  end

  def r_out_generic(event)
    @yail.log.info "bot: #{event.inspect}"
  end
end

end
end
