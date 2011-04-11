require 'rubygems'

# Want a specific version of net/yail?  Try uncommenting this:
# gem 'net-yail', '1.x.y'

require 'net/yail'
require 'getopt/long'

# User specifies channel and nick
opt = Getopt::Long.getopts(
  ['--network',  Getopt::REQUIRED],
  ['--nick', Getopt::REQUIRED],
  ['--loud', Getopt::BOOLEAN]
)

irc = Net::YAIL.new(
  :address    => opt['network'],
  :username   => 'Frakking Bot',
  :realname   => 'John Botfrakker',
  :nicknames  => [opt['nick']]
)

irc.log.level = Logger::DEBUG if opt['loud']

# Register handlers
irc.heard_welcome { |e| irc.join('#bots') }       # Filter - runs after the server's welcome message is read
irc.on_invite     { |e| irc.join(e.channel) }     # Handler - runs on an invite message

# Start the bot and enjoy the endless loop
irc.start_listening!
