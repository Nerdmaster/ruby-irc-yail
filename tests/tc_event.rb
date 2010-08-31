#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/net_yail'
require 'test/unit'

# Stolen from tc_message_parser - same tests, different object
class MessageParserEventTest < Test::Unit::TestCase
  # Simplest test case, I think
  def test_ping
    event = Net::YAIL::IncomingEvent.parse("PING :nerdbucket.com")
    assert_equal 'nerdbucket.com', event.text
    assert_equal :incoming_ping, event.type
    assert !event.respond_to?(:servername)
    assert !event.respond_to?(:nick)
    assert !event.respond_to?(:channel)
    assert !event.respond_to?(:fullname)
    assert event.server?
  end

  def test_topic
    event = Net::YAIL::IncomingEvent.parse(":Dude!dude@nerdbucket.com TOPIC #nerdtalk :31 August 2010 \357\277\275 Foo.")
    assert_equal :incoming_topic, event.type
    assert_equal 'Dude', event.nick
    assert_equal "31 August 2010 \357\277\275 Foo.", event.text
    assert_equal '#nerdtalk', event.channel
    assert_equal 'Dude!dude@nerdbucket.com', event.fullname
  end

  # Parsing of PRIVMSG messages
  def test_messages
    # Basic test of privmsg-type command
    event = Net::YAIL::IncomingEvent.parse(':Nerdmaster!jeremy@nerdbucket.com PRIVMSG Nerdminion :Do my bidding!!')
    assert_nil event.parent
    assert_equal 'Nerdmaster', event.nick
    assert_equal 'jeremy', event.msg.user
    assert_equal 'nerdbucket.com', event.msg.host
    assert_equal 'Nerdmaster!jeremy@nerdbucket.com', event.fullname
    assert_equal 'Nerdmaster!jeremy@nerdbucket.com', event.from
    assert !event.server?
    assert_equal 'PRIVMSG', event.msg.command
    assert_equal :incoming_msg, event.type
    assert_equal 'Nerdminion', event.target
    assert_equal true, event.pm?
    assert_equal 'Do my bidding!!', event.text

    # CTCP to user
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com PRIVMSG Nerdminion :\001FOO is to bar as BAZ is to...?\001")
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_ctcp, event.type
    assert_nil event.channel
    assert_equal 'Nerdminion', event.target
    assert_equal true, event.pm?
    assert_equal 'FOO is to bar as BAZ is to...?', event.text
    assert_equal :incoming_msg, event.parent.type
    assert_equal "\001FOO is to bar as BAZ is to...?\001", event.parent.text
    assert_nil event.parent.parent

    # Action to channel
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com PRIVMSG #bottest :\001ACTION gives Towelie a joint\001")
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_act, event.type
    assert_equal '#bottest', event.channel
    assert_equal false, event.pm?
    assert_equal 'gives Towelie a joint', event.text
    assert_equal :incoming_ctcp, event.parent.type
    assert_equal "ACTION gives Towelie a joint", event.parent.text
    assert_equal :incoming_msg, event.parent.parent.type
    assert_equal "\001ACTION gives Towelie a joint\001", event.parent.parent.text
    assert_nil event.parent.parent.parent

    # PM to channel with less common prefix
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com PRIVMSG !bottest :foo")
    assert_equal :incoming_msg, event.type
    assert_equal false, event.pm?
    assert_equal '!bottest', event.channel
  end

  # Quick test of a numeric message I've ACTUALLY SEEN!!
  def test_numeric
    event = Net::YAIL::IncomingEvent.parse(':nerdbucket.com 266 Nerdmaster :Current global users: 22  Max: 33')
    assert_equal 'Current global users: 22  Max: 33', event.text
    assert_equal :incoming_266, event.type
    assert_equal 'nerdbucket.com', event.servername
    assert_equal 'nerdbucket.com', event.from
    assert_equal 'Nerdmaster', event.target

    assert !event.respond_to?(:nick)
    assert !event.respond_to?(:channel)
    assert !event.respond_to?(:fullname)
    assert event.server?

    assert_equal :incoming_numeric, event.parent.type
    assert_equal 266, event.parent.numeric

    # Numeric with multiple args
    event = Net::YAIL::IncomingEvent.parse(':someserver.co.uk.fn.bb 366 Towelie #bottest :End of /NAMES list.')
    assert_equal :incoming_366, event.type
    assert_equal '#bottest End of /NAMES list.', event.text
    assert_equal ['#bottest', 'End of /NAMES list.'], event.parameters

    # First param in the message params list should still be nick
    assert_equal 'Towelie', event.msg.params.first
  end

  # Test an invite
  def test_invite
    event = Net::YAIL::IncomingEvent.parse(':Nerdmaster!jeremy@nerdbucket.com INVITE Nerdminion :#nerd-talk')
    assert_equal '#nerd-talk', event.channel
    assert_equal 'Nerdmaster', event.nick
    assert_equal 'Nerdminion', event.target
  end

  # Test a user joining message
  def test_join
    event = Net::YAIL::IncomingEvent.parse(':Nerdminion!minion@nerdbucket.com JOIN :#nerd-talk')
    assert_equal '#nerd-talk', event.channel
    assert_equal 'Nerdminion', event.nick
    assert_equal :incoming_join, event.type
  end

  def test_part
    event = Net::YAIL::IncomingEvent.parse(':Nerdminion!minion@nerdbucket.com PART #nerd-talk :No, YOU GO TO HELL')
    assert_equal '#nerd-talk', event.channel
    assert_equal 'Nerdminion', event.nick
    assert_equal 'No, YOU GO TO HELL', event.text
    assert_equal :incoming_part, event.type
  end

  def test_kick
    event = Net::YAIL::IncomingEvent.parse(%q|:Nerdmaster!jeremy@nerdbucket.com KICK #nerd-talk Nerdminion :You can't quit!  You're FIRED!|)
    assert_equal '#nerd-talk', event.channel
    assert_equal 'Nerdminion', event.target
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_kick, event.type
    assert_equal %q|You can't quit!  You're FIRED!|, event.text
  end

  def test_quit
    event = Net::YAIL::IncomingEvent.parse(':TheTowel!ce611d7b0@nerdbucket.com QUIT :Bye bye')
    assert_equal 'TheTowel', event.nick
    assert_equal :incoming_quit, event.type
    assert_equal 'Bye bye', event.text
  end

  def test_nick
    # Nick change when nick is "unusual" - this also tests the bug with a single parameter being
    # treated incorrectly
    event = Net::YAIL::IncomingEvent.parse(':[|\|1]!~nerdmaste@nerd.nerdbucket.com NICK :Deadnerd')
    assert_equal '[|\|1]', event.nick
    assert_equal :incoming_nick, event.type
    assert_equal 'Deadnerd', event.text
  end

  # Test some notice stuff
  def test_notice_and_ctcp_reply
    event = Net::YAIL::IncomingEvent.parse(":nerdbucket.com NOTICE Nerdminion :You suck.  A lot.")
    assert_equal 'nerdbucket.com', event.servername
    assert_equal 'nerdbucket.com', event.from
    assert event.server?
    assert_equal :incoming_notice, event.type
    assert_equal 'Nerdminion', event.target
    assert !event.respond_to?(:nick)
    assert !event.respond_to?(:fullname)
    assert_equal 'You suck.  A lot.', event.text

    # This CTCP message...
    #     ":Nerdmaster!jeremy@nerdbucket.com PRIVMSG Nerdminion \001USERINFO\001"
    # ...might yield this response:
    event = Net::YAIL::IncomingEvent.parse(":Nerdminion!minion@nerdbucket.com NOTICE Nerdmaster :\001USERINFO :Minion of the nerd\001")
    assert !event.respond_to?(:servername)
    assert_equal :incoming_ctcp_reply, event.type
    assert_equal 'Nerdmaster', event.target
    assert_equal 'Nerdminion', event.nick
    assert_equal 'Nerdminion!minion@nerdbucket.com', event.fullname
    assert_equal 'Nerdminion!minion@nerdbucket.com', event.from
    assert_equal 'USERINFO :Minion of the nerd', event.text

    # Channel-wide notice
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com NOTICE #channel-ten-news :Tonight's late-breaking story...")
    assert !event.respond_to?(:servername)
    assert_equal :incoming_notice, event.type
    assert_equal 'Nerdmaster', event.nick
    assert_equal '#channel-ten-news', event.channel
    assert_nil event.target
    assert_equal 'Nerdmaster!jeremy@nerdbucket.com', event.fullname
    assert_equal %q|Tonight's late-breaking story...|, event.text
  end

  def test_modes
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com MODE #bots +ob Towelie Doogles!*@*")
    assert !event.respond_to?(:servername)
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_mode, event.type
    assert_equal '#bots', event.channel
    assert_equal ['Towelie', 'Doogles!*@*'], event.targets
    assert_equal '+ob', event.text

    # Newly-created channels do this
    event = Net::YAIL::IncomingEvent.parse(':nerdbucket.com MODE #bots +nt')
    assert event.server?
    assert_equal 'nerdbucket.com', event.servername

    # TODO: Parse modes better!  This case will be interesting, as the "i" is channel-specific.  Useful
    # parsing would give us something like {'#bots' => '-i', 'Doogles!*@*' => '-b', 'Towelie' => '-v', 'Nerdmaster' => '-v'}
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com MODE #bots -bivv Doogles!*@* Towelie Nerdmaster")
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_mode, event.type
    assert_equal '#bots', event.channel
    assert_equal ['Doogles!*@*', 'Towelie', 'Nerdmaster'], event.targets
    assert_equal '-bivv', event.text

    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com MODE #bots +m")
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_mode, event.type
    assert_equal '#bots', event.channel
    assert_equal [], event.targets
    assert_equal '+m', event.text

    # TODO: This is even worse than above - this is a pretty specific message (setting channel key
    # to 'foo'), but has to be parsed in a pretty absurd way to get that info.
    event = Net::YAIL::IncomingEvent.parse(":Nerdmaster!jeremy@nerdbucket.com MODE #bots +k foo")
    assert_equal 'Nerdmaster', event.nick
    assert_equal :incoming_mode, event.type
    assert_equal '#bots', event.channel
    assert_equal ['foo'], event.targets
    assert_equal '+k', event.text
  end
end
