require 'rubygems'
require 'fileutils'
require 'hpricot'
require 'logger'
require 'net/http'
require 'resolv-replace'
require 'rexml/document'
require 'rexml/htmlwrite'
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

  def self.create
    Models.create_schema :assume => (Models::App.table_exists? ? 1.0 : 0.0)
  end
end
