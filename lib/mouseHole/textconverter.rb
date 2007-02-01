require 'mouseHole/converters'

module MouseHole::Converters

  class Text < Base
    mime_type "text/*"

    class << self

      def parse(page, body)
        body
      end

      def output(document)
        document.to_s
      end

    end

  end

end
