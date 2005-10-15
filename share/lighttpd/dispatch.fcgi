#!/usr/bin/env ruby
require 'ostruct'
options = <%= options.auto_marshal %>

$:.unshift options.lib_dir

require 'fcgi.so'
require 'logger'
require 'mouseHole'
require 'mouseHole/moonproxy'

MOUSEHOST = options.host
MOUSEPORT = options.port

FCGI.each_request do |req|
    begin
        server = MouseHole::ProxyServer( MouseHole::MoonProxy )::new( options,
            :Logger => Logger.new( File.join( options.log_dir, 'fastcgi.log' ) ),
            :BindAddress => options.host,
            :Port => options.port
        )
        server.mount( "/images", WEBrick::HTTPServlet::FileHandler, File.join( options.app_dir, 'images' ) )
        trap( :INT ) { server.shutdown }
        server.start( req.env, req.in, req.out )
        req.finish
    rescue Object => err
        req.out << "Content-Type: text/html\n\n"
        req.out << err.message
        req.out << err.backtrace
        req.finish
    end
end
