require 'net/http'
module Net
class HTTPIO < HTTP
    def request(req, body = nil, &block)  # :yield: +response+
        unless started?
            start
            req['connection'] ||= 'close'
        end
        if proxy_user()
            req.proxy_basic_auth proxy_user(), proxy_pass()
        end

        if req.respond_to? :set_body_internal
            req.set_body_internal body
            begin_transport req
            req.exec @socket, @curr_http_version, edit_path(req.path)
        else
            begin_transport req
            req.exec @socket, @curr_http_version, edit_path(req.path), body
        end
        begin
            res = HTTPResponse.read_new(@socket)
        end while HTTPContinue === res
        sock = @socket
        http = self
        res.instance_eval do 
            @len = nil
            @http = http
            @req = req
            @socket = sock
            @body_exist = req.response_body_permitted? && self.class.body_permitted?
            def read clen = nil
                return if @read
                if @body_exist
                    dest = ''
                    if chunked?
                        while true
                            unless @len
                                line = @socket.readline
                                hexlen = line.slice(/[0-9a-fA-F]+/) or
                                    raise HTTPBadResponse, "wrong chunk size line: #{line}"
                                @len = hexlen.hex
                            end
                            if @len == 0
                                @read = true
                                break
                            end
                            clen = [@len, clen].min if clen
                            @socket.read((clen or @len), dest)
                            if clen
                                @len -= clen
                                break if @len > 0
                            end
                            @len = nil
                            @socket.read 2   # \r\n
                        end
                        until @socket.readline.empty?
                          # none
                        end if @read
                    else
                        clen ||= content_length()
                        if clen
                            @socket.read clen, dest
                        else
                            clen = range_length()
                            if clen
                                @socket.read clen, dest
                            else
                                @socket.read_all dest
                            end
                        end
                    end
                    dest
                else
                    nil
                end
            rescue EOFError
                @read = true
                dest
            end
            def body; true end
            def close
                req, res = @req, self
                @http.instance_eval do
                    end_transport req, res
                    finish
                end
            end
            def size; 0 end
            def is_a? klass; klass == IO ? true : super(klass); end
        end

        res
    end
end
end
