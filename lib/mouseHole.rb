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
        @temp_scripts, @user_scripts = {}, {}
        @user_data_dir, @user_script_dir = File.join( MH, 'data' ), File.join( MH, 'userScripts' )
        File.makedirs( @user_script_dir )
        File.makedirs( @user_data_dir )
        @db = YAML::DBM.open( File.join( @user_data_dir, 'mouseHole' ) )
        @conf = @db['conf'] || {:rewrites_on => true, :mounts_on => true, :logs_on => false}
        Dir["#{ @user_script_dir }/*.user.rb"].each do |userb|
            userb = File.basename userb
            load_user_script userb
        end

        debug( "MouseHole proxy config: #{ config.inspect }" )
    end

    # Loops through scripts, ensuring freshness, reloading as needed
    def each_fresh_script( which = :active )
        scripts = @user_scripts
        if which == :all
            scripts = scripts.to_a + Dir["#{ @user_script_dir }/*.user.rb"].map do |path| 
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
                active = script.respond_to?(:active) and script.active
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
            script = eval( File.read( fullpath ) )
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

    # Removes cache headers from HTTPResponse +res+.
    def no_cache( res )
        res['etag'] = nil
        res['expires'] = nil
        res['cache-control'] = 'no-cache'
        res['pragma'] = 'no-cache'
    end

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
        req.header['accept-encoding'] = ['gzip','deflate']
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
        if res.status == 200 and not is_mousehole? req
            if req.request_uri.path =~ /\.user\.rb$/
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
                end
                res.body = installer_pane( req, evaluator, "#{ home_url req }mouseHole/install" )
                res['content-type'] = 'text/html'
                res['content-length'] = res.body.length
                no_cache res
                res.setup_header
            elsif @conf[:rewrites_on]
                case res.content_type
                when /^text\/html/, /^application\/xhtml+xml/
                    doc = nil
                    each_fresh_script do |path, script|
                        next unless script.match req.request_uri
                        unless doc
                            decode(res)
                            doc = script.read_xhtml( res.body, true )
                            res.body = ""
                        end
                        script.document = doc
                        script.execute( req, res )
                    end
                    if doc
                        doc.write( res.body = "" )
                        res['content-length'] = res.body.length
                        no_cache res
                    end
                end
            end
        end
    end

    # MouseHole's own top URL.
    def home_url( req ); is_mousehole?( req ) ? "/" : "http://#{ @config[:BindAddress] }:#{ @config[:Port ] }/"; end

    # The home page, primary configuration.
    def mousehole_home( req, res )
        title = "Welcome to MouseHole v#{ VERSION }"
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
                ctx, lineno, func, message = script.message.split( /\s*:\s*/, 4 )        
                if message =~ /\(eval\):(\d+):\s+(.+)$/
                    lineno, message = $1, $2
                end
                content += %{<li><input type="checkbox" name="#{ File.basename path }/toggle" disabled="true" />
                    <h4>#{ path }</h4>
                    <p class="details">Script failed due to #{ script.class } on line #{ lineno }: `#{ message }'</p></li>}
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
    def regexp( val )
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
                script.remove_match( regexp( req.query['remove'] ) )
            end
            if req.query['match'] 
                if inc
                    script.include_match( regexp( req.query['match'] ) )
                else
                    script.exclude_match( regexp( req.query['match'] ) )
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

    # Script configuration page.
    def server_config( args, req, res )
        userb = args.first
        script = @user_scripts[userb]
        if script and script.respond_to? :matches
            title = script.name
            include_matches, exclude_matches = script.matches.partition { |k,v| v }.map do |matches|
                matches.map { |k,v| "<option>#{ k.respond_to?( :to_str ) ? k.to_str : k.inspect }</option>" }
            end
            install_url = %{<p>Installed from: <a href="#{ script.install_url }">#{ script.install_url }</a></p>} if script.install_url
            script_config = script.configure_proc[ req, res ] if script.configure_proc
            content = %{
                <form method="POST">
                <input type="hidden" id="userb" value="#{ userb }" />
                <div id="installer">
                <h1>#{ script.name }</h1>
                <p>#{ script.description }</p>#{ install_url }#{ script_config }
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
            temp, install_url, path = @temp_scripts[userb]

            scriptset = ( @db["script:#{ path }"] || {} )
            scriptset[:install_url] = install_url
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
    def installer_pane( req, e, url )
        if e.obj.respond_to? :matches
            include_matches, exclude_matches = e.obj.matches.partition { |k,v| v }.map do |matches|
                matches.map { |k,v| "<option>#{ k.inspect }</option>" }
            end
            content = %[
            <form action='#{ url }' method='POST'>
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
            <p>#{ e.obj.message }</p>
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
            background-color: #ddd;
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
            padding: 4px;
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
            border: solid 4px #333;
            width: 540px;
            margin: 0 auto;
            padding: 4px 10px;
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
        <div id="banner"><a href="#{ home_url req }"><img src="#{ home_url req }images/mouseHole-neon.png" 
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
            @obj = eval( code )
        rescue Exception => e
            fake = Struct.new( :lineno, :message )
            ctx, lineno, func, message = e.message.split( /\s*:\s*/, 4 )        
            message = "#{ e.class } on line #{ lineno }: `#{ message }'"
            @obj = fake.new( lineno, message )
        end
    end

    # The UserScript class is the basic unit of scripting.  Scripts can rewrite content coming
    # through the proxy or scripts can mount themselves as applications.
    class UserScript

        attr_accessor :document, :matches, :db, :request, :response, :mtime, :active, :install_url

        def name s = nil; s ? @name = s : @name; end
        def namespace s = nil; s ? @namespace = s : @namespace; end
        def description s = nil; s ? @description = s : @description; end
        def mount s = nil, &blk; s ? @mount = [s, blk] : @mount.to_a[0]; end
        def mount_proc; @mount[1] if @mount; end
        def rewrite &blk; @rewrite = blk; end
        def rewrite_proc; @rewrite; end
        def configure &blk; @configure = blk; end
        def configure_proc; @configure; end
        def version s = nil; s ? @version = s : @version; end
        def include_match r; self.matches[r] = true; end
        def exclude_match r; self.matches[r] = false; end
        def remove_match r; self.matches.delete r; end
        def match uri; self.matches.sort_by { |k,v| [v.to_s, k.to_s] }.reverse.
            inject(false){|s,(r,m)| uri.to_s.match(r) ? m : s } end
        def matches; @matches ||= {}; end

        def []( k ); @db[ k ]; end
        def []=( k, v ); @db[ k ] = v; end
        def execute( req, res )
            return unless rewrite_proc
            rewrite_proc[ req, res ]
        end

        def read_xhtml_from( uri, full_doc = false )
            read_xhtml( open( uri ) { |f| f.read }, full_doc )
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

        def self.method_missing( meth , *args )
            @@mouselog.send( meth , *args )
        end
    end

    # Log messages, unless.
    def debug( msg )
        Log.debug( msg ) if @conf[:logs_on]
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
            obj = script if mount =~ /^\/*#{ script.mount }$/
        end
        if obj
            obj.request, obj.response = request, response
            b = obj.mount_proc[ path_parts.join( '/' ) ]
            response.body = b if b
        end
        raise WEBrick::HTTPStatus::NotFound, "No mouseHole script answered for `#{ mount }'" unless obj
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
                    Tidy.open :output_xhtml => true, :show_body_only => !full_doc do |tidy|
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
