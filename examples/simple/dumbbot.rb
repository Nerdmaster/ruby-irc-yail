require 'rubygems'

# Want a specific version of net/yail?  Try uncommenting this:
# gem 'net-yail', '1.x.y'

require 'net/yail'
require 'getopt/long'

# User specifies channel and nick
opt = Getopt::Long.getopts(
  ['--network',  Getopt::REQUIRED],
  ['--nick', Getopt::REQUIRED],
  ['--port', Getopt::REQUIRED],
  ['--loud', Getopt::BOOLEAN]
)

opts = {
  :address    => opt['network'],
  :username   => 'FrakkingBot',
  :realname   => 'John Botfrakker',
  :nicknames  => [opt['nick']],
}
opts[:port] = opt['port'] if opt['port']

irc = Net::YAIL.new(opts)

irc.log.level = Logger::DEBUG if opt['loud']

# Register handlers
irc.heard_welcome { |e| irc.join('#bots') }       # Filter - runs after the server's welcome message is read
irc.on_invite     { |e| irc.join(e.channel) }     # Handler - runs on an invite message

# Start the bot and enjoy the endless loop
irc.start_listening!
