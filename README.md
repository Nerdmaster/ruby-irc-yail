Latest documentation is always at [Nerdbucket.com](http://ruby-irc-yail.nerdbucket.com/)

Net::YAIL is a library built for dealing with IRC communications in Ruby.
This is a project I've been building for about three years, based
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

For the nitty-gritty, you can see all this stuff in the [Net::YAIL docs](http://ruby-irc-yail.nerdbucket.com/)
page, as well as more complete documentation about the system.  For a complete bot,
check out the IRCBot source code.  Below is just a very simple example:

    require 'rubygems'
    require 'net/yail'

    irc = Net::YAIL.new(
      :address    => 'irc.someplace.co.uk',
      :username   => 'Frakking Bot',
      :realname   => 'John Botfrakker',
      :nicknames  => ['bot1', 'bot2', 'bot3']
    )

    irc.prepend_handler :incoming_welcome, proc {|text, args|
      irc.join('#foo')
      return false
    }

    irc.start_listening
    while irc.dead_socket == false
      # Avoid major CPU overuse by taking a very short nap
      sleep 0.05
    end

Now we've built a simple IRC listener that will connect to a (probably
invalid) network, identify itself, and sit around waiting for the welcome
message.  After this has occurred, we join a channel and return false.

Features of YAIL:
========

* Allows event handlers to be specified very easily for all known IRC events,
  and except in a few rare cases one can choose to override the default
  handling mechanisms.
* Allows handling outgoing messages, such as when privmsg is called.  The API
  won't allow you to stop the outgoing message (though I may offer this if
  people want it), but you can filter data before it's sent out.  This is one
  thing I didn't see anywhere else.
* Threads for input and output are persistent.  This is a feature, not a bug.
  Some may hate this approach, but I'm a total n00b to threads, and it seemed
  like the way to go, having thread loops responsible for their own piece of
  the library.  I'd *love* input here if anybody can tell me why this is a bad
  idea....
* "Stacked" event handling is possible if you want to provide a very modular
  framework of your own.  When you prepend a handler, its return determines if
  the next handler will get called.  This isn't useful for a simple bot most
  likely, but can have some utility in bigger projects where a single event
  may need to be dispatched to several handlers.
  * The upcoming <s>2.0</s>1.4 release will change this greatly, though -
    you should start looking at your app's handlers in terms of whether they
    are the "core" handler or just a "filter".  More info to come!
* Easy to build a simple bot without subclassing anything.  One gripe I had
  with IRCSocket was that it was painful to do anything without subclassing
  and overriding methods.  No need here.
* Lots of built-in reporting.  You may hate this part, but for a bot, it's
  really handy to have most incoming data reported on some level.  I may make
  this optional at some point, but only if people complain, since I haven't
  yet seen a need to do so....
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
