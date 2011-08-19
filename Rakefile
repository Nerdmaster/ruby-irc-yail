require 'rake/gempackagetask'
require 'rake/testtask'
require 'lib/net/yail/yail-version'
spec = Gem::Specification.new do |s|
  s.platform          = Gem::Platform::RUBY
  s.name              = "net-yail"
  s.version           = Net::YAIL::VERSION
  s.author            = "Jeremy Echols"
  s.email             = "yail<at>nerdbucket dot com"
  s.description       = %Q|
Net::YAIL is an IRC library written in pure Ruby.  Using simple functions, it
is trivial to build a complex, event-driven IRC application, such as a bot or
even a full command-line client.  All events can have a single callback and
any number of before-callback and after-callback filters.  Even outgoing events,
such as when you join a channel or send a message, can have filters for stats
gathering, text filtering, etc.
|.strip

  s.summary           = "Yet Another IRC Library: wrapper for IRC communications in Ruby."
  s.files             = FileList[ 'examples/simple/*', 'examples/logger/*', 'examples/loudbot/*.rb', 'lib/net/*.rb', 'lib/net/yail/*', 'test/*.rb' ].to_a
  s.homepage          = 'http://ruby-irc-yail.nerdbucket.com/'
  s.rubyforge_project = 'net-yail'
  s.require_path      = "lib"
  s.test_files        = Dir.glob('tests/*.rb')
  s.has_rdoc          = true
  s.rdoc_options      = ['--main', 'Net::YAIL']
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

Rake::TestTask.new do |t|
  t.libs << "tests"
  t.test_files = FileList['tests/tc_*.rb']
  t.verbose = true
end

task :default => "pkg/#{spec.name}-#{spec.version}.gem" do
  puts "generated latest version"
end
