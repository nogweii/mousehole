require 'open-uri'
require 'net/https'

class Array
  def to_h
    self.inject({}) do |hash, value|
      hash[value.first] = value.last ; hash
    end
  end
end

def fetch(uri, header, proxy_url, limit = 10)
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  prox = URI.parse(proxy_url)
  http_obj = Net::HTTP::Proxy(prox.host, prox.port).new(uri.host, uri.port)
  if uri.scheme == 'https'
    http_obj.use_ssl = true
    http_obj.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  
  response = http_obj.start { |http| http.request_get(uri.request_uri, header) }
  if (Net::HTTPSuccess === response) then response
  elsif (Net::HTTPRedirection === response) then
    fetch(URI.parse(response['location']), header, proxy_url, limit - 1)
  else
    response.error!
  end
end

class ProxyLike < MouseHole::App
  title 'ProxyLike'
  namespace 'http://whytheluckystiff.net/mouseHole/'
  description %{
    Run pages through the proxy by passing them in on the URL.
    For example, to view Boing Boing through the proxy, use:
    http://127.0.0.1:3704/http://boingboing.net/ 
  }
  version '2.11'
  
  def self.proxy_read(page)
    puts page.headers.inspect
    mH = "http://#{ page.headers['host'] }/"
    uri = URI(page.location.to_s[1..-1])
    options = page.headers
    options.delete_if { |k,v| %w(host accept-encoding).include? k }
    
    doc = fetch(uri, options, mH)
    
    base_uri = uri.dup
    base_uri.path = '/'
    page.document = base_href doc.body, base_uri, mH
  end
  
  mount "http:" do |page|
    proxy_read(page)
  end
  
  mount "https:" do |page|
    proxy_read(page)
  end

  def self.base_href( html, uri, mh )
    html.gsub( /(href\s*=\s*["']?)(#{ uri }|\/+)/, "\\1#{ mh }#{ uri }" ).
      sub( /<html/i, %(<base href="#{ uri }" /><html) )
  end
end
