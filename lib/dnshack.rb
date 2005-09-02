#
# DNS hack to override based on HOSTS constant
#
module Net
class InternetMessageIO
    alias_method :_init, :initialize
    def initialize( *args )
        if defined? ::HOSTS and ::HOSTS.has_key? args.first
            args[0] = ::HOSTS[args[0]]
        end
        _init( *args )
    end
end
end

