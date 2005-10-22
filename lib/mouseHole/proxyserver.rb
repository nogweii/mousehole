require 'net/httpio'

module MouseHole
class CancelRewrite < StandardError; end
# ProxyServer stuff
def self.ProxyServer( base_proxy )
    Class.new( base_proxy ) do

        attr_accessor :user_scripts, :temp_scripts

        def initialize(options, *args)
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

            # add MouseHole hosts entries
            HOSTS['mouse.hole'] = "#{ options.host }:#{ options.port }"
            HOSTS['mh']         = "#{ options.host }:#{ options.port }"

            # user-specific directories and utilities
            @mousehole_utils = make_utility_mixin options
            @etags, @temp_scripts, @user_scripts = {}, {}, {}
            @user_data_dir, @user_script_dir, @user_temp_dir = 
                File.join( options.mouse_dir, 'data' ), 
                File.join( options.mouse_dir, 'userScripts' ),
                File.join( options.mouse_dir, 'temp' )
            File.makedirs( @user_script_dir )
            File.makedirs( @user_data_dir )
            @started = Time.now

            # connect to the database, get some data
            @driver = MouseHole::Databases.open( options.db_driver, 
                    options.database || {'path' => @user_data_dir} )
            @db = @driver.open_table( 'mouseHole' )
            load_conf

            # read user scripts on startup
            Dir["#{ @user_script_dir }/*.user.{rb,js}"].each do |userb|
                userb = File.basename userb
                load_user_script userb
            end
        end
        
        def load_conf
            # initialize the basic settings
            @conf = @db['conf'] || {:rewrites_on => true, :mounts_on => true, :logs_on => false}
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
                        @logger.debug( "Reloading #{ path }, as it has changed." )
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
                script.mousehole_uri = home_uri
                script.logger = @logger
                script.db = @driver.open_table( userb )
                script.mtime = File.mtime( fullpath )
                script.active = true
                ( @db["script:#{ userb }"] || {} ).each do |k,v|
                    script.method( "#{ k }=" ).call( v )
                end
                script.extend @mousehole_utils
                if script.mount
                    MouseHole::HOSTS[script.mount.to_s] = "#{ config[:ServerName] }:#{ config[:Port] }"
                    MouseHole::HOSTS["mouse.#{ script.mount }"] = "#{ config[:ServerName] }:#{ config[:Port] }"
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

        # MrCode's gzip decoding from WonderLand!  Also reads in remainder of the body from the
        # stream.
        def decode(res)
            body = ''
            while str = res.body.read; body += str; end
            res.body.close
            res.body = body
            res['content-length'] = res.body.length

            case res['content-encoding']
            when 'gzip':
                gzr = Zlib::GzipReader.new(StringIO.new(res.body))
                res.body = gzr.read
                gzr.close
                res['content-encoding'] = nil
                res['content-length'] = res.body.length        
            when 'deflate':
                res.body = Zlib::Inflate.inflate(res.body)
                res['content-encoding'] = nil
                res['content-length'] = res.body.length        
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
            return false unless req.respond_to?( :host )
            if MouseHole::HOSTS.has_key?( req.host )
                host, port = MouseHole::HOSTS[ req.host ].split ':'
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
                        evaluator.script_id = File.join( @user_temp_dir, scrip )
                        File.open( evaluator.script_id, 'w' ) do |t|
                            t << evaluator.code
                        end
                        @temp_scripts[evaluator.script_id] = [req.request_uri.to_s, scrip]
                        Thread.start( evaluator ) do |e|
                            e.taint
                            $SAFE = 4
                            e.evaluate
                        end.join
                        res.body = installer_pane( req, evaluator, "#{ home_uri req }mouseHole/install" )
                        res['content-type'] = 'text/html'
                        res['content-length'] = res.body.length
                    end
                elsif @conf[:rewrites_on] and res['content-type']
                    converter = Converters.detect_by_mime_type res['content-type'].split(';',2)[0]
                    if converter
                        check_cache res
                        if res.status == 200
                            doc = nil
                            rewritten = false
                            each_fresh_script do |path, script|
                                next unless script.match( req.request_uri, converter )
                                unless doc
                                    decode( res )
                                    doc = converter.parse( script, req, res )
                                end
                                break unless doc
                                begin
                                    script.do_rewrite( converter, doc, req, res )
                                    rewritten = true
                                rescue CancelRewrite
                                end
                            end
                            if rewritten
                                converter.output( doc, res )
                                res['content-length'] = res.body.length
                            end
                        end
                    end
                end
            end
        end

        # MouseHole's own top URL.
        def home_uri( req = nil ); is_mousehole?( req ) ? "/" : "http://#{ @config[:BindAddress] }:#{ @config[:Port ] }/"; end

        # The home page, primary configuration.
        def mousehole_home( req, res )
            title = "MouseHole"
            content = %{
                <style type="text/css">
                    .details { font-size: 12px; clear: both; margin: 12px 8px; }
                    .mount, h4 { float: left; font-size: 15px; margin: 9px 8px 0px 8px; }
                    h4 { margin: 6px 0; font-size: 18px; font-weight: normal; }
                    li { list-style: none; }
                    #scripts li input { float: left; margin: 10px 8px 3px 8px; }
                </style>
                <div id="installer">
                    <div class="quickactions">
                    <ul>
                    <li><input type="checkbox" name="rewrites" onClick="sndReq('/mouseHole/toggle_rewrites')"
                        #{ 'checked' if @conf[:rewrites_on] } /> Script rewriting on?</li>
                    <li><input type="checkbox" name="mounts" onClick="sndReq('/mouseHole/toggle_mounts')"
                        #{ 'checked' if @conf[:mounts_on] } /> Script mounts on?</li>
                    <li class="wide"><input type="checkbox" name="logs" onClick="sndReq('/mouseHole/toggle_logs')"
                        #{ 'checked' if @conf[:logs_on] } /> Log debug messages to mouse.log?</li></ul>
                    </div>
                    <h1>Scripts Installed</h1>
                    <p>The following scripts are installed on your mouseHole.  Check marks indicate
                    that the script is active.  You may toggle it on or off.  Click on the script's
                    name to configure it.</p>
                    <div id="scripts"><ul>}
                script_count = 0
            each_fresh_script :all do |path, script|
                mounted = nil
                if script.respond_to? :mount
                    if script.mount
                        mounted = %{<p class="mount">[<a href="/#{ script.mount }">/#{ script.mount }</a>]</p>}
                    end
                    content += %{<li><input type="checkbox" name="#{ File.basename path }/toggle"
                        onClick="sndReq('/mouseHole/toggle/#{ File.basename path }')"
                        #{ 'checked' if script.active } />
                        <h4><a href="/mouseHole/config/#{ File.basename path }">#{ script.name }</a></h4>
                        #{ mounted }<p class="details">#{ script.description }</p></li>}
                else
                    ctx, lineno, func, message = script.message.split( /\s*:\s*/, 4 )        
                    unless message
                        ctx, lineno, func, message = "#{ script.backtrace[1] }:#{ script.message }".split( /\s*:\s*/, 4 )        
                    end
                    if ctx == "(eval)"
                        ctx = nil
                    end
                    content += %{<li><input type="checkbox" name="#{ File.basename path }/toggle" disabled="true" />
                        <h4>#{ path }</h4>
                        <p class="details">Script failed 
                        #{ "due to <b>#{ script.class }</b>" unless script.class == Exception } on line 
                        <b>#{ lineno }</b>#{ " in file <b>#{ ctx }</b>" if ctx }: <u>#{ WEBrick::HTMLUtils::escape message }</u></p></li>}
                end
                script_count += 1
            end
            content += %{<li>
                    <p>#{ script_count.zero? ? "No" : script_count } user scripts installed.  More
                    scripts can be found on the <a href="http://mousehole.rubyforge.org/wiki/wiki.pl?UserScripts">user scripts list</a>.</p>
                    </li>
                    </ul></div>
                    <div class="quickactions">
                    <a class="syndicate" title="RSS 2.0" href="/mouseHole/rss"><span>RSS</span></a>
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
                    <pre style="font-size: 10px;">#{ db.inject( {} ) { |hsh,(k,v)| hsh[k] = v; hsh }.to_yaml }</pre>]
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
        def server_match( args, req, res )
            userb = args.first
            if ( script = @user_scripts[userb] ) and script.respond_to? :matches
                if req.query['remove'] 
                    script.remove_match( req.query['remove'].to_i )
                end
                if req.query['include_match']
                    script.include_match( build_match( req.query['include_match'] ) )
                end
                if req.query['exclude_match'] 
                    script.exclude_match( build_match( req.query['exclude_match'] ) )
                end
                if req.query['match'] 
                    script.matches[req.query['at'].to_i][0] = build_match( req.query['match'] )
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
                @db["script:#{ userb }"] = {:install_uri => @user_scripts[userb].install_uri}
                load_user_script userb
            end
        end

        # Uninstall script.
        def server_uninstall( args, req, res )
            userb = args.first
            if @user_scripts[userb] and @user_scripts[userb].respond_to? :active
                @user_scripts.delete userb
                File.delete File.join( @user_script_dir, userb )
                @db.delete "script:#{ userb }"
            end
        end

        # Script configuration page.
        def server_config( args, req, res )
            userb = args.first
            script = @user_scripts[userb]
            if script and script.respond_to? :matches
                title = script.name
                all_matches = script.matches.map { |k,v| "<option>#{ v ? "include" : "exclude" }: #{ k.respond_to?( :to_str ) ? k.to_str : ( k.respond_to?( :source ) ? k.inspect : k.to_json ) }</option>" }
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
                        <h2>URL Matching Rules</h2>
                        <select class="matches" id="all_matches" size="6">
                        #{ all_matches * "\n" }
                        </select>
                        <input type="button" name="add" value="Include..." onClick="prompt_new_match('all_matches', 'include')" />
                        <input type="button" name="add" value="Exclude..." onClick="prompt_new_match('all_matches', 'exclude')" />
                        <input type="button" name="edit" value="Edit..." onClick="prompt_edit_match('all_matches')" />
                        <input type="button" name="remove" value="Remove" onClick="remove_a_match('all_matches')" />
                    </div>
                    <br clear="all" />
                    <p><input type="button" name="reset" value="Reset to Defaults" onClick="if ( confirm( 'Would you really like to reset the script configuration?' ) ) { reset_config(); }" />
                       <input type="button" name="uninstall" value="Uninstall" onClick="if ( confirm( 'Would you really like to uninstall #{ userb }?' ) ) { uninstall_script(); }" />
                    </p>
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
                install_uri, path = @temp_scripts[userb]

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
                    <p><strong>Return to the previous page and hit refresh.  Then, try installing again.</strong></p>
                    </div>}
                res.body = installer_html( req, title, content ) 
            end
        end

        # Script installation page.
        def installer_pane( req, e, uri )
            if e.obj.respond_to? :matches
                all_matches = e.obj.matches.map { |k,v| "<option>#{ v ? "include" : "exclude" }: #{ k.respond_to?( :to_str ) ? k.to_str : ( k.respond_to?( :source ) ? k.inspect : k.to_json ) }</option>" }
                content = %[
                <form action='#{ uri }' method='POST'>
                <p class="tiny">Detected MouseHole script: #{ e.script_path }</p>
                <div id="installer">
                <h1>#{ e.obj.name }</h1>
                <p>#{ e.obj.description }</p>
                <div class="matchset">
                    <h2>URL Matching Rules</h2>
                    <select class="matches" size="6">
                    #{ all_matches * "\n" }
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
                background: url(#{ home_uri req }images/mouseHole-stripe.png);
                font: normal 11pt verdana, arial, sans-serif;
                padding: 20px 0px;
            }
            h1, h2, p { margin: 8px 0; padding: 0; }
            h1 { text-align: center; }
            p.tiny {
                color: #000;
                font: 9px;
                width: 540px;
                text-align: center;
                margin: 0 auto;
            }
            a.syndicate {
                float: right;
                border: #666 1px solid;
                margin: 4px;
                text-decoration:none;
            }
            a.syndicate span {
                display: block;
                border: #ddd 1px solid;
                padding: 1px 3px;
                font:bold 10px verdana,sans-serif;
                color: #f1f1f7;
                background: #5AD;
                text-decoration:none;
                margin:0;
            }
            .matchset {
                float: left;
                width: 540px;
            }
            .matchset input {
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
                width: 520px;
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
                var match = $(id).options[i].text.match( /(.*): (.*)/ );
                match[2] = prompt("Modify the URL of the page below." + match_note, match[2] );
                if (!match[2]) return;
                sndReq('/mouseHole/match/' + $('userb').value + '?at=' + i + "&match=" + escape(match[2]), function(txt) {
                    $(id).options[i] = new Option(match[1] + ": " + match[2]);
                });
            }

            function prompt_new_match(id, prefix) {
                var match = prompt("Enter a new URL below." + match_note, "http://foo.com/*");
                if (!match) return;
                var opts = document.getElementById(id).options
                sndReq('/mouseHole/match/' + $('userb').value + '?' + prefix + '_match=' + escape(match), function(txt) {
                    opts[opts.length] = new Option(prefix + ": " + match);
                });
            }

            function reset_config() {
                sndReq('/mouseHole/reset/' + $('userb').value, function(txt) {
                    window.location = '/mouseHole/config/' + $('userb').value;
                });
            }

            function uninstall_script() {
                sndReq('/mouseHole/uninstall/' + $('userb').value, function(txt) {
                    window.location = '/';
                });
            }

            function remove_a_match(id) {
                var i = $(id).selectedIndex;
                if ( i < 0 ) { alert( "Please select an expression from the list" ); return; }
                sndReq('/mouseHole/match/' + $('userb').value + '?remove=' + i, function(txt) {
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

        # Handles requests to the various mounts.  Also ripped from Catapult.
        def scripted_mounts( request, response )
            # return not_allowed( request, response ) unless  MouseHole.allow_from? request.peeraddr[2].strip 
            each_fresh_script do |path, script|
                hostmap = {script.mount.to_s => "mh", "mouse.#{ script.mount }" => "mouse.hole"}
                if hostmap.has_key? request.request_uri.host
                    response['location'] = "http://#{ hostmap[ request.request_uri.host ] }/#{ script.mount }#{ request.request_uri.path }"
                    raise WEBrick::HTTPStatus::Found
                end
                if request.request_uri.path =~ %r!^/#{ script.token }/!
                    rewrote = script.do_registered_uri( URI($'), request, response )
                    return
                end
            end
            unless request.path_info.to_s.size > 1 
                mousehole_home( request, response ) 
                no_cache response
                return
            end
            raise WEBrick::HTTPStatus::NotFound, "Mounts turned off." unless @conf[:mounts_on]
         
            obj = nil
            @logger.debug( "MouseHole::ProxyServer#process_request has  path_info #{request.path_info}" )
            path_parts = request.path_info.split( '/' ).reject { |x| x.to_s.strip.size == 0 }
            mount = path_parts.shift.to_s.strip
            each_fresh_script do |path, script|
                if mount =~ /^\/*#{ script.mount }$/
                    script.do_mount( path_parts.join( '/' ), request, response )
                    no_cache response
                    return
                end
            end
            raise WEBrick::HTTPStatus::NotFound, "No mouseHole script answered for `#{ mount }'"
        end

        def make_utility_mixin( options )
            logger = @logger
            @mousehole_utils = Module.new do
                libtidy = nil
                if options.tidy
                    # Search for libtidy
                    libdirs = ['/usr/lib', '/usr/local/lib'] + $:
                    libdirs << File.dirname( RUBYSCRIPT2EXE_APPEXE ) if defined? RUBYSCRIPT2EXE_APPEXE
                    libdirs.each do |libdir|
                        libtidies = ['so']
                        libtidies.unshift 'dll' if Config::CONFIG['arch'] =~ /win32/
                        libtidies.unshift 'dylib' if Config::CONFIG['arch'] =~ /darwin/
                        libtidies.collect! { |lib| File.join( libdir, "libtidy.#{lib}") }
                        if libtidy = libtidies.find { |lib| File.exists? lib } 
                            logger.debug "Found Tidy! #{ libtidy }"
                            require 'tidy'
                            require 'htree/htmlinfo'
                            Tidy.path = libtidy
                            def xhtmlize html, full_doc = false, charset = nil
                                if charset =~ /utf-?8/i
                                    charset = 'utf8'
                                else
                                    charset = 'raw'
                                end
                                Tidy.open :output_xhtml => true, 
                                          :char_encoding => charset, 
                                          :show_body_only => !full_doc do |tidy|
                                    tidy.clean( html )
                                end
                            end
                            def read_xhtml html, *args
                                REXML::Document.new( xhtmlize( html, *args ) )
                            end
                            break
                        end
                        libtidy = nil
                    end
                end

                unless libtidy
                    logger.debug "No Tidy found."
                    require 'htree'
                    def xhtmlize html, full_doc = false, charset = nil
                       out = ""
                       HTree( html ).display_xml( out )
                       out
                    end
                    def read_xhtml html, *args
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

        # Don't start reading the body, just pull headers!
        def proxy_service(req, res)
            # Proxy Authentication
            proxy_auth(req, res)      

            # Create Request-URI to send to the origin server
            uri  = req.request_uri
            path = uri.path.dup
            path << "?" << uri.query if uri.query

            # Choose header fields to transfer
            header = Hash.new
            choose_header(req, header)
            set_via(header)

            # select upstream proxy server
            if proxy = proxy_uri(req, res)
                proxy_host = proxy.host
                proxy_port = proxy.port
                if proxy.userinfo
                    credentials = "Basic " + [proxy.userinfo].pack("m*")
                    credentials.chomp!
                    header['proxy-authorization'] = credentials
                end
            end

            # Check our internal HOSTS registry
            if defined? MouseHole::HOSTS and MouseHole::HOSTS.has_key? req.request_uri.host
                ip, port = MouseHole::HOSTS[req.request_uri.host].split(/:/)
                req.request_uri.host = ip
                req.request_uri.port = port.to_i if port
            end

            response = nil
            begin
              http = Net::HTTPIO.new(uri.host, uri.port, proxy_host, proxy_port)
              if @config[:ProxyTimeout]
                  ##################################   these issues are 
                  http.open_timeout = 30   # secs  #   necessary (maybe bacause
                  http.read_timeout = 60   # secs  #   Ruby's bug, but why?)
                  ##################################
              end
              response =
                  case req.request_method
                  when "GET"  then http.request_get(path, header)
                  when "POST" then http.request_post(path, req.body || "", header)
                  when "HEAD" then http.request_head(path, header)
                  else
                    raise WEBrick::HTTPStatus::MethodNotAllowed,
                      "unsupported method `#{req.request_method}'."
                  end
            rescue => err
                @logger.debug("#{err.class}: #{err.message}")
                raise WEBrick::HTTPStatus::ServiceUnavailable, err.message
            end
      
            # Convert Net::HTTP::HTTPResponse to WEBrick::HTTPProxy
            res.status = response.code.to_i
            choose_header(response, res)
            set_cookie(response, res)
            set_via(res)
            res.body = response
            def res.send_body(socket)
              if @body.respond_to?(:read) and @body.respond_to?(:size)
                  send_body_io(socket)
              else 
                  send_body_string(socket)
              end
            end


            # Process contents
            if handler = @config[:ProxyContentHandler]
                handler.call(req, res)
            end
        end
    end
end
end
