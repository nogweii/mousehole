require 'ostruct'
options = <%= options.auto_marshal %>
$:.unshift options.lib_dir
 
require 'logger'
require 'mouseHole'
require 'mouseHole/moonproxy'

begin
    server = MouseHole::ProxyServer( MouseHole::MoonProxy )::new( options,
        :BindAddress => options.host,
        :Port => options.port
    )
    server.mount( "/images", WEBrick::HTTPServlet::FileHandler, File.join( options.app_dir, 'images' ) )
    trap( :INT ) { server.shutdown }
    server.start
rescue Object => err
    p err.message
    p err.backtrace
end
