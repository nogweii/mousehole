module MouseHole
module Databases
    class ConnectionError < Exception; end
    def self.open( driver_name, opts = nil )
        driver_name << "db"
        require "mouseHole/#{driver_name}"
        klass = self.constants.detect { |c| c.downcase == driver_name }
        const_get( klass ).new( opts ) if klass
    end
end
end
