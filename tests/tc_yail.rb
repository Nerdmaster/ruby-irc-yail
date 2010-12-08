#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/net_yail'
require File.dirname(__FILE__) + '/mock_irc'
require 'test/unit'

# This test suite is built as an attempt to validate basic functionality in YAIL.  Due to the
# threading of the library, things are going to be... weird.  Good luck, me.
class MessageParserEventTest < Test::Unit::TestCase
  def setup
    @msg = Hash.new(0)
    @yail = Net::YAIL.new(
      :io => MockIRC.new, :silent => true, :address => 'fake-irc.nerdbucket.com',
      :nicknames => ['Bot'], :realname => 'Net::YAIL', :username => 'Username'
    )
  end

  # Log in to fake server, give name, choose nick, join a channel, get kicked, quit
  def test_simple
    @yail.prepend_handler(:incoming_welcome)    { |text, args|                          @msg[:welcome] += 1 }
    @yail.prepend_handler(:incoming_endofmotd)  { |text, args|                          @msg[:endofmotd] += 1 }
    @yail.prepend_handler(:incoming_notice)     { |fullactor, actor, target, text|      @msg[:notice] += 1 }
    @yail.start_listening

    # Give us a chance to catch all events
    until ( 1 == @msg[:endofmotd] )
      sleep 0.1
    end

    assert_equal "Bot", yail.me, "Auto-nick setting worked"
    assert_equal 1, @msg[:welcome]

    yail.quit("Bye bye")
    sleep 0.1
  end
end
