require 'rubygems'
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
  :nicknames  => [opt['nick']],
  :loud       => opt['loud']
)

# Register handlers
irc.prepend_handler(:incoming_welcome) {|text, args| irc.join('#bots') }
irc.prepend_handler(:incoming_invite) {|full, user, channel| irc.join(channel) }

# Start the bot and enjoy the endless loop
irc.start_listening!
