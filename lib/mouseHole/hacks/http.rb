require 'net/http'

class Net::HTTP
  alias __request__ request

  # Replace the request method in Net::HTTP to sniff the body type
  # and set the stream if appropriate
  def request(req, body = nil, &block)
    if body != nil && body.respond_to?(:read)
      req.body_stream = body
      return __request__(req, nil, &block)
    else
      return __request__(req, body, &block)
    end
  end
end
