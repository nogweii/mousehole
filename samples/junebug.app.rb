# (From _why: http://rubyforge.org/pipermail/mousehole-scripters/2007-January/000241.html)
#
# MouseHole2 is built on Camping, so you can put Camping apps right in the
# ~/.mouseHole/ directory and they'll startup.  Camping's blog example, Tepee,
# etc.
# 
# "Junebug is a simple, clean, minimalist wiki intended for personal use."
# (http://www.junebugwiki.com/)
#
# Junebug is written in Camping and follows Camping's rules, but is distributed as
# a Gem. To install Junebug: gem install junebug-wiki.
#
# Copy this file to ~/.mouseHole/junebug.app.rb.  And start up
# mouseHole and it'll be mounted at http://localhost:3704/junebug.
#

require 'junebug/config'
JUNEBUG_ROOT = ENV['JUNEBUG_ROOT'] = File.join(Junebug::Config.rootdir, "deploy")
require(Junebug::Config.script)
  
def Junebug.config; {'startpage' => 'Home_Page'}; end
Junebug.create
