# This is a demonstration of net-yail just to see what a "real" bot could do without much work.
# Chances are good that you'll want to put things in classes and/or modules rather than go this
# route, so take this example with a grain of salt.
#
# Yes, this is a very simple copy of an existing "loudbot" implementation, but using YAIL to
# demonstrate the INCREDIBLE POWER THAT IS Net::YAIL.  Plus, plagiarism is a subset of the cool
# crime of stealing.
#
# Example of running this thing:
#     ruby bot_runner.rb --network irc.somewhere.org --channel "#bots"

require 'rubygems'

# Want a specific version of net/yail?  Try uncommenting this:
# gem 'net-yail', '1.x.y'

require 'net/yail'
require 'getopt/long'

# Hacks Array#shuffle and Array#shuffle! for people not using the latest ruby
require 'shuffle'

# Pulls in all of loudbot's methods - filter/callback handlers for IRC events
require 'loudbot'

# User specifies network, channel and nick
opt = Getopt::Long.getopts(
  ['--network', Getopt::REQUIRED],
  ['--channel', Getopt::REQUIRED],
  ['--nick', Getopt::REQUIRED],
  ['--debug', Getopt::BOOLEAN]
)

# Create bot object
@irc = Net::YAIL.new(
  :address    => opt['network'],
  :username   => 'Frakking Bot',
  :realname   => 'John Botfrakker',
  :nicknames  => [opt['nick'] || "SUPERLOUD"]
)

# Loud messages can be newline-separated strings in louds.txt or an array or hash serialized in
# louds.yml.  If messages are an array, we convert all of them to hash keys with a score of 1.
@messages = FileTest.exist?("louds.yml") ? YAML.load_file("louds.yml") :
            FileTest.exist?("louds.txt") ? IO.readlines("louds.txt") :
            {"ROCK ON WITH SUPERLOUD" => 1}
if Array === @messages
  dupes = @messages.dup
  @messages = {}
  dupes.each {|string| @messages[string.strip] = 1}
end

@random_messages = @messages.keys.shuffle
@last_message = nil
@dirty_messages = false

# If --debug is passed on the command line, we spew lots of filth at the user
@irc.log.level = Logger::DEBUG if opt['debug']

#####
#
# To learn the YAIL, begin below with attentiveness to commented wording
#
#####

# This is a filter.  Because it's past-tense ("heard"), it runs after the server's welcome message
# has been read - i.e., after any before-filters and the main hanler happen.
@irc.heard_welcome { |e| @irc.join(opt['channel']) if opt['channel'] }

# on_xxx means it's a callback for an incoming event.  Callbacks run after before-filters, and
# replaces any existing incoming invite callback.  YAIL has very few built-in callbacks, so
# this is a safe operation.
@irc.on_invite { |e| @irc.join(e.channel) }

# This is just another callback, using the do/end block form.  We auto-message the channel on join.
@irc.on_join do |e|
  @irc.msg(e.channel, "WHATS WRONG WITH BEING SEXY") if e.nick == @irc.me
end

# You should *never* override the on_ping callback unless you handle the PONG manually!!
# Filters, however, are perfectly fine.
#
# Here we're using the ping filter to actually do the serialization of our messages hash.  Since
# we know pings are regular, this is kind of a hack to serialize every few minutes.
@irc.heard_ping do
  unless @dirty_messages
    File.open("louds.yml", "w") {|f| f.puts @messages.to_yaml}
    @dirty_messages = false
  end
end

# This is a before-filter - using the present tense means it's a before-filter, and using a tense
# of "hear" means it's for incoming messages (as opposed to "saying" and "said", where we'd filter
# our outgoing messages).  Here we intercept all potential commands and send them to a method.
@irc.hearing_msg {|e| do_command($1, e) if e.message =~ /^!(.*)$/ }

# Another filter, but in-line this time - we intercept messages directly to the bot.  The call to
# +handled!+ tells the event not to run any more filters or the main callback.
@irc.hearing_msg do |e|
  if e.message =~ /^#{@irc.me}/
    random_message(e.channel)
    e.handled!
  end
end

# This is our primary message callback.  We know our filters have caught people talking to us and
# any command-style messages, so we don't need to worry about those situations here.  The decision
# to make this the primary callback is pretty arbitrary - do what makes the most sense to you.
#
# Note that this is a proc-based filter - we handle the message entirely in incoming_message.
@irc.on_msg self.method(:incoming_message)

# Start the bot - the bang (!) calls the version of start_listening that runs an endless loop
@irc.start_listening!
