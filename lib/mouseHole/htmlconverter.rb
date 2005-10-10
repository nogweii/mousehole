require 'mouseHole/converters'

module MouseHole
module Converters

class HTML < Base
    mime_type "text/html"
    mime_type "application/xhtml+xml"

    def self.parse(script, req, res)
        charset = 'raw'
        if "#{ res['content-type'] }" =~ /charset=([\w\-]+)/
            charset = $1
        elsif res.body =~ %r!<meta[^>]+charset\s*=\s*([\w\-]+)!
            charset = $1
        end
        script.read_xhtml( res.body, true, charset ) rescue nil
    end
    def self.output(document, res)
        fix_doc(document) if REXML::Element == document
        document.write(res.body = "")
    end
    def self.fix_doc(e)
        if(HTree::ElementContent[e.expanded_name] == :EMPTY)
            e.children.each { |x| x.delete}
        elsif e.children.empty?
            e << REXML::Text.new('')
        end
        e.each { |x| fix_doc(x) if REXML::Element === x}
    end
end

end
end
