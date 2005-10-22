require 'yaml/dbm'
require 'delegate'
module MouseHole::Databases
class YAMLDB
    def initialize( options = nil )
        raise ConnectionError, "Remote YAML::DBM is not supported" if \
            options['host'] or options['port']
        @path = options['path']
    end
    def open_table( table_name )
        YAML::DBM.open( File.join( @path, table_name ) )
    end
end
end
