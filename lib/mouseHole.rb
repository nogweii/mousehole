require 'rubygems'
require 'fileutils'
require 'hpricot'
require 'json-hack'
require 'logger'
require 'net/http'
require 'open-uri'
require 'resolv-replace'
require 'urihack'
require 'zlib'

require 'camping'

Camping.goes :MouseHole

require 'mouseHole/htmlconverter'
require 'mouseHole/feedconverter'

require 'mouseHole/central'
require 'mouseHole/proxyhandler'
require 'mouseHole/app'

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

  def self.token
    (0...32).map { ALPHA[rand(ALPHA.size)] }.join
  end

  def self.create
    Models.create_schema :assume => (Models::App.table_exists? ? 1.0 : 0.0)
  end
end
