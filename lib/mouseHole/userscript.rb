module MouseHole
# The UserScript class is the basic unit of scripting.  Scripts can rewrite content coming
# through the proxy or scripts can mount themselves as applications.
class UserScript

    attr_accessor :document, :matches, :db, :request, :response, :mtime, :active, 
        :install_uri, :token, :mousehole_uri, :registered_uris, :logger

    def initialize
        @token = WEBrick::Utils::random_string 32
        @matches, @registered_uris, @rewrites = [], [], {}
    end
    def debug msg; @logger.debug( msg ); end
    def name s = nil; s ? @name = s : @name; end
    def namespace s = nil; s ? @namespace = s : @namespace; end
    def description s = nil; s ? @description = s : @description; end
    def mount s = nil, &blk; s ? @mount = [s, blk] : @mount.to_a[0]; end
    def mount_proc; @mount[1] if @mount; end
    def rewrite *content_types, &blk
        content_types << MouseHole::Converters::HTML if content_types.empty?
        content_types.each do |ct|
            @rewrites[ct] = blk
        end
    end
    def register_uri(r = "", &blk)
        self.registered_uris << [r, blk]
    end
    def unregister_uri(r = "")
        self.registered_uris.delete_if { |uridef| uridef[0] == r }
    end
    def reg( r = "" ); "/#{ @token }/#{ r }" end
    def configure &blk; @configure = blk end
    def configure_proc; @configure end
    def version s = nil; s ? @version = s : @version end

    def include_match r, i = nil; add_match r, true, i end
    def exclude_match r, i = nil; add_match r, false, i end
    def add_match r, m, i = nil
        r.strip! if r.respond_to? :strip!
        return if r.to_s.empty?
        if i; self.matches.insert(i, [r, m])
        else; self.matches << [r, m] end
    end
    def remove_match i; self.matches.delete_at i end
    def match uri, converter = nil
        return false unless @rewrites.has_key?( converter ) if converter
        self.matches.inject(false){|s,(r,m)| match_uri(uri, r) ? m : s }
    end

    def []( k ); @db[ k ]; end
    def []=( k, v ); @db[ k ] = v; end

    def do_configure( req, res )
        if configure_proc
            self.request, self.response = req, res
            configure_proc[ req, res ] 
        end
    end

    def do_rewrite( conv, doc, req, res )
        if doc and @rewrites[ conv ]
            self.request, self.response, self.document = req, res, doc
            @rewrites[ conv ][ req, res ]
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

    def read_xhtml_from( uri, full_doc = false, charset = 'raw' )
        read_xhtml( open( uri ) do |f| 
            body = f.read
            if f.content_type =~ /charset=([\w\-]+)/
                charset = $1
            elsif body =~ %r!<meta[^>]+charset\s*=\s*([\w\-]+)!
                charset = $1
            end
            body
        end, full_doc, charset )
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
end
