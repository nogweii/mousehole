require 'mongrel'

class Mongrel::HttpParser
  alias_method :__execute__, :execute

  # An alternate execute method since HTTP proxies don't get a REQUEST_PATH.  Instead, use
  # the REQUEST_URI as the path.  That way poxy requests go the the "http:" classification.
  def execute(params, data, nparsed)
    nparsed = __execute__(params, data, nparsed)
    params['REQUEST_PATH'] = params['REQUEST_URI'] if params['REQUEST_PATH'].nil?
    nparsed
  end

end

class Mongrel::HttpResponse

  # Since the ProxyHandler streams data itself with Net::HTTP, it's easier to hack Mongrel
  # than Net::HTTP.  So, let's send the status line on its own, then the headers, body, etc.
  def send_plain_status
    if not @status_sent
      @socket.write("HTTP/1.1 %d %s\r\n" % [status, Mongrel::HTTP_STATUS_CODES[@status]])
      @status_sent = true
    end
  end

end

