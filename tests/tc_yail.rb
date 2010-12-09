#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/net_yail"
require File.dirname(__FILE__) + "/mock_irc"
require "test/unit"

# This test suite is built as an attempt to validate basic functionality in YAIL.  Due to the
# threading of the library, things are going to be... weird.  Good luck, me.
class YailSessionTest < Test::Unit::TestCase
  def setup
    @msg = Hash.new(0)
    @mockirc = MockIRC.new
    @yail = Net::YAIL.new(
      :io => @mockirc, :silent => true, :address => "fake-irc.nerdbucket.com",
      :nicknames => ["Bot"], :realname => "Net::YAIL", :username => "Username"
    )
    @yail.prepend_handler(:incoming_welcome)        { |text, args|                          @msg[:welcome] += 1 }
    @yail.prepend_handler(:incoming_endofmotd)      { |text, args|                          @msg[:endofmotd] += 1 }
    @yail.prepend_handler(:incoming_notice)         { |f, actor, target, text|              @msg[:notice] += 1 }
    @yail.prepend_handler(:incoming_nick)           { |f, actor, nick|                      @msg[:nick] += 1 }
    @yail.prepend_handler(:incoming_bannedfromchan) { |text, args|                          @msg[:bannedfromchan] += 1 }
    @yail.prepend_handler(:incoming_join)           { |f, actor, target|                    @msg[:join] += 1 }
    @yail.prepend_handler(:incoming_mode)           { |f, actor, target, modes, objects|    @msg[:mode] += 1 }
    @yail.prepend_handler(:outgoing_mode)           { |target, modes, objects|              @msg[:o_mode] += 1 }
    @yail.prepend_handler(:incoming_msg)            { |f, actor, target, text|              @msg[:msg] += 1 }
    @yail.prepend_handler(:incoming_act)            { |f, actor, target, text|              @msg[:act] += 1 }
    @yail.prepend_handler(:incoming_ctcp)           { |f, actor, target, text|              @msg[:ctcp] += 1 }
  end

  # Waits until the mock IRC reports it has no more output - i.e., we've read everything available
  def wait_for_irc
    while @mockirc.ready?
      sleep 0.05
    end

    # For safety, we need to wait yet again to be sure YAIL has processed the data it read.
    # This is hacky, but it decreases random failures quite a bit
    sleep 0.1
  end

  # Log in to fake server, do stuff, see that basic handling and such are working.  For simplicity,
  # this will be the all-encompassing "everything" test for now
  def test_session
    # Channels list helps us test joins
    channels = []
    @yail.prepend_handler(:incoming_join) do |fullactor, actor, target|
      channels.push(target) if @yail.me == actor
    end

    @yail.start_listening

    # Wait until all data has been read and check messages
    wait_for_irc
    assert_equal 1, @msg[:welcome]
    assert_equal 1, @msg[:endofmotd]
    assert_operator @msg[:notice], :>, 0
    assert_equal 1, @msg[:o_mode], "Auto-sent mode +i"
    assert_equal "Bot", @yail.me, "Auto-nick setting worked"

    # Make sure nick change works
    @yail.nick "Foo"
    wait_for_irc
    assert_equal "Foo", @yail.me, "Auto-nick setting worked again!"

    # Join a channel where we've been banned
    @yail.join("#banned")
    wait_for_irc
    assert_equal 1, @msg[:bannedfromchan]
    assert_equal [], channels

    # Join some other channel
    @yail.join("#foosball")
    wait_for_irc
    assert_equal ['#foosball'], channels

    # Mock some chatter to verify PRIVMSG info
    @msg = Hash.new(0)
    @mockirc.add_output ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :#{@yail.me}: Welcome!"
    wait_for_irc
    assert_equal 1, @msg[:msg]
    assert_equal 0, @msg[:act]
    assert_equal 0, @msg[:ctcp]

    # CTCP
    @msg = Hash.new(0)
    @mockirc.add_output ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :\001CTCP THING\001"
    wait_for_irc
    assert_equal 0, @msg[:msg]
    assert_equal 0, @msg[:act]
    assert_equal 1, @msg[:ctcp]

    # ACT
    @msg = Hash.new(0)
    @mockirc.add_output ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :\001ACTION vomits on you\001"
    wait_for_irc
    assert_equal 0, @msg[:msg]
    assert_equal 1, @msg[:act]
    assert_equal 0, @msg[:ctcp]
  end
end
