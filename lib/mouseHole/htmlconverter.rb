require 'mouseHole/converters'

module MouseHole
module Converters

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
        def output(document, page)
            fix_doc(document) if REXML::Element == document
            document.write(page.body = "")
        end
        def fix_doc(e)
            if(HTree::ElementContent[e.expanded_name] == :EMPTY)
                e.children.each { |x| x.delete}
            elsif e.children.empty?
                e << REXML::Text.new('')
            end
            e.each { |x| fix_doc(x) if REXML::Element === x}
        end
        def parse_xhtml(str, full_doc = false, charset = nil)
            HTree.parse(str).each_child do |child|
                if child.respond_to? :qualified_name
                    if child.qualified_name == 'html'
                        return HTree::Doc.new( child ).to_rexml
                    end
                end
            end
        end
    end
end

end
end
