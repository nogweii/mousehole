# the libraries
require 'fileutils'
require 'hpricot'
require 'logger'
require 'open-uri'
require 'resolv-replace'
require 'zlib'

require 'camping'

Camping.goes :MouseHole

# mouseHole's minor hacks to a few libs
require 'mouseHole/hacks/http'
require 'mouseHole/hacks/json'
require 'mouseHole/hacks/mongrel'
require 'mouseHole/hacks/uri'

# mouseHole's mixins that end up in many places
require 'mouseHole/mixins/logger'
require 'mouseHole/mixins/handler'

require 'mouseHole/htmlconverter'
require 'mouseHole/feedconverter'

# mouseHole's proxy infrastructure
require 'mouseHole/central'
require 'mouseHole/proxyhandler'
require 'mouseHole/app'

# mouseHole's doorway app
require 'mouseHole/helpers'
require 'mouseHole/models'
require 'mouseHole/views'
require 'mouseHole/controllers'

module MouseHole
  VERSION = "2.0"

  HOSTS = Hash[ *%W[
    hoodwink.d  72.36.180.126
    ___._       72.36.180.125
  ] ]

  DOMAINS = ['mouse.hole', 'mh']

  ALPHA = [*('a'..'z')] + [*('A'..'z')] + [*('0'..'9')] + ["-"]

  # Generate a 32-character token.  Each app gets its own token.
  def self.token
    (0...32).map { ALPHA[rand(ALPHA.size)] }.join
  end

  # Create the database for MouseHole, set it all up.
  def self.create
    Models.create_schema :assume => (Models::App.table_exists? ? 1.0 : 0.0)
  end
end
