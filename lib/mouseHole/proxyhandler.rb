require 'mouseHole/page'

module MouseHole

  class MountHandler < Mongrel::HttpHandler
    include HandlerMixin
    include LoggerMixin

    def initialize(block)
      @block = block
    end

    def process(request, response)
      reqh, env = page_headers(request)
      header = []
      choose_header(reqh, header)
      page = Page.new(URI(env['request-uri']), 404, header)
      @block.call(page)
      output(page, response)
    end

  end

  class ProxyHandler < Mongrel::HttpHandler
    include HandlerMixin
    include LoggerMixin

    def initialize(central)
      @central = central
    end

    def process(request, response)
      start = Time.now
      uri, reqh, env = page_prep(request)
        
      if uri.path =~ %r!/([\w\-]{32})/!
        token, trail = $1, $'
        app = @central.find_app :token => token
        if app
          hdlr = app.find_handler :is => :mount, :on => :all, :name => trail
          return hdlr.process(request, response)
        end
      end

      header = []
      choose_header(reqh, header)
      set_via(header)

      http = Net::HTTP.new(env['server-name'], env['server-port'], @central.proxy_host, @central.proxy_port)
      http.open_timeout = 10
      http.read_timeout = 20
      reqm = Net::HTTP.const_get(env['request-method'].capitalize)
      debug "-> connecting to #{uri}", :since => start
      resin = http.request(reqm.new(uri.request_uri, header), reqm::REQUEST_HAS_BODY ? request.body : nil) do |resin|
        header = []
        debug " > opened #{uri}", :since => start
        choose_header(resin.to_hash, header)
        set_via(header)

        page = Page.new(uri, resin.code, header)
        if page.converter and !DOMAINS.include?(env['server-name']) and @central.rewrite(page, resin)
          info "*> rewriting #{page.location}", :since => start
          output(page, response)
        else
          debug " > streaming #{page.location}", :since => start
          response.status = resin.code.to_i
          header.each { |k, v| response.header[k] = v }
          response.send_plain_status
          response.send_header
          resin.read_body do |chunk|
            response.write(chunk)
          end
        end
      end
      debug "-> finished #{uri}", :since => start
      resin
    end

  end

end
