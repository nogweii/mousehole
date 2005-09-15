MouseHole.script do
    name 'ProxyLike'
    namespace 'http://whytheluckystiff.net/mouseHole/'
    description %{
        Run pages through the proxy by passing them in on the URL.
        For example, to view Boing Boing through the proxy, use:
        http://localhost:37004/http://boingboing.net/ 
    }
    version '0.2'

    mount "http:" do |path_info|
        mH = request.request_uri.dup
        mH.path = '/'
        uri = URI.parse("http://#{ path_info }")
        uri.path = '/' if uri.path.empty?
        open(uri, :proxy => mH) do |f|
            base_uri = uri.dup
            base_uri.path = '/'
            base_href f.read, base_uri
        end
    end

    def base_href( html, uri )
        html.gsub( /(href\s*=\s*["']?)(#{ uri }|\/+)/, "\\1http://#{ MOUSEHOST }:#{ MOUSEPORT }/#{ uri }" ).
             gsub( /<head>/, %(<head><base href="#{ uri }" />) )
    end
end
