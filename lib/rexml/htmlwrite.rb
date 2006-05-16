class REXML::Element
    def write(writer=$stdout, indent=-1, t = nil, h = nil)
        #print "ID:#{indent}"
        writer << "<#@expanded_name"

        @attributes.each_attribute do |attr|
            writer << " "
            attr.write( writer, indent )
        end unless @attributes.empty?

        if HTree::ElementContent[@expanded_name] == :EMPTY
            writer << " />"
        else
            writer << ">"
            write_children( writer, indent, t, h )  
            writer << "</#{expanded_name}>"
        end
    end
end
