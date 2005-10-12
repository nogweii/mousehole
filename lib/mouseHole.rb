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
require 'dnshack'

# mouseHole internals
require 'mouseHole/evaluator'
require 'mouseHole/htmlconverter'
require 'mouseHole/feedconverter'
require 'mouseHole/userscript'
require 'mouseHole/starmonkey'
require 'mouseHole/proxyserver'

module MouseHole

    include REXML
    include Converters

    # session id
    TOKEN = WEBrick::Utils::random_string 32

    # Scripts use this method.
    def self.script &blk
        uscript = UserScript.new
        uscript.instance_eval &blk
        uscript
    end

    # Wrapper for a gloabal logger.  Found in James Britt's catapult.
    # If MouseHole ends up being run as a Windows service or something similar, then
    # it may make sense to replace file logging with something more approriate
    # to the processing environment, such as an event log.  But you likely will not
    # want scads of debug messages going there, so be sure the log level or
    # whatever is set accordingly.
    class Log
        @@mouselog = Logger.new( File.join( "mouse.log"  ) )
        @@mouselog.level = Logger::DEBUG
        @@conf = {}

        def self.conf=( conf )
            @@conf = conf
        end

        def self.method_missing( meth , *args )
            @@mouselog.send( meth , *args ) if @@conf[:logs_on]
        end
    end
end
