# It's freaky! <lwu.two@gmail.com>

require 'open-uri'
require 'sandbox'

class Array; def to_h
    self.inject({}) { |hash, value| hash[value.first] = value.last ; hash }
end; end

def marshal_dump *var
  var.map { |v| "Marshal.load(#{Marshal.dump(v).dump})" }.join(',')
end

class FreakyLike < MouseHole::App
  title 'FreakyLike'
  namespace 'http://www.stanford.edu/'
  description %{
    Extend ProxyLike to be scriptable at proxy(run)time,
    with the help of the freakyfreaky sandbox.

    For example, to view Boing Boing through the proxy,
    using a proxy script defined at http://127.0.0.1:3300/script,
    http://127.0.0.1:3704/rewrite://boingboing.net/http://127.0.0.1:3300/script
  }
  version '1.0'

  RewritePrefix = "rewrite:"

  mount RewritePrefix do |page|

    match = %r{(#{RewritePrefix}//.+)(http://.+)}.match(page.location.to_s).captures
    match[0].gsub!(RewritePrefix, 'http:')
    page_uri, script_uri = URI(match[0]), URI(match[1])

    mH = "http://#{ page.headers['host'] }/"

    # http GET page_uri
    options = page.headers.to_h
    options.delete_if { |k,v| %w(host accept-encoding).include? k }
    page.document = page_uri.open(options) { |f| f.read }

    # http GET script_uri, and apply sandboxed script to document
    begin
      script = script_uri.open(options) { |f| puts f.inspect; f.read }
    rescue
      warn "Couldn't read #{script_uri}"
    end

    begin
      code = %{
        $host = #{marshal_dump(mH)}
        page = MouseHole::Page.restore(#{marshal_dump(page.to_a)})
        eval #{marshal_dump(script)}
        s = ''
        Freaky.rewrite(page).to_s.each { |line| s << line }
        s
      } # TODO: figure out why String can't be referred if returned directly
      page.document = Box.eval(code)
    rescue Sandbox::Exception => e
      page.document = "(Caught sandbox exception: #{e})"
    end

    base_uri = page_uri.dup
    base_uri.path = '/'
    page.document = base_href(page.document, base_uri, mH, script_uri)
  end

  def self.base_href( html, uri, mh, script )
    # TODO: postfix script to outgoing URLs
    # rewrite_uri = uri.to_s.gsub(%r(http://), RewritePrefix+'//')

    rewrite_uri = uri
    doc = html.gsub( /(href\s*=\s*["']?)(#{ uri }|\/+)/, 
                     "\\1#{ mh }#{ rewrite_uri }")
    doc.sub(/<html/i, %(<base href="#{ rewrite_uri }" /><html) )
  end
end

module Web
  def self.escape(s); Camping.escape(s); end
  def self.unescape(s); Camping.un(s); end
end

FreakyLike::Box = Sandbox.safe
FreakyLike::Box.ref Web
FreakyLike::Box.ref MouseHole
FreakyLike::Box.ref MouseHole::Page
FreakyLike::Box.ref MouseHole::PageHeaders
FreakyLike::Box.import URI::HTTP
FreakyLike::Box.import OpenURI::Meta
FreakyLike::Box.import HashWithIndifferentAccess

%w(CGI Time Hpricot PP JSON YAML OpenStruct Sandbox).each do |klass| 
  FreakyLike::Box.import Kernel.const_get(klass)
end

