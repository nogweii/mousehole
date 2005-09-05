#
# DNS hack to override based on HOSTS constant
#
module Net
class InternetMessageIO
    alias_method :_init, :initialize
    def initialize( *args )
        if defined? ::HOSTS and ::HOSTS.has_key? args.first
            if ::HOSTS[args[0]] =~ /:/
                args[0], args[1] = ::HOSTS[args[0]].split(/:/)
            else
                args[0] = ::HOSTS[args[0]]
            end
        end
        _init( *args )
    end
end
end

