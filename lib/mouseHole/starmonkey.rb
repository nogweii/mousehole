require 'mouseHole/userscript'

module MouseHole
# StarmonkeyUserScript gives basic Greasemonkey support.
class StarmonkeyUserScript < UserScript
    alias_method :include, :include_match
    alias_method :exclude, :exclude_match
    def initialize( src )
        super()
        # yank manifest
        @src_orig = src.gsub( %r!//\s*==\s*UserScript\s*==(.+)//\s*==\s*/UserScript\s*==!m ) do
            manifest = $1
            manifest.scan( %r!^//\s*@(\w+)\s+(.*)$! ) do |k, v|
                method( k ).call( v )
            end
            nil
        end
        register_uri "starmonkey.js" do
            response['content-type'] = 'text/javascript'
            response.body = @src
        end
        register_uri "http://*" do |(uri,)|
            uri.query = request.query_string
            uri.open do |f|
                f.meta.each do |k, v|
                    response[k] = v
                end
                response.body = f.read
            end
        end
        register_uri "fin" do
            @token = WEBrick::Utils::random_string 32
        end
        rewrite do
            inject_script
        end
    end

    def inject_script
        @token = WEBrick::Utils::random_string 32
        @src = starmonkey_wrap( @src_orig )
        body = document.elements['//body']
        body ||= document.elements['//html']
        return unless body

        script = REXML::Element.new 'script'
        script.attributes['type'] = 'text/javascript'
        script.attributes['src'] = reg( "starmonkey.js" )

        body.add script
    end

    # Lovingly wraps a greasemonkey script in starmonkey proper
    def starmonkey_wrap( content )
                 <<-EOJS.gsub( /^ {12}/, '' )
        (function() {
        
        function GM_registerMenuCommand() {
        // Worth implementing?  How?
        }
        
        function GM_xmlhttpRequest(details) {
            var xhr;
            var xmlhttp = [function() {return new ActiveXObject('Msxml2.XMLHTTP')},
                           function() {return new ActiveXObject('Microsoft.XMLHTTP')},
                           function() {return new XMLHttpRequest()}];

            for (var i = 0; i < xmlhttp.length; i++) {
                try { xhr = xmlhttp[i](); break; } catch (e) {}
            }
            xhr.open( details['method'] || 'GET', "/#{ @token }/" + details['url'], true );
            for (var headKey in (details['headers'] || {})) {
                xhr.setRequestHeader( headerKey, details['headers'][headerKey] );
            }
            xhr.onreadystatechange = function () {
                var funcs = [];
                if (details['onreadystatechange']) funcs[funcs.length] = details['onreadystatechange'];
                if (xhr.readyState == 4) {
                    if (xhr.status == 200 && details['onload']) {
                        funcs[funcs.length] = details['onload'];
                    } else if (details['onerror']) {
                        funcs[funcs.length] = details['onerror'];
                    }
                }
                for (var i = 0; i < funcs.length; i++ ) {
                    funcs[i]({status: xhr.status, statusText: xhr.statusText, 
                        responseHeaders: xhr.getAllResponseHeaders(), responseText: xhr.responseText, 
                        readyState: xhr.readyState });
                }
            }
            xhr.send( details['method'] == 'post' ? details['body'] : null );
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
        
        // expire the token!!
        // GM_xmlhttpRequest({url: "#{ reg 'fin' }"});

        GM_registerMenuCommand = null;
        GM_xmlhttpRequest = null;
        GM_log = null;
        GM_getValue = null;
        GM_setValue = null;

        })();
        EOJS
    end
end
end
