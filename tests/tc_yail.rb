#!/usr/bin/env ruby
require File.dirname(__FILE__) + "/net_yail"
require File.dirname(__FILE__) + "/mock_irc"
require "test/unit"

# This test suite is built as an attempt to validate basic functionality in YAIL.  Due to the
# threading of the library, things are going to be... weird.  Good luck, me.
class YailSessionTest < Test::Unit::TestCase
  def setup
    @mockirc = MockIRC.new
    @log = Logger.new($stderr)
    @log.level = Logger::WARN
    @yail = Net::YAIL.new(
      :io => @mockirc, :address => "fake-irc.nerdbucket.com", :log => @log,
      :nicknames => ["Bot"], :realname => "Net::YAIL", :username => "Username"
    )
  end

  # Sets up all our handlers the legacy way - allows testing that things work as they used to
  def setup_legacy_handling
    ###
    # Simple counters for basic testing of successful handler registration - note that all handlers
    # must add "; false" to the end to avoid stopping the built-in handlers
    ###

    @msg = Hash.new(0)
    @yail.prepend_handler(:incoming_welcome)        { |message, args|                          @msg[:welcome] += 1; false }
    @yail.prepend_handler(:incoming_endofmotd)      { |message, args|                          @msg[:endofmotd] += 1; false }
    @yail.prepend_handler(:incoming_notice)         { |f, actor, target, message|              @msg[:notice] += 1; false }
    @yail.prepend_handler(:incoming_nick)           { |f, actor, nick|                         @msg[:nick] += 1; false }
    @yail.prepend_handler(:incoming_bannedfromchan) { |message, args|                          @msg[:bannedfromchan] += 1; false }
    @yail.prepend_handler(:incoming_join)           { |f, actor, target|                       @msg[:join] += 1; false }
    @yail.prepend_handler(:incoming_mode)           { |f, actor, target, modes, objects|       @msg[:mode] += 1; false }
    @yail.prepend_handler(:incoming_msg)            { |f, actor, target, message|              @msg[:msg] += 1; false }
    @yail.prepend_handler(:incoming_act)            { |f, actor, target, message|              @msg[:act] += 1; false }
    @yail.prepend_handler(:incoming_ctcp)           { |f, actor, target, message|              @msg[:ctcp] += 1; false }
    @yail.prepend_handler(:incoming_ping)           { |message|                                @msg[:ping] += 1; false }
    @yail.prepend_handler(:incoming_quit)           { |f, actor, message|                      @msg[:quit] += 1; false }
    @yail.prepend_handler(:outgoing_mode)           { |target, modes, objects|                 @msg[:o_mode] += 1; false }
    @yail.prepend_handler(:outgoing_join)           { |channel, pass|                          @msg[:o_join] += 1; false }

    ###
    # More complex handlers to test parsing of messages
    ###

    # Channels list helps us test joins
    @channels = []
    @yail.prepend_handler(:incoming_join) do |fullactor, actor, target|
      @channels.push(target) if @yail.me == actor
    end

    # Gotta store extra info on notices to test event parsing
    @notices = []
    @yail.prepend_handler(:incoming_notice) do |f, actor, target, message|
      @notices.push({:from => f, :nick => actor, :target => target, :message => message})
    end

    @yail.prepend_handler(:incoming_ping) { |message|                        @ping_message = message; false }
    @yail.prepend_handler(:incoming_quit) { |f, actor, message|              @quit = {:full => f, :nick => actor, :message => message}; false }
    @yail.prepend_handler(:outgoing_join) { |channel, pass|               @out_join = {:channel => channel, :password => pass}; false }
    @yail.prepend_handler(:incoming_msg)  { |f, actor, channel, message|     @privmsg = {:channel => channel, :nick => actor, :message => message}; false }
    @yail.prepend_handler(:incoming_ctcp) { |f, actor, channel, message|     @ctcp = {:channel => channel, :nick => actor, :message => message}; false }
    @yail.prepend_handler(:incoming_act)  { |f, actor, channel, message|     @act = {:channel => channel, :nick => actor, :message => message}; false }
  end

  # "New" handlers are set up (the 1.5+ way of doing things) here to perform tests in common with
  # legacy.  Note that because handlers are different, we have to use filtering for things like the
  # welcome message, otherwise we don't let YAIL do its default stuff.
  def setup_new_handlers
    ###
    # Simple counters for basic testing of successful handler registration
    ###

    @msg = Hash.new(0)
    @yail.heard_welcome           { @msg[:welcome] += 1 }
    @yail.heard_endofmotd         { @msg[:endofmotd] += 1 }
    @yail.heard_notice            { @msg[:notice] += 1 }
    @yail.heard_nick              { @msg[:nick] += 1 }
    @yail.heard_bannedfromchan    { @msg[:bannedfromchan] += 1 }
    @yail.heard_join              { @msg[:join] += 1 }
    @yail.heard_mode              { @msg[:mode] += 1 }
    @yail.heard_msg               { @msg[:msg] += 1 }
    @yail.heard_act               { @msg[:act] += 1 }
    @yail.heard_ctcp              { @msg[:ctcp] += 1 }
    @yail.heard_ping              { @msg[:ping] += 1 }
    @yail.heard_quit              { @msg[:quit] += 1 }
    @yail.said_mode               { @msg[:o_mode] += 1 }
    @yail.said_join               { @msg[:o_join] += 1 }

    ###
    # More complex handlers to test parsing of messages
    ###

    # Channels list helps us test joins
    @channels = []
    @yail.on_join do |event|
      @channels.push(event.channel) if @yail.me == event.nick
    end

    # Gotta store extra info on notices to test event parsing
    @notices = []
    @yail.on_notice do |event|
      # Notices are tricky - we have to check server? and pm? to mimic legacy handler info
      notice = {:from => event.from, :message => event.message}
      notice[:nick] = event.server? ? "" : event.nick
      notice[:target] = event.pm? ? event.target : event.channel
      @notices.push notice
    end

    @yail.heard_ping  { |event| @ping_message = event.message }
    @yail.on_quit     { |event| @quit = {:full => event.fullname, :nick => event.nick, :message => event.message} }
    @yail.saying_join { |event| @out_join = {:channel => event.channel, :password => event.password} }
    @yail.on_msg      { |event| @privmsg = {:channel => event.channel, :nick => event.nick, :message => event.message} }
    @yail.on_ctcp     { |event| @ctcp = {:channel => event.channel, :nick => event.nick, :message => event.message} }
    @yail.on_act      { |event| @act = {:channel => event.channel, :nick => event.nick, :message => event.message} }
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
  # this will be the all-encompassing "everything" test for legacy handling
  def test_legacy
    # Set up legacy handlers
    setup_legacy_handling

    common_tests
  end

  # Exact same tests as above - just verifying functionality is the same as it was in legacy
  def test_new
    setup_new_handlers
    wait_for_irc

    common_tests
  end

  # Resets the messages hash, mocks the IRC server to send string to us, waits for the response, yields to the block
  def mock_message(string)
    @msg = Hash.new(0)
    @mockirc.add_output string
    wait_for_irc
    yield
  end

  # Runs basic tests, verifying that we get expected results from a mocked session.  Handlers set
  # via legacy prepend_handler should be just the same as new handler system.
  def common_tests
    @yail.start_listening

    # Wait until all data has been read and check messages
    wait_for_irc
    assert_equal 1, @msg[:welcome]
    assert_equal 1, @msg[:endofmotd]
    assert_equal 3, @msg[:notice]

    # Intense notice test - make sure all events were properly translated
    assert_equal ['fakeirc.org', nil, 'fakeirc.org'], @notices.collect {|n| n[:from]}
    assert_equal ['', '', ''], @notices.collect {|n| n[:nick]}
    assert_equal ['AUTH', 'AUTH', 'Bot'], @notices.collect {|n| n[:target]}
    assert_match %r|looking up your host|i, @notices.first[:message]
    assert_match %r|looking up your host|i, @notices[1][:message]
    assert_match %r|you are exempt|i, @notices.last[:message]

    # Test magic methods that set up the bot
    assert_equal "Bot", @yail.me, "Should have set @yail.me automatically on welcome handler"
    assert_equal 1, @msg[:o_mode], "Should have auto-sent mode +i"

    # Make sure nick change works
    @yail.nick "Foo"
    wait_for_irc
    assert_equal "Foo", @yail.me, "Should have set @yail.me on explicit nick change"

    # Join a channel where we've been banned
    @yail.join("#banned")
    wait_for_irc
    assert_equal 1, @msg[:bannedfromchan]
    assert_equal "#banned", @out_join[:channel]
    assert_equal "", @out_join[:password]
    assert_equal [], @channels

    # Join some other channel
    @yail.join("#foosball", "pass")
    wait_for_irc
    assert_equal "#foosball", @out_join[:channel]
    assert_equal "pass", @out_join[:password]
    assert_equal ['#foosball'], @channels

    # Mock some chatter to verify PRIVMSG info
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :#{@yail.me}: Welcome!" do
      assert_equal 1, @msg[:msg]
      assert_equal 0, @msg[:act]
      assert_equal 0, @msg[:ctcp]

      assert_equal "Nerdmaster", @privmsg[:nick]
      assert_equal "#foosball", @privmsg[:channel]
      assert_equal "#{@yail.me}: Welcome!", @privmsg[:message]
    end

    # CTCP
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :\001CTCP THING\001" do
      assert_equal 0, @msg[:msg]
      assert_equal 0, @msg[:act]
      assert_equal 1, @msg[:ctcp]

      assert_equal "Nerdmaster", @ctcp[:nick]
      assert_equal "#foosball", @ctcp[:channel]
      assert_equal "CTCP THING", @ctcp[:message]
    end

    # ACT
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :\001ACTION vomits on you\001" do
      assert_equal 0, @msg[:msg]
      assert_equal 1, @msg[:act]
      assert_equal 0, @msg[:ctcp]

      assert_equal "Nerdmaster", @act[:nick]
      assert_equal "#foosball", @act[:channel]
      assert_equal "vomits on you", @act[:message]
    end

    # PING
    mock_message "PING boo" do
      assert_equal 1, @msg[:ping]
      assert_equal 'boo', @ping_message
    end

    # User quits
    mock_message ":Nerdmaster!nerd@nerdbucket.com QUIT :Quit: Bye byes" do
      assert_equal 1, @msg[:quit]
      assert_equal 'Nerdmaster!nerd@nerdbucket.com', @quit[:full]
      assert_equal 'Nerdmaster', @quit[:nick]
      assert_equal 'Quit: Bye byes', @quit[:message]
    end
  end

  # Verifies that chains are broken properly for before filters and the callback, but not for after filters
  def test_chain_breaking
    @msg = Hash.new(0)

    # First call means last filter - this one proves that the last one did or didn't run
    @yail.hearing_msg { |e| @msg[:before_last] += 1; e.handled! if e.message == "quit 2" }

    # Second call means first filter - this one actually allows or skips all other filters and callbacks
    @yail.hearing_msg { |e| e.handled! if e.message == "quit 1" }

    # Actual callback - this is hit as long as a before filter didn't stop the chain
    @yail.on_msg      { |e| @msg[:callback] += 1; e.handled! }

    # After filters never stop the chain
    @yail.heard_msg   { |e| @msg[:after_msg] += 1; e.handled! }
    @yail.heard_msg   { |e| @msg[:after_msg] += 1; e.handled! }
    @yail.heard_msg   { |e| @msg[:after_msg] += 1; e.handled! }
    @yail.heard_msg   { |e| @msg[:after_msg] += 1; e.handled! }

    @yail.start_listening

    wait_for_irc

    # quit 1 means no filters are hit after the first
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :quit 1" do
      assert_equal 0, @msg[:before_last]
      assert_equal 0, @msg[:callback]
      assert_equal 0, @msg[:after_msg]
    end

    # quit 2 means we hit the first before filter, but stopped after the second
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :quit 2" do
      assert_equal 1, @msg[:before_last]
      assert_equal 0, @msg[:callback]
      assert_equal 0, @msg[:after_msg]
    end

    # After filters get run when before filters don't stop things, even though callback and after
    # filters keep trying to break the chain
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :Well hello there, test!" do
      assert_equal 1, @msg[:before_last]
      assert_equal 1, @msg[:callback]
      assert_equal 4, @msg[:after_msg]
    end
  end

  # Verify that *_any filters are run appropriately and in order - before filter should be the
  # first filter run, and after filter should be the last
  def test_any_filters_and_filter_order
    step = 1

    # First we should hit the incoming "any" before filter
    @yail.hearing_any do |e|
      if e.type == :incoming_msg
        assert_equal 1, step
        step += 1
      end
    end

    # Second, incoming message before filter
    @yail.hearing_msg { |e| assert_equal 2, step; step += 1 }

    # Third, the callback
    @yail.on_msg      { |e| assert_equal 3, step; step += 1 }

    # Fourth, incoming message after callback
    @yail.heard_msg   { |e| assert_equal 4, step; step += 1 }

    # Last, incoming "any" after filter
    @yail.heard_any do |e|
      if e.type == :incoming_msg
        assert_equal 5, step
      end
    end

    @yail.start_listening

    wait_for_irc

    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :Well hello there, test!" do
      # We should have no handlers hit more than once - step should be 5 still
      assert_equal 5, step
    end
  end

  def test_conditional_filters
    @msg = Hash.new(0)

    # Conditional filters are really ugly when passing a block instead of a method, so let's
    # at least try to make this look decent
    hearing_food    = lambda { @msg[:food] += 1 }
    not_hearing_bad = lambda { @msg[:not_bad] += 1 }
    heard_nothing   = lambda { @msg[:nothing] += 1 }
    heard_2         = lambda { @msg[:heard_2] += 1 }

    # If the message looks like "food", the handler will be hit
    @yail.hearing_msg(hearing_food, :if => lambda {|e| e.message =~ /food/})

    # Unless the message looks like "bad", the handler will be hit
    @yail.hearing_msg(not_hearing_bad, :unless => lambda {|e| e.message =~ /bad/})

    # Verify after-filter is called, and hash conditions are respected
    @yail.heard_msg(heard_nothing, :if => {:message => ""})

    # Verify multiple hash conditions are anded
    @yail.heard_msg(heard_2, :if => {:message => "bah", :pm? => true})

    # GO GO GO
    @yail.start_listening

    wait_for_irc

    # Food
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :this food is bad" do
      assert_equal({:food => 1}, @msg)
    end

    # Good food!
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :this food is good!" do
      assert_equal({:food => 1, :not_bad => 1}, @msg)
    end

    # Good drink
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :this drink is good!" do
      assert_equal({:not_bad => 1}, @msg)
    end

    # Nothing, but not bad
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :" do
      assert_equal({:not_bad => 1, :nothing => 1}, @msg)
    end

    # Private message for multiple hash test
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #{@yail.me} :bah" do
      assert_equal({:not_bad => 1, :heard_2 => 1}, @msg)
    end

    # Private message without bah does *not* fire off multiple hash handler
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #{@yail.me} :hey there buddy" do
      assert_equal({:not_bad => 1}, @msg)
    end

    # "bah" without being pm doesn't fire off handler, either
    mock_message ":Nerdmaster!nerd@nerdbucket.com PRIVMSG #foosball :bah" do
      assert_equal({:not_bad => 1}, @msg)
    end
  end
end
