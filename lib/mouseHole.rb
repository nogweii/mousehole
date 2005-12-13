require 'rbconfig'
$:.unshift "#{ File.dirname __FILE__ }/#{ Config::CONFIG['arch'] }"
$:.unshift "#{ File.dirname __FILE__ }"

# mouseHole user libs
require 'mouseHole/constants'
require 'builder'
require 'ftools'
require 'open-uri'
require 'json/lexer'
require 'json/objects'
require 'logger'
require 'md5'
require 'redcloth'
require 'rexml/document'
require 'rexml/htmlwrite'
require 'stringio'
require 'timeout'
require 'yaml/dbm'
require 'webrick/utils'
require 'zlib'
require 'urihack'

# mouseHole internals
require 'mouseHole/evaluator'
require 'mouseHole/htmlconverter'
require 'mouseHole/feedconverter'
require 'mouseHole/userscript'
require 'mouseHole/starmonkey'
require 'mouseHole/proxyserver'
require 'mouseHole/databases'
require 'mouseHole/metamake'

module MouseHole

    include REXML
    include Converters

    # session id
    TOKEN = WEBrick::Utils::random_string 32

    HOSTS = Hash[ *%W[
        hoodwink.d  72.9.109.166
        ___._       72.9.109.166
    ] ]

    # Scripts use this method.
    def self.script &blk
        MetaMake(UserScript, &blk)
    end
end
