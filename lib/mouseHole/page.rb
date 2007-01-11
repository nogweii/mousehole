module MouseHole

  class PageHeaders < Array
    def []( k )
      self.assoc(k.to_s.downcase).to_a[1]
    end
    def []=(k, v)
      k = k.to_s.downcase
      if (tmp = self.assoc(k))
        tmp[1] = v
      else
        self << [k, v] 
      end
      v
    end
  end

  class Page
    attr_accessor :location, :status, :headers, :converter, :document, :input
    def initialize(uri, status, headers)
      @location = uri
      @status = status
      @input = Camping.qsp(uri.query)
      @headers = PageHeaders[*headers]
      ctype = @headers['Content-Type']
      if ctype
        @converter = Converters.detect_by_mime_type ctype.split(';',2)[0]
      end
    end

    # MrCode's gzip decoding from WonderLand!  Also reads in remainder of the body from the
    # stream.
    def decode(resin)
      body = ''
      resin.read_body do |chunk|
        body += chunk
      end

      case resin['content-encoding']
      when 'gzip':
        gzr = Zlib::GzipReader.new(StringIO.new(body))
        body = gzr.read
        gzr.close
        self.headers['content-encoding'] = nil
      when 'deflate':
        body = Zlib::Inflate.inflate(body)
        self.headers['content-encoding'] = nil
      end

      @document = @converter.parse(self, body)
      if @document
        true
      else
        @document = body
        false
      end
    end 

    def body=(str)
      @document = str
    end

    def body
      if @converter
        @converter.output(document)
      else
        document.to_s
      end
    end

    class ElementNotFound < StandardError; end

    def method_missing(ele, &b)
      node = @document.at(ele)
      if node
        node.inner_html = Markaby::Builder.new({},self,&b).to_s
      else
        raise ElementNotFound, "No `#{ele}' found on the page."
      end
    end

  end

end
