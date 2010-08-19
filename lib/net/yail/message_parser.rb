# Net::YAIL's solution to the amazing lack of *useful* IRC message parsers.  So far as I know,
# this will parse any message coming from an RFC-compliant IRC server.

module Net
class YAIL

# This is my lame attempt to convert the BNF-style grammar from RFC 1459 into
# useable ruby regexes.  The hope here is that one can effectively match an
# incoming message with high accuracy.  Usage:
#
#     line = ':Nerdmaster!jeremy@nerdbucket.com PRIVMSG Nerdminion :Do my bidding!!'
#     message = Net::YAIL::MessageParser.new(line)
#     # hash now has all kinds of useful pieces of the incoming message:
#     puts line.nick        # "Nerdmaster"
#     puts line.user        # "jeremy"
#     puts line.host        # "nerdbucket.com"
#     puts line.prefix      # "Nerdmaster!jeremy@nerdbucket.com"
#     puts line.command     # "PRIVMSG"
#     puts line.params      # ["Nerdminion", "Do my bidding!!"]
class MessageParser
  attr_reader :nick, :user, :host, :prefix, :command, :params, :servername

  # Note that all regexes are non-greedy.  I'm scared of greedy regexes, sirs.
  USER        = /\S+?/
  # RFC suggested that a nick *had* to start with a letter, but that seems to
  # not be the case.
  NICK        = /[\w\d\\|`'^{}\]\[-]+?/
  HOST        = /\S+?/
  SERVERNAME  = /\S+?/

  # This is automatically grouped for ease of use in the parsing.  Group 1 is
  # the full prefix; 2, 3, and 4 are nick/user/host; 1 is also servername if
  # there was no match to populate 2, 3, and 4.
  PREFIX      = /((#{NICK})!(#{USER})@(#{HOST})|#{SERVERNAME})/
  COMMAND     = /(\w+|\d{3})/
  TRAILING    = /\:\S*?/
  MIDDLE      = /(?: +([^ :]\S*))/

  MESSAGE     = /^(?::#{PREFIX} +)?#{COMMAND}(.*)$/

  def initialize(line)
    @params = []

    if line =~ MESSAGE
      matches = Regexp.last_match

      @prefix = matches[1]
      if (matches[2])
        @nick = matches[2]
        @user = matches[3]
        @host = matches[4]
      else
        @servername = matches[1]
      end

      @command = matches[5]

      # Args are a bit tricky.  First off, we know there must be a single
      # space before the arglist, so we need to strip that.  Then we have to
      # separate the trailing arg as it can contain nearly any character. And
      # finally, we split the "middle" args on space.
      arglist = matches[6].sub(/^ +/, '')
      arglist.sub!(/^:/, ' :')
      (middle_args, trailing_arg) = arglist.split(/ +:/, 2)
      @params.push(middle_args.split(/ +/), trailing_arg)
      @params.compact!
      @params.flatten!
    end
  end
end

end
end
