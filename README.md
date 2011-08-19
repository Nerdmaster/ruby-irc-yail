**This document is not necessarily going to reflect the latest *stable* YAIL!** The latest stable release's
documentation is always at [Nerdbucket.com](http://ruby-irc-yail.nerdbucket.com/).

Net::YAIL is a library built for dealing with IRC communications in Ruby.
This is a project I've been building on and off since 2005 or so, based
originally on the very messy initial release of IRCSocket (back when I first
started, that was the only halfway-decent IRC lib I found).  I've put a lot
of time and effort into cleaning it up to make it better for my own uses,
and now it's almost entirely my code.

Some credit should also be given to Ruby-IRC, as I stole its eventmap.yml
file with very minor modifications.

This library may not be useful to everybody (or anybody other than myself,
for that matter), and Ruby-IRC or another lib may work for your situation
far better than this thing will, but the general design I built here has
just felt more natural to me than the other libraries I've looked at since
I started my project.

Example Usage
======

Need an example?  For a separate project you can play with that relies on Net::YAIL, check out
https://github.com/Nerdmaster/superloud.  This is based on the code in the examples directory,
but is easier to clone, run, and tinker with because it's a separate github project.

For the nitty-gritty, you can see all this stuff in the [Net::YAIL docs](http://ruby-irc-yail.nerdbucket.com/)
page, as well as more complete documentation about the system.  For a complete bot,
check out the IRCBot source code as well as the various examples found in the github
project or in the gem's examples directory.  Below is just a very simple example:

    require 'rubygems'
    require 'net/yail'

    irc = Net::YAIL.new(
      :address    => 'irc.someplace.co.uk',
      :username   => 'Frakking Bot',
      :realname   => 'John Botfrakker',
      :nicknames  => ['bot1', 'bot2', 'bot3']
    )

    # Register a proc callback
    irc.on_welcome proc { |event| irc.join('#foo') }

    # Register a block
    irc.on_invite { |event| irc.join(event.channel) }

    # Another way to register a block - note that this clobbers the prior callback
    irc.set_callback(:incoming_invite) { |event| irc.join(event.channel) }

    # Filter for all incoming pings so we can log them
    irc.hearing_ping {|event| $stderr.puts event.inspect}

    # Loops forever here until CTRL+C is hit.
    irc.start_listening!

Now we've built a simple IRC listener that will connect to a (probably
invalid) network, identify itself, and sit around waiting for the welcome
message.  After this has occurred, we join a channel.  If invited to another
channel, we will join it.  We spit out info about all incoming PINGs.

Filters and callbacks:
==============

YAIL is built with the concept of there being a single callback for any given
event.  Plugins can add functionality around an event via filters, but only
the IRC client implementation should be writing callbacks.  If you're building
a bot or an IRC client, you should be handling events.  If you're building
a library that others will use and won't implement its own IRC handling, you
should be primarily building filters.

When a callback is set, it overwrites any previous callback.  This allows sane
defaults to be set up if they make sense (such as responding to a PING with a
PONG), but if the user decides to do so, he can easily overwrite those
defaults.

Filters represent code that needs to be run before or after an event is
handled.  Filters running before an event can stop the event from triggering
its callback, but this should be used only in very special cases (such as
building a module to ignore events from specific users).  Filters should be
looked at as the hooks to be used when wanting to see an event, but shouldn't
generally be the final callback of an event.

Callback and filter methods:

* set_callback(:xxx): Replaces the existing handler (if any) for the given event with the block or proc object passed
  in.  Replace "xxx" with the callback name, such as :incoming_welcome, :outgoing_kick, etc.  This is typically going
  to be used for incoming and custom events, but if you don't mind getting your hands dirty with raw IRC commands,
  you can also overwrite the outgoing handlers this way.
* before_filter(:xxx), after_filter(:xxx): These create a filter for any event, and as above take a proc object or a
  block.  As many filters as desired may be created for an event.  A before_filter() call could be used to actually
  modify the data that gets sent to the callback, while an after_filter() would make more sense for something like
  logging or gathering stats only for events that make it through the callback.

Shortcut methods make the common operations take a bit less typing, and are hopefully intuitive enough that you don't
lose anything by using them.  They are all used similarly to set_callback, before_filter, and after_filter, but with
the event name as part of the method.  They must be given a proc object or a block.

* on_xxx: Sets a callback for an incoming event, so on_join will be the same as calling set_callback(:incoming_join)
* hearing_xxx: Creates a before-filter on incoming event xxx.  This is the same as calling before_filter(:incoming_xxx)
* heard_xxx: Creates an after-filter on incoming event xxx.  This is the same as calling after_filter(:incoming_xxx)
* saying_xxx: Creates a before-filter on outgoing event xxx.  This is the same as calling before_filter(:outgoing_xxx)
* said_xxx: Creates an after-filter on outgoing event xxx.  This is the same as calling after_filter(:outgoing_xxx)

Features of YAIL:
========

* Allows event callbacks to be specified very easily for all known IRC events,
  and in all cases, one can choose to override the default handling mechanisms.
  Generally speaking, it's best to be sure you know what you're doing when you
  decide to change how PING is responded to, but the capability is there.
* Allows handling outgoing messages, such as when privmsg is called.  You can
  filter data before it's sent out, log statistics after it's sent, or even
  customize the raw socket output.  This is one feature I didn't see anywhere
  else.
* Threads for input and output are persistent.  This is a feature, not a bug.
  Some may hate this approach, but I'm a total n00b to threads, and it seemed
  like the way to go, having thread loops responsible for their own piece of
  the library.  I'd *love* input here if anybody can tell me why this is a bad
  idea....
* Unlimited before- and after-callback filters allow for building a modular
  framework on top of YAIL.
* There is now only ONE callback per event as of YAIL 1.5 (2.0 will actually
  remove the code supporting the "legacy" event system).  This is a bit more
  constrictive than some libraries, but makes it a lot more clear what is the
  definitive handler of an event versus what provides functionality separate
  from said handler.  For simple bots, this should actually be easier to use.
* Easy to build a simple bot without subclassing anything.  One gripe I had
  with IRCSocket was that it was painful to do anything without subclassing
  and overriding methods.  No need here.
* Lots of built-in reporting comes free by subclassing IRCBot, but is no longer
  required otherwise.
* Built-in PRIVMSG buffering!  You can of course choose to not buffer, but by
  default you cannot send more than one message to a given target (user or
  channel) more than once per second.  Additionally, this buffering method is
  ideal for a bot that's trying to be chatty on two channels at once, because
  buffering is per-target, so queing up 20 lines on <tt>##foo</tt> doesn't mean waiting
  20 seconds to spit data out to <tt>##bar</tt>.  The one caveat here is that if your
  app is trying to talk to too many targets at once, the buffering still won't
  save you from a flood-related server kick.  If this is a problem for others,
  I'll look into building an even more awesome buffering system.
* The included IRCBot is a great starting point for building your own bot,
  but if you want something even simpler, just look at Net::YAIL's documentation
  for the most basic working examples.

I still have a lot to do, though.  The output API is definitely not fully
fleshed out.  I believe that the library is also missing a lot for people
who just have a different approach than me, since this was purely designed for
my own benefit, and then released almost exclusively to piss off the people
whose work I stole to get where I'm at today.  (Just kiddin', Pope)

This code is released under the MIT license.  I hear it's all the rage with
the kids these days.
