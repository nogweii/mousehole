require 'mongrel'
require 'mouseHole/page'

Mongrel::Const.const_set :REQUEST_PATH, "REQUEST_URI".freeze

class Mongrel::HttpResponse
  def send_plain_status
    if not @status_sent
      @socket.write("HTTP/1.1 %d %s\r\n" % [status, Mongrel::HTTP_STATUS_CODES[@status]])
      @status_sent = true
    end
  end
end

#
## Replace the request method in Net::HTTP to sniff the body type
## and set the stream if appropriate
##
class Net::HTTP
  alias __request__ request

  def request(req, body = nil, &block)
    if body != nil && body.respond_to?(:read)
      req.body_stream = body
      return __request__(req, nil, &block)
    else
      return __request__(req, body, &block)
    end
  end
end

module MouseHole

  module HandlerMixin

    def proxy_auth(req, res)
      if proc = @config[:ProxyAuthProc]
      proc.call(req, res)
      end
      req.header.delete("proxy-authorization")
    end

    # Some header fields shuold not be transfered.
    HopByHop = %w( connection keep-alive proxy-authenticate upgrade
             proxy-authorization te trailers transfer-encoding )
    ShouldNotTransfer = %w( proxy-connection )
    def split_field(f) f ? f.split(/,\s+/).collect{|i| i.downcase } : [] end

    def choose_header(src, dst)
      connections = split_field(src['connection'])
      src.each do |key, value|
      key = key.downcase
      if HopByHop.member?(key)      || # RFC2616: 13.5.1
         connections.member?(key)     || # RFC2616: 14.10
         ShouldNotTransfer.member?(key)  # pragmatics
         # @logger.debug("choose_header: `#{key}: #{value}'")
         next
      end
      dst << [key.downcase, value]
      end
    end

    def set_via(h)
      h << ['Via', "MouseHole/#{VERSION}"]
    end

    def proxy_uri(req, res)
      @config[:ProxyURI]
    end

    def output(page, response)
      clength = nil
      response.status = page.status
      page.headers.each do |k, v|
        if k =~ /^CONTENT-LENGTH$/i
        clength = v.to_i
        else
        [*v].each do |vi|
          response.header[k] = vi
        end
        end
      end

      body = page.body
      response.send_status(body.length)
      response.send_header
      response.write(body)
    end

    def page_prep(request)
      reqh, env = {}, {}
      request.params.each do |k, v|
        k = k.downcase.gsub('_','-')
        env[k] = v
        if k =~ /^http-/ and k != "http-version"
          reqh[$'] = v
        end
      end
      path = env['path-info'].gsub("//#{env['server-name']}",'')
      uri = "http:#{env['path-info']}"
      return uri, path, reqh, env
    end
  end

  class MountHandler < Mongrel::HttpHandler
    include HandlerMixin

    def initialize(block)
      @block = block
    end

    def process(request, response)
      uri, path, reqh, env = page_prep(request)
      header = []
      choose_header(reqh, header)
      page = Page.new(uri, 404, header)
      @block.call(page)
      output(page, response)
    end

  end

  class ProxyHandler < Mongrel::HttpHandler
    include HandlerMixin

    def initialize(central)
      @central = central
    end

    def process(request, response)
      uri, path, reqh, env = page_prep(request)
        
      header = []
      choose_header(reqh, header)
      set_via(header)

      http = Net::HTTP.new(env['server-name'], env['server-port'], @central.options.proxy_host, @central.options.proxy_port)
      http.open_timeout = 10
      http.read_timeout = 20
      reqm = Net::HTTP.const_get(env['request-method'].capitalize)
      resin = http.request(reqm.new(path, header), reqm::REQUEST_HAS_BODY ? request.body : nil) do |resin|
        header = []
        # @logger.debug("opened: http:#{env['path-info']}")
        choose_header(resin, header)
        set_via(header)

        page = Page.new(uri, resin.code, header)
        if !DOMAINS.include?(env['server-name']) and @central.rewrite(page, resin)
          puts "** Rewriting #{page.location}..."
          output(page, response)
        else
          response.status = resin.code.to_i
          header.each { |k, v| response.header[k] = v }
          response.send_plain_status
          response.send_header
          resin.read_body do |chunk|
            # @logger.debug("read chunk: http:#{env['path-info']} / #{chunk.length}")
            response.write(chunk)
          end
        end
      end
    end

  end

end
