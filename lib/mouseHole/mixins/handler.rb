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
      connections = split_field(src['connection'].to_s)
      src.each do |key, value|
        key = key.downcase
        if HopByHop.member?(key)      || # RFC2616: 13.5.1
           connections.member?(key)     || # RFC2616: 14.10
           ShouldNotTransfer.member?(key)  # pragmatics
           # @logger.debug("choose_header: `#{key}: #{value}'")
           next
        end
        dst << [key.downcase, value.length == 1 ? value.first : value]
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

    def page_headers(request)
      reqh, env = {}, {}
      request.params.each do |k, v|
        k = k.downcase.gsub('_','-')
        env[k] = v
        if k =~ /^http-/ and k != "http-version"
          reqh[$'] = v
        end
      end
      return reqh, env
    end

    def page_prep(request)
      reqh, env = page_headers(request)
      uri = "http:#{env['path-info']}"
      if uri.match(/[#{Regexp::quote('{}|\^[]`')}]/)
        uri = URI.escape(uri)
      end
      return URI(uri), reqh, env
    end

  end

end
