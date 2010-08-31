#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/net_yail'
require 'test/unit'

class MessageParserTest < Test::Unit::TestCase
  # Very simple parsing of easy strings
  def test_parse_basic
    # Basic test of privmsg-type command
    msg = Net::YAIL::MessageParser.new(':Nerdmaster!jeremy@nerdbucket.com PRIVMSG Nerdminion :Do my bidding!!')
    assert_equal 'Nerdmaster', msg.nick
    assert_equal 'jeremy', msg.user
    assert_equal 'nerdbucket.com', msg.host
    assert_equal 'Nerdmaster!jeremy@nerdbucket.com', msg.prefix
    assert_equal 'PRIVMSG', msg.command
    assert_equal 'Nerdminion', msg.params[0]
    assert_equal 'Do my bidding!!', msg.params[1]

    # Server command of some type
    msg = Net::YAIL::MessageParser.new(':nerdbucket.com SERVERCOMMAND arg1 arg2 :final :trailing :arg, --fd9823')
    assert_equal 'nerdbucket.com', msg.servername
    assert_nil msg.user
    assert_nil msg.nick
    assert_nil msg.host
    assert_equal 'nerdbucket.com', msg.prefix
    assert_equal 'arg1', msg.params[0]
    assert_equal 'arg2', msg.params[1]
    assert_equal 'final :trailing :arg, --fd9823', msg.params[2]

    # Server command of some type - no actual final arg
    msg = Net::YAIL::MessageParser.new(':nerdbucket.com SERVERCOMMAND arg1:finaltrailingarg')
    assert_equal 'nerdbucket.com', msg.servername
    assert_nil msg.user
    assert_nil msg.nick
    assert_nil msg.host
    assert_equal 'nerdbucket.com', msg.prefix
    assert_equal 'arg1:finaltrailingarg', msg.params[0]

    # WTF?  Well, IRC spec says it's valid
    msg = Net::YAIL::MessageParser.new('MAGICFUNKYFRESHCMD arg1 arg2')
    assert_nil msg.servername
    assert_equal 'MAGICFUNKYFRESHCMD', msg.command
    assert_equal 'arg1', msg.params[0]
    assert_equal 'arg2', msg.params[1]

    # Action
    msg = Net::YAIL::MessageParser.new(":Nerdmaster!jeremy@nerdbucket.com PRIVMSG #bottest :\001ACTION gives Towelie a joint\001")
    assert_equal 'Nerdmaster', msg.nick
    assert_equal 'PRIVMSG', msg.command
    assert_equal '#bottest', msg.params.first
    assert_equal "\001ACTION gives Towelie a joint\001", msg.params.last

    # Bot sets mode
    msg = Net::YAIL::MessageParser.new(':Towelie!~x2e521146@towelie.foo.bar MODE Towelie :+i')
    assert_equal 'Towelie', msg.nick
    assert_equal 'towelie.foo.bar', msg.host
    assert_equal 'MODE', msg.command
    assert_equal 'Towelie', msg.params.first
    assert_equal '+i', msg.params.last

    # Numeric message with a : before final param
    msg = Net::YAIL::MessageParser.new(':someserver.co.uk.fn.bb 366 Towelie #bottest :End of /NAMES list.')
    assert_nil msg.nick
    assert_nil msg.host
    assert_equal '366', msg.command
    assert_equal 'Towelie', msg.params.shift
    assert_equal '#bottest', msg.params.shift
    assert_equal 'End of /NAMES list.', msg.params.shift

    # Nick change when nick is "unusual" - this also tests the bug with a single parameter being
    # treated incorrectly
    msg = Net::YAIL::MessageParser.new(':[|\|1]!~nerdmaste@nerd.nerdbucket.com NICK :Deadnerd')
    assert_equal '[|\|1]', msg.nick
    assert_equal 'NICK', msg.command
    assert_equal '~nerdmaste', msg.user
    assert_equal 'nerd.nerdbucket.com', msg.host
    assert_equal '[|\|1]!~nerdmaste@nerd.nerdbucket.com', msg.prefix
    assert_equal 'Deadnerd', msg.params.shift
    assert_equal 0, msg.params.length

    # Annoying topic change
    msg = Net::YAIL::MessageParser.new(":Dude!dude@nerdbucket.com TOPIC #nerdtalk :31 August 2010 \357\277\275 Foo.")
    assert_equal 'TOPIC', msg.command
    assert_equal 'Dude', msg.nick
    assert_equal "31 August 2010 \357\277\275 Foo.", msg.params.last
    assert_equal '#nerdtalk', msg.params.first
    assert_equal 'Dude!dude@nerdbucket.com', msg.prefix
  end
end
