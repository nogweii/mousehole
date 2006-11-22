require 'mouseHole/converters'

module MouseHole::Converters

  class HTML < Base
    mime_type "text/html"
    mime_type "application/xhtml+xml"

    class << self

      def parse(page, body)
        charset = 'raw'
        if "#{ page.headers['content-type'] }" =~ /charset=([\w\-]+)/
          charset = $1
        elsif body =~ %r!<meta[^>]+charset\s*=\s*([\w\-]+)!
          charset = $1
        end
        parse_xhtml(body, true, charset)
      end

      def output(document)
        if document.respond_to? :to_original_html
          document.to_original_html
        else
          document.to_s
        end
      end

      def parse_xhtml(str, full_doc = false, charset = nil)
        Hpricot.parse(str)
      end

    end

  end

end
