module MouseHole
module Converters

def self.detect_by_mime_type type_str
    self.constants.map { |c| const_get(c) }.detect do |c|
        if c.respond_to? :handles_mime_type?
            c.handles_mime_type? type_str
        end
    end
end

class Base
    def self.mime_type type_match
        @mime_types ||= []
        @mime_types << type_match
    end
    def self.handles_mime_type? type_str
        (@mime_types || []).any? { |mt| mt === type_str }
    end
end

end
end
