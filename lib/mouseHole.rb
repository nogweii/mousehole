require 'rbconfig'
$:.unshift "#{ File.dirname __FILE__ }/#{ Config::CONFIG['arch'] }"
$:.unshift "#{ File.dirname __FILE__ }"

# mouseHole user libs
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
require 'webrick/httpproxy'
require 'yaml/dbm'
require 'zlib'
require 'dnshack'

class MouseHole < WEBrick::HTTPProxyServer

    VERSION = "1.2"

    include REXML

    # session id
    TOKEN = WEBrick::Utils::random_string 32

    # locate ~/.mouseHole
    [
        [ENV['HOME'], File.join( ENV['HOME'], '.mouseHole' )],
        [ENV['APPDATA'], File.join( ENV['APPDATA'], 'MouseHole' )]
    ].each do |home_top, home_dir|
        next unless home_top
        if File.exists? home_top
            File.makedirs( home_dir )
            MH = home_dir
            break
        end
    end

    attr_accessor :user_scripts, :temp_scripts

    def initialize(*args)
        super(*args)
        config.merge!(
            :RequestCallback => method( :prewink ),
            :ProxyContentHandler => method( :upwink )
        )

        # various dispatch
        mount_proc( "/" ) do |req, res| 
            res['content-type'] = 'text/html'
            scripted_mounts( req, res )
        end
        mount_proc( "/mouseHole" ) do |req, res|
            res['content-type'] = 'text/html'
            path_parts = req.path_info.split( '/' ).reject { |x| x.to_s.strip.size == 0 }
            mount = path_parts.shift
            if mount
                method( "server_#{ mount }" ).call( path_parts, req, res )
            else
                mousehole_home( req, res )
            end
            no_cache res
        end
        mount( "/favicon.ico", nil )

        # read user scripts on startup
        @etags, @temp_scripts, @user_scripts = {}, {}, {}
        @user_data_dir, @user_script_dir = File.join( MH, 'data' ), File.join( MH, 'userScripts' )
        File.makedirs( @user_script_dir )
        File.makedirs( @user_data_dir )
        @started = Time.now
        @db = YAML::DBM.open( File.join( @user_data_dir, 'mouseHole' ) )
        @conf = @db['conf'] || {:rewrites_on => true, :mounts_on => true, :logs_on => false}
        Log.conf = @conf
        Dir["#{ @user_script_dir }/*.user.{rb,js}"].each do |userb|
            userb = File.basename userb
            load_user_script userb
        end

        debug( "MouseHole proxy config: #{ config.inspect }" )
    end
    
    # intercept URLs for redirection
    def service(req, res)
        if %w{GET POST PUT HEAD}.include? req.request_method
            # do redirections
            rewrote = false
            each_fresh_script do |path, script|
                if req.request_uri.path =~ %r!^/#{ script.token }/!
                    rewrote = script.do_registered_uri( URI($'), req, res )
                end
            end
            if not rewrote
                super(req, res)
            else
                res['Content-Length'] = res.body.length
            end
        else
            super(req, res)
        end
    end

    # Loops through scripts, ensuring freshness, reloading as needed
    def each_fresh_script( which = :active )
        scripts = @user_scripts
        if which == :all
            scripts = scripts.to_a + Dir["#{ @user_script_dir }/*.user.{rb,js}"].map do |path| 
                [File.basename(path)] unless scripts[File.basename(path)]
            end.compact
        end
        scripts.each do |path, script|
            fullpath = "#{ @user_script_dir }/#{ path }"
            if not File.exists? fullpath
                @user_scripts.delete(path)
            else
                if script.nil? or File.mtime(fullpath) > ( script.mtime rescue Time.at(0) )
                    puts( "Reloading #{ path }, as it has changed." )
                    @user_scripts[path] = script = load_user_script( path )
                end
                active = script.active if script.respond_to?(:active)
                next unless active or which == :all
                yield path, script
            end
        end
    end

    # Loads a user script and merges in the user's configuration for that script.
    def load_user_script( userb )
        if @user_scripts[userb] and @user_scripts[userb].respond_to?(:db) and @user_scripts[userb].db
            @user_scripts[userb].db.close rescue nil
        end
        fullpath = "#{ @user_script_dir }/#{ userb }"
        script = nil
        begin
            if userb =~ /\.user\.js$/
                script = StarmonkeyUserScript.new( File.read( fullpath ) )
            else
                script = eval( File.read( fullpath ) )
            end
            script.db = YAML::DBM.open( File.join( @user_data_dir, userb ) )
            script.mtime = File.mtime( fullpath )
            script.active = true
            ( @db["script:#{ userb }"] || {} ).each do |k,v|
                script.method( "#{ k }=" ).call( v )
            end
            if script.mount
                ::HOSTS[script.mount.to_s] = "#{ MOUSEHOST }:#{ MOUSEPORT }"
                ::HOSTS["mouse.#{ script.mount }"] = "#{ MOUSEHOST }:#{ MOUSEPORT }"
            end
        rescue Exception => e
            script = e
        end
        @user_scripts[userb] = script
    end

    # Generates a new MouseHole Etag from a regular Etag.
    def mousetag( etag )
        if etag and not etag.empty?
            etag = "#{ etag }"
            etag[1,0] = "MH-"
        end
        etag
    end

    # Removes cache headers from HTTPResponse +res+.
    def check_cache( res )
        if res['etag']
            res['etag'] = mousetag( res['etag'] )
            @etags[res['etag'].to_s] = Time.now
        end
    end

    # Prevents caching, even on the back button
    def no_cache( res )
        res['etag'] = nil
        res['expires'] = 'Sat, 01 Jan 2000 00:00:00 GMT'
        res['cache-control'] = 'no-store, no-cache'
        res['pragma'] = 'no-cache'
    end

    # MrCode's gzip decoding from WonderLand!
    def decode(res)
        case res['content-encoding']
        when 'gzip':
            gzr = Zlib::GzipReader.new(StringIO.new(res.body))
            res.body = gzr.read
            gzr.close
            res['content-encoding'] = nil
        when 'deflate':
            res.body = Zlib::Inflate.inflate(res.body)
            res['content-encoding'] = nil
        end
    end

    # Before sending a request, alter outgoing headers.
    def prewink( req, res )
        # proxy handles the gzip encoding
        req.header['accept-encoding'] = ['gzip','deflate']

        # watch for possible HTML, allow caching of proxy-processed content
        if req.header['accept'].to_s =~ %r!text/html!
            etag = req.header['if-none-match'].to_s
            unless etag and @etags[etag]
                req.header.delete 'if-modified-since'
                req.header.delete 'if-none-match'
            else
                req.header['if-none-match'][0].gsub!( /^(.)MH-/, '\1' )
            end
        end

        # allow user scripts to modify the request headers
        # each_fresh_script do |path, script|
        #     next unless script.match req.request_uri
        #     script.prewrite( req, res )
        # end
    end

    # Is this request referencing a URL handled by MouseHole?
    def is_mousehole? req
        if ::HOSTS.has_key? req.host
            host, port = ::HOSTS[ req.host ].split ':'
        end
        host ||= req.host
        port ||= req.port
        host == @config[:BindAddress] and port.to_i == @config[:Port].to_i
    end

    # After response is received, pass to qualifying scripts.
    # Also detects user scripts in the wild.
    def upwink( req, res )
        unless is_mousehole? req
            if req.request_uri.path =~ /\.user\.(rb|js)$/
                check_cache res
                if res.status == 200
                    decode(res)
                    scrip = File.basename( req.request_uri.path )
                    evaluator = Evaluator.new( scrip, res.body.dup )
                    t = Tempfile.new( scrip )
                    t.write evaluator.code
                    evaluator.script_id = t.path
                    @temp_scripts[t.path] = [t, req.request_uri.to_s, scrip]
                    t.close
                    Thread.start( evaluator ) do |e|
                        e.taint
                        $SAFE = 4
                        e.evaluate
                    end.join
                    res.body = installer_pane( req, evaluator, "#{ home_uri req }mouseHole/install" )
                    res['content-type'] = 'text/html'
                    res['content-length'] = res.body.length
                end
            elsif @conf[:rewrites_on]
                case res.content_type
                when /^text\/html/, /^application\/xhtml+xml/
                    check_cache res
                    if res.status == 200
                        doc = nil
                        each_fresh_script do |path, script|
                            next unless script.match req.request_uri
                            unless doc
                                decode(res)
                                doc = script.read_xhtml( res.body, true ) rescue nil
                            end
                            script.do_rewrite( doc, req, res )
                        end
                        if doc
                            doc.write( res.body = "" )
                            res['content-length'] = res.body.length
                        end
                    end
                end
            end
        end
    end

    # MouseHole's own top URL.
    def home_uri( req ); is_mousehole?( req ) ? "/" : "http://#{ @config[:BindAddress] }:#{ @config[:Port ] }/"; end

    # The home page, primary configuration.
    def mousehole_home( req, res )
        title = "MouseHole"
        content = %{
            <style type="text/css">
                .details { clear: both; margin: 12px 8px; }
                .mount, h4, input { float: left; margin: 0 8px; }
                h4 { margin: 0; }
                li { list-style: none; }
            </style>
            <div id="installer">
                <div class="quickactions">
                <ul>
                <li><input type="checkbox" name="rewrites" onClick="sndReq('/mouseHole/toggle_rewrites')"
                    #{ 'checked' if @conf[:rewrites_on] } /> Script rewriting on?</li>
                <li><input type="checkbox" name="mounts" onClick="sndReq('/mouseHole/toggle_mounts')"
                    #{ 'checked' if @conf[:mounts_on] } /> Script mounts on?</li>
                <li class="wide"><input type="checkbox" name="logs" onClick="sndReq('/mouseHole/toggle_logs')"
                    #{ 'checked' if @conf[:logs_on] } /> Log debug messages to mouse.log?</li>
                </div>
                <h1>Scripts Installed</h1>
                <p>The following scripts are installed on your mouseHole.  Check marks indicate
                that the script is active.  You may toggle it on or off.  Click on the script's
                name to configure it.</p><ul>}
            script_count = 0
        each_fresh_script :all do |path, script|
            mounted = nil
            if script.respond_to? :mount
                if script.mount
                    mounted = %{<p class="mount">[<a href="/#{ script.mount }">/#{ script.mount }]</a></p>}
                end
                content += %{<li><input type="checkbox" name="#{ File.basename path }/toggle"
                    onClick="sndReq('/mouseHole/toggle/#{ File.basename path }')"
                    #{ 'checked' if script.active } />
                    <h4><a href="/mouseHole/config/#{ File.basename path }">#{ script.name }</a></h4>
                    #{ mounted }<p class="details">#{ script.description }</p></li>}
            else
                ctx, lineno, func, message = "#{ script.backtrace[1] }:#{ script.message }".split( /\s*:\s*/, 4 )        
                if ctx == "(eval)"
                    ctx = nil
                end
                content += %{<li><input type="checkbox" name="#{ File.basename path }/toggle" disabled="true" />
                    <h4>#{ path }</h4>
                    <p class="details">Script failed due to <b>#{ script.class }</b> on line 
                    <b>#{ lineno }</b>#{ " in file <b>#{ ctx }</b>" if ctx }: <u>#{ message }</u></p></li>}
            end
            script_count += 1
        end
        content += %{<li><p>#{ script_count.zero? ? "No" : script_count } user scripts installed.</p></li>}
        content += %{</ul>
                <div class="quickactions">
                <p>MouseHole #{ VERSION } by <a href="http://whytheluckystiff.net/">why the lucky stiff</a><br />
                    Running on ruby #{ ::RUBY_VERSION } (#{ ::RUBY_RELEASE_DATE }) [#{ ::RUBY_PLATFORM }]</li>
                    Built for the <a href="http://hoodwink.d/">hoodwinkers</a>
                </p>
                </div>
            </div>
        }
        res.body = installer_html( req, title, content )
    end

    # Load a string as a Regexp, if it looks like one.
    def build_match( val )
        if val =~ /^\/(.*)\/([mix]*)$/
            r, m = $1, $2
            mods = nil
            unless m.to_s.empty?
                mods = 0x00
                mods |= Regexp::EXTENDED if m.include?( 'x' )
                mods |= Regexp::IGNORECASE if m.include?( 'i' )
                mods |= Regexp::MULTILINE if m.include?( 'm' )
            end
            Regexp.new( r, mods )
        elsif val =~ /^\s*\{(.*)\}\s*$/
            JSON::Lexer.new( val ).nextvalue
        else
            val
        end
    end

    # RSS feed of all user scripts.  Two good uses of this: your browser can build a bookmark list of all
    # your user scripts from the feed (or) if you share a proxy, you can be informed concerning the user scripts
    # people are installing.
    def server_rss( args, req, res )
        res['content-type'] = 'text/xml'
        rss( res.body = "" ) do |c|
            uri = req.request_uri.dup
            uri.path = '/'

            c.title "MouseHole User Scripts: #{ uri.host }"
            c.link "#{ uri }"
            c.description "A list of user script installed for the MouseHole proxy at #{ uri }"

            c.item do |item|
                item.title "MouseHole"
                item.link "#{ uri }"
                item.guid "#{ uri }"
                item.dc :creator, "MouseHole"
                item.dc :date, @started
                item.description "The primary MouseHole configuration page."
            end

            each_fresh_script :all do |path, script|
                if script
                    c.item do |item|
                        uri.path = "/mouseHole/config/#{ path }"
                        item.title "#{ script.name }: Configuration"
                        item.link "#{ uri }"
                        item.guid "#{ uri }"
                        item.dc :creator, "MouseHole"
                        item.dc :date, script.mtime
                        item.description script.description
                    end
                    if script.mount
                        c.item do |item|
                            uri.path = "/#{ script.mount }"
                            item.title "#{ script.name }: Mounted at /#{ script.mount }"
                            item.link "#{ uri }"
                            item.guid "#{ uri }"
                        end
                    end
                end
            end
        end
    end

    # Dumps database to the browser, for debugging, for knowledge.
    def server_database( args, req, res )
        databases = [['mouseHole', @db]]
        if req.query['all']
            databases += @user_scripts.map { |path,script| [script.name, script.db] if script.respond_to? :db }.compact
        end
        body = %{<div id="installer"><h1>Database dump</h1>}
        databases.each do |area, db|
            body += %[<h2>#{ area }</h2>
                <pre>#{ db.inject( {} ) { |hsh,(k,v)| hsh[k] = v; hsh }.to_yaml }</pre>]
        end
        unless req.query['all']
            body += %{<p><a href="?all=1">Show all data</a></p>}
        end
        body += %{</div>}
        res.body = installer_html req, "Database dump", body
    end

    # Turns on/off rewriting.
    def server_toggle_rewrites( *args )
        @conf[:rewrites_on] = !@conf[:rewrites_on]
        @db['conf'] = @conf
    end

    # Turns on/off mounts.
    def server_toggle_mounts( *args )
        @conf[:mounts_on] = !@conf[:mounts_on]
        @db['conf'] = @conf
    end

    # Turns on/off logs.
    def server_toggle_logs( *args )
        @conf[:logs_on] = !@conf[:logs_on]
        @db['conf'] = @conf
    end

    # Adds/removes URL matches from user scripts.
    def server_imatch( args, req, res ); _server_match( true, args, req, res ); end
    def server_xmatch( args, req, res ); _server_match( false, args, req, res ); end
    def _server_match( inc, args, req, res )
        userb = args.first
        if ( script = @user_scripts[userb] ) and script.respond_to? :matches
            if req.query['remove'] 
                script.remove_match( build_match( req.query['remove'] ) )
            end
            if req.query['match'] 
                if inc
                    script.include_match( build_match( req.query['match'] ) )
                else
                    script.exclude_match( build_match( req.query['match'] ) )
                end
            end
            scriptset = ( @db["script:#{ userb }"] || {} )
            scriptset[:matches] = @user_scripts[userb].matches
            @db["script:#{ userb }"] = scriptset
            res.body = scriptset.inspect
        end
    end

    # Turns scripts on/off.
    def server_toggle( args, req, res )
        userb = args.first
        if @user_scripts[userb] and @user_scripts[userb].respond_to? :active
            scriptset = ( @db["script:#{ userb }"] || {} )
            scriptset[:active] = !@user_scripts[userb].active
            @user_scripts[userb].active = scriptset[:active]
            @db["script:#{ userb }"] = scriptset
            res.body = scriptset.inspect
        end
    end

    # Reset script config.
    def server_reset( args, req, res )
        userb = args.first
        if @user_scripts[userb] and @user_scripts[userb].respond_to? :active
            @db["script:#{ userb }"] = {}
        end
    end

    # Script configuration page.
    def server_config( args, req, res )
        userb = args.first
        script = @user_scripts[userb]
        if script and script.respond_to? :matches
            title = script.name
            include_matches, exclude_matches = script.matches.partition { |k,v| v }.map do |matches|
                matches.map { |k,v| "<option>#{ k.respond_to?( :to_str ) ? k.to_str : ( k.respond_to?( :source ) ? k.inspect : k.to_json ) }</option>" }
            end
            if script.install_uri
                install_uri = %{<p>Installed from: <a href="#{ script.install_uri }">#{ script.install_uri }</a></p>} 
            end
            script_config = script.do_configure( req, res )
            content = %{
                <form method="POST">
                <input type="hidden" id="userb" value="#{ userb }" />
                <div id="installer">
                <h1>#{ script.name }</h1>
                <p>#{ script.description }</p>#{ install_uri }#{ script_config }
                <div class="matchset">
                    <h2>Included pages</h2>
                    <select class="matches" id="i_matches" size="6">
                    #{ include_matches * "\n" }
                    </select>
                    <input type="button" name="add" value="Add..." onClick="prompt_new_match('i_matches')" />
                    <input type="button" name="edit" value="Edit..." onClick="prompt_edit_match('i_matches')" />
                    <input type="button" name="remove" value="Remove" onClick="remove_a_match('i_matches')" />
                </div>
                <div class="matchset">
                    <h2>Excluded pages</h2>
                    <select class="matches" id="x_matches" size="6">
                    #{ exclude_matches * "\n" }
                    </select>
                    <input type="button" name="add" value="Add..." onClick="prompt_new_match('x_matches')" />
                    <input type="button" name="edit" value="Edit..." onClick="prompt_edit_match('x_matches')" />
                    <input type="button" name="remove" value="Remove" onClick="remove_a_match('x_matches')" />
                </div>
                <br clear="all" />
                <p><input type="button" name="reset" value="Reset to Defaults" onClick="if ( confirm( 'Would you really like to reset the script configuration?' ) ) { reset_config(); }" /></p>
                </div>
                </form>
            }
        end
        res.body = installer_html( req, title, content ) 
    end

    # Script installation process.
    def server_install( args, req, res )
        userb = req.query[ 'script_id' ]
        if req.query[ 'do_it' ] and @temp_scripts[userb] and File.exists? userb
            temp, install_uri, path = @temp_scripts[userb]

            scriptset = ( @db["script:#{ path }"] || {} )
            scriptset[:install_uri] = install_uri
            @db["script:#{ path }"] = scriptset

            File.copy( userb, File.join( @user_script_dir, path ) )
            load_user_script path
            @temp_scripts.delete userb
            res['location'] = "/mouseHole"
            raise WEBrick::HTTPStatus::Found
        else
            title = "Script not installed!"
            content = %{<p class="tiny">#{ title }</p>
                <div id="installer">
                <h1>Script Missing</h1>
                <p>The script you are trying to install is gone.  This may have been
                caused by restarting MouseHole during installation or clearing your
                temp folder.</p>
                </div>}
            res.body = installer_html( req, title, content ) 
        end
    end

    # Script installation page.
    def installer_pane( req, e, uri )
        if e.obj.respond_to? :matches
            include_matches, exclude_matches = e.obj.matches.partition { |k,v| v }.map do |matches|
                matches.map { |k,v| "<option>#{ k.inspect }</option>" }
            end
            content = %[
            <form action='#{ uri }' method='POST'>
            <p class="tiny">Detected MouseHole script: #{ e.script_path }</p>
            <div id="installer">
            <h1>#{ e.obj.name }</h1>
            <p>#{ e.obj.description }</p>
            <div class="matchset">
                <h2>Included pages</h2>
                <select class="matches" size="6">
                #{ include_matches * "\n" }
                </select>
            </div>
            <div class="matchset">
                <h2>Excluded pages</h2>
                <select class="matches" size="6">
                #{ exclude_matches * "\n" }
                </select>
            </div>
            <br clear="all" />
            <h2>View Source</h2>
            <textarea cols="20" rows="30">#{ WEBrick::HTMLUtils::escape e.code }</textarea>
            <input type="hidden" name="script_id" value="#{ e.script_id }" />
            <input type="button" name="dont_do_it" value="Cancel" onClick="history.back()" />
            <input type="submit" name="do_it" value="Install the Script" />
            </div></form>]
        else
            content = %[
            <p class="tiny">Invalid MouseHole script: #{ e.script_path }</p>
            <div id="installer">
            <p>The following script has been deemed invalid due to failure during
            the security and testing check.</p>
            <p>#{ e.obj.message } [<a href="javascript:void(0);" onClick="document.getElementById('backtrace').style.display='';">backtrace</a>]</p>
            <div id="backtrace" style="display:none;"><pre>#{ e.obj.backtrace }</pre></div>
            <h2>View Source</h2>
            <textarea cols="20" rows="30">#{ WEBrick::HTMLUtils::escape e.code }</textarea>
            <input type="button" name="dont_do_it" value="Cancel" onClick="history.back()" />
            </div>]
        end
        installer_html( req, "Install User Script: #{ e.script_path }?", content )
    end

    # Wrapper HTML for all configuration/installation pages.
    def installer_html( req, title, content )
        %[<html><head><title>#{ title }</title>
        <link href='/mouseHole/rss' title='RSS' rel='alternate' type='application/rss+xml' />
        <style type="text/css">
        body {
            color: #333;
            background: url(#{ home_uri req }images/mouseHole-tile.png);
            font: normal 11pt verdana, arial, sans-serif;
            padding: 20px 0px;
        }
        h1, h2, p { margin: 8px 0; padding: 0; }
        h1 { text-align: center; }
        p.tiny {
            color: #777;
            font: 9px;
            width: 540px;
            text-align: center;
            margin: 0 auto;
        }
        .matchset {
            float: left;
            width: 270px;
        }
        .matchset input {
            width: 80px;
            margin-right: 3px;
        }
        .quickactions {
            background-color: #ddd;
            padding: 4px 8px;
            font-size: 11px;
        }
        .quickactions ul {
            padding: 2px 0px 4px 0px;
            margin: 0;
        }
        .quickactions li {
            width: 240px;
            float: left;
        }
        .quickactions li.wide {
            width: 500px;
            float: none;
            clear: both;
        }
        select.matches {
            width: 260px;
        }
        #banner {
            text-align: center;
            margin-bottom: 8px;
        }
        #installer {
            background-color: #f7f7ff;
            border: solid 10px #111;
            width: 540px;
            margin: 0 auto;
            padding: 8px 10px;
        }
        textarea {
            font-size: 10px;
            width: 540px;
        }
        </style>
        <script language="Javascript">
        <!--
        var match_note = " You can specify multiple pages using the wildcard (*) character."

        function $(id) { return document.getElementById(id); }

        function prompt_edit_match(id) {
            var i = $(id).selectedIndex;
            if ( i < 0 ) { alert( "Please select an expression from the list" ); return; }
            var match = prompt("Modify the URL of the page below." + match_note, $(id).options[i].value);
            if (!match) return;
            sndReq('/mouseHole/' + id[0] + 'match/' + $('userb').value + '?remove=' + escape($(id).options[i].value) + "&match=" + escape(match), function(txt) {
                $(id).options[i] = new Option(match, match);
            });
        }

        function prompt_new_match(id) {
            var match = prompt("Enter a new URL below." + match_note, "http://foo.com/*");
            if (!match) return;
            var opts = document.getElementById(id).options
            sndReq('/mouseHole/' + id[0] + 'match/' + $('userb').value + '?match=' + escape(match), function(txt) {
                opts[opts.length] = new Option(match, match);
            });
        }

        function reset_config() {
            sndReq('/mouseHole/reset/' + $('userb').value, function(txt) {
                window.location = '/mouseHole/config/' + $('userb').value;
            });
        }

        function remove_a_match(id) {
            var i = $(id).selectedIndex;
            if ( i < 0 ) { alert( "Please select an expression from the list" ); return; }
            sndReq('/mouseHole/' + id[0] + 'match/' + $('userb').value + '?remove=' + escape($(id).options[i].value), function(txt) {
                $(id).options[i] = null;
            });
        }

        function createRequestObject() {
            var ro;
            var browser = navigator.appName;
            if(browser == "Microsoft Internet Explorer"){
                ro = new ActiveXObject("Microsoft.XMLHTTP");
            }else{
                ro = new XMLHttpRequest();
            }
            return ro;
        }

        var http = createRequestObject();

        function sndReq(action, handler) {
            http.open('get', action);
            http.onreadystatechange = function() {
                if(http.readyState == 4){
                    handler(http.responseText);
                }
            };
            http.send(null);
        }
        -->
        </script>
        <body>
        <div id="banner"><a href="#{ home_uri req }"><img src="#{ home_uri req }images/mouseHole-burn.gif" 
            border="0" /></a></div>
        #{ content }
        </body></html>]
    end

    # RSS starter method.
    def rss( io )
        feed = Builder::XmlMarkup.new( :target => io, :indent => 2 )
        feed.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
        feed.rss( 'xmlns:admin' => 'http://webns.net/mvcb/',
                  'xmlns:sy' => 'http://purl.org/rss/1.0/modules/syndication/',
                  'xmlns:dc' => 'http://purl.org/dc/elements/1.1/',
                  'xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
                  'version' => '2.0' ) do |rss|
            rss.channel do |c|
                # channel stuffs
                c.dc :language, "en-us" 
                c.dc :creator, "MouseHole #{ VERSION }"
                c.dc :date, Time.now.utc.strftime( "%Y-%m-%dT%H:%M:%S+00:00" )
                c.admin :generatorAgent, "rdf:resource" => "http://builder.rubyforge.org/"
                c.sy :updatePeriod, "hourly"
                c.sy :updateFrequency, 1
                yield c
            end
        end 
    end

    # The Evaluator class is used during the script security check.  Metadata about the
    # script is stored here.  Basically, we taint this object and run the code inside
    # +evaluate+ at a $SAFE level of 4.  Exceptions rise.
    class Evaluator
        attr_accessor :script_path, :script_id, :code, :obj
        def initialize( script_path, code )
            @script_path, @code = script_path, code
        end
        def evaluate
            if script_path =~ /\.user\.js$/
                @obj = StarmonkeyUserScript.new( code )
            else
                @obj = eval( code )
            end
        rescue Exception => e
            fake = Struct.new( :lineno, :message, :backtrace )
            ctx, lineno, func, message = "#{ e.backtrace[0] }:#{ e.message }".split( /\s*:\s*/, 4 )        
            message = "#{ e.class } on line #{ lineno }: `#{ message }'"
            @obj = fake.new( lineno, message, e.backtrace * "\n" )
        end
    end

    # The UserScript class is the basic unit of scripting.  Scripts can rewrite content coming
    # through the proxy or scripts can mount themselves as applications.
    class UserScript

        attr_accessor :document, :matches, :db, :request, :response, :mtime, :active, :install_uri, :token

        def initialize
            @token = WEBrick::Utils::random_string 32
        end
        def debug msg; Log.debug( msg ); end
        def name s = nil; s ? @name = s : @name; end
        def namespace s = nil; s ? @namespace = s : @namespace; end
        def description s = nil; s ? @description = s : @description; end
        def mount s = nil, &blk; s ? @mount = [s, blk] : @mount.to_a[0]; end
        def mount_proc; @mount[1] if @mount; end
        def rewrite &blk; @rewrite = blk; end
        def rewrite_proc; @rewrite; end
        def register_uri(r = "", &blk)
            self.registered_uris << [r, blk]
        end
        def reg( r = "" ); "/#{ @token }/#{ r }"; end
        def configure &blk; @configure = blk; end
        def configure_proc; @configure; end
        def version s = nil; s ? @version = s : @version; end

        def include_match r; r.strip! if r.respond_to? :strip!; self.matches[r] = true; end
        def exclude_match r; r.strip! if r.respond_to? :strip!; self.matches[r] = false; end
        def remove_match r; r.strip! if r.respond_to? :strip!; self.matches.reject! { |k,v| k == r }; end
        def match uri; self.matches.sort_by { |k,v| [v.to_s, k.to_s] }.reverse.
            inject(false){|s,(r,m)| match_uri(uri, r) ? m : s } end
        def matches; @matches ||= {}; end
        def registered_uris; @registered_uris ||= []; end

        def []( k ); @db[ k ]; end
        def []=( k, v ); @db[ k ] = v; end

        def do_configure( req, res )
            if configure_proc
                self.request, self.response = req, res
                configure_proc[ req, res ] 
            end
        end

        def do_rewrite( doc, req, res )
            if doc and rewrite_proc
                self.request, self.response, self.document = req, res, doc
                rewrite_proc[ req, res ]
            end
        end

        def registered_uri_fallback( script_uri, req, res )
            script_uri.instance_variables.each do |iv|
                v = script_uri.instance_variable_get( iv )
                req.request_uri.instance_variable_set( iv, v ) if v
            end
            false
        end

        def do_registered_uri( script_uri, req, res )
            registered_uris.find do |m, registered_proc|
                if match_uri(script_uri, m)
                    self.request, self.response = req, res
                    if registered_proc
                        registered_proc[script_uri, req, res]
                        return true
                    else
                        return registered_uri_fallback(script_uri, req, res)
                    end
                end
            end
            return false
        end

        def do_mount( path, req, res )
            self.request, self.response = req, res
            b = mount_proc[ path ]
            res.body = b if b
        end

        def read_xhtml_from( uri, full_doc = false )
            read_xhtml( open( uri ) { |f| f.read }, full_doc )
        end

        def match_uri( uri, r )
            if r.respond_to? :source
                uri.to_s.match r
            elsif r.respond_to? :to_str
                uri.to_s.match /^#{ r.to_str.gsub( '*', '.*' ) }/
            elsif r.respond_to? :keys
                !r.detect do |k, v|
                    !match_uri( uri.__send__( k ), v )
                end
            end
        end

        # deprecated stuff, remove in a few versions
        def install_url=( url ); @install_uri = url; end
    end

    class StarmonkeyUserScript < UserScript
        alias_method :include, :include_match
        alias_method :exclude, :exclude_match
        def initialize( src )
            super()
            # yank manifest
            @src = starmonkey_wrap( src.gsub( %r!//\s+==UserScript==(.+)//\s+==/UserScript==!m ) do
                manifest = $1
                manifest.scan( %r!^//\s+@(\w+)\s+(.*)$! ) do |k, v|
                    method( k ).call( v )
                end
                nil
            end )
            register_uri do
                response['content-type'] = 'text/javascript'
                response.body = @src
            end
            rewrite do
                inject_script
            end
        end

        def inject_script
            body = document.elements['//body']
            body ||= document.elements['/html']
            return unless body

            script = REXML::Element.new 'script'
            script.attributes['type'] = 'text/javascript'
            script.attributes['src'] = reg

            body.add script
        end

        # Lovingly wraps a greasemonkey script in starmonkey proper
        def starmonkey_wrap( content )
                     <<-EOJS.gsub( /^ {12}/, '' )
            (function() {
            
            // Starmonkey: an implementation of the greasemonkey APIs for mouseHole
            
            function starmonkey_API_URI(path) {
                var request_uri = "http://" + window.location.host;
                if ( window.location.port != 80 ) {
                    request_uri = request_uri + ":" + window.location.port;
                }
                request_uri = request_uri + "/#{ @token }/" + path;
            
                if ( argments.length > 1 ) {
                    var parameters = arguments[1];
                    var sep = "?";
                    for (var name in parameters) {
                        request_uri = request_uri + sep + encode(name) + "=" + encode(parameters[name]);
                        sep = "&";
                    }
                }
            
                return request_uri;
            }
            
            function GM_registerMenuCommand() {
            // Worth implementing?  How?
                alert('GM_registerMenuCommand is not implemented in starmonkey');
            }
            
            function GM_xmlhttpRequest(details) {
            }
            
            function GM_setValue(name, value) {
                starmonkey_API('setValue', name, value);
            }
            
            function GM_getValue(name, defawlt) {
                starmonkey_API('getValue', name, defawlt);
            }
            
            function GM_log(message) {
                var parameters = { 'message': message };
                if ( arguments.length > 1 ) {
                    parameters['level'] = arguments[1];
                }
                starmonkey_API('log', parameters);
            }
            
            #{ content }
            
            })();
            EOJS
        end
    end

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
        @@mouselog = Logger.new( File.join( MH, "mouse.log"  ) )
        @@mouselog.level = Logger::DEBUG
        @@conf = {}

        def self.conf=( conf )
            @@conf = conf
        end

        def self.method_missing( meth , *args )
            @@mouselog.send( meth , *args ) if @@conf[:logs_on]
        end
    end

    # Log messages, unless.
    def debug( msg )
        Log.debug( msg )
    end

    # Handles requests to the various mounts.  Also ripped from Catapult.
    def scripted_mounts( request, response )
        # return not_allowed( request, response ) unless  MouseHole.allow_from? request.peeraddr[2].strip 
        each_fresh_script do |path, script|
            hostmap = {script.mount.to_s => "mh", "mouse.#{ script.mount }" => "mouse.hole"}
            if hostmap.has_key? request.request_uri.host
                response['location'] = "http://#{ hostmap[ request.request_uri.host ] }/#{ script.mount }#{ request.request_uri.path }"
                raise WEBrick::HTTPStatus::Found
            end
        end
        unless request.path_info.to_s.size > 1 
            mousehole_home( request, response ) 
            no_cache response
            return
        end
        raise WEBrick::HTTPStatus::NotFound, "Mounts turned off." unless @conf[:mounts_on]
     
        obj = nil
        debug( "MouseHole#process_request has  path_info #{request.path_info}" )
        path_parts = request.path_info.split( '/' ).reject { |x| x.to_s.strip.size == 0 }
        mount = path_parts.shift.to_s.strip
        STDERR.puts( "Get mount '#{mount}'")
        each_fresh_script do |path, script|
            if mount =~ /^\/*#{ script.mount }$/
                script.do_mount( path_parts.join( '/' ), request, response )
                return
            end
        end
        raise WEBrick::HTTPStatus::NotFound, "No mouseHole script answered for `#{ mount }'"
    end

    class UserScript
        # Search for libtidy
        libtidy = nil
        libdirs = ['/usr/lib', '/usr/local/lib'] + $:
        libdirs << File.dirname( RUBYSCRIPT2EXE_APPEXE ) if defined? RUBYSCRIPT2EXE_APPEXE
        libdirs.each do |libdir|
            libtidies = ['so']
            libtidies.unshift 'dll' if Config::CONFIG['arch'] =~ /win32/
            libtidies.unshift 'dylib' if Config::CONFIG['arch'] =~ /darwin/
            libtidies.collect! { |lib| File.join( libdir, "libtidy.#{lib}") }
            if libtidy = libtidies.find { |lib| File.exists? lib } 
                puts "Found Tidy! #{ libtidy }"
                require 'tidy'
                require 'htree/htmlinfo'
                Tidy.path = libtidy
                def xhtmlize html, full_doc = false
                    Tidy.open :output_xhtml => true, :char_encoding => 'raw', :show_body_only => !full_doc do |tidy|
                        tidy.clean( html )
                    end
                end
                def read_xhtml html, full_doc = false
                    REXML::Document.new( xhtmlize( html, full_doc ) )
                end
                break
            end
            libtidy = nil
        end

        unless libtidy
            puts "No Tidy found."
            require 'htree'
            def xhtmlize html, full_doc = false
               out = ""
               HTree( html ).display_xml( out )
               out
            end
            def read_xhtml html, full_doc = false
                HTree.parse( html ).each_child do |child|
                    if child.respond_to? :qualified_name
                        if child.qualified_name == 'html'
                            return HTree::Doc.new( child ).to_rexml
                        end
                    end
                end
            end
        end
    end
end
