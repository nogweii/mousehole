require 'open-uri'

class Array
  def to_h
    self.inject({}) do |hash, value|
      hash[value.first] = value.last ; hash
    end
  end
end

class ProxyLike < MouseHole::App
  title 'ProxyLike'
  namespace 'http://whytheluckystiff.net/mouseHole/'
  description %{
    Run pages through the proxy by passing them in on the URL.
    For example, to view Boing Boing through the proxy, use:
    http://localhost:37004/http://boingboing.net/ 
  }
  version '2.1'
  
  mount "http:" do |page|
    mH = "http://#{ page.headers['host'] }/"
    uri = URI(page.location.to_s[1..-1])
    options = {:proxy => mH}.merge(page.headers.to_h)
    options.delete "host"
    page.document =
      uri.open(options) do |f|
      base_uri = uri.dup
      base_uri.path = '/'
      base_href f.read, base_uri, mH
    end
  end

  def self.base_href( html, uri, mh )
    html.gsub( /(href\s*=\s*["']?)(#{ uri }|\/+)/, "\\1#{ mh }#{ uri }" ).
      sub( /<html/i, %(<base href="#{ uri }" /><html) )
  end
end
