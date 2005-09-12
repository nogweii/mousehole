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

# Hacks URI to allow a host of ___._
# Actually, it basically just hacks URI to allow any host for HTTP URLs
# but it does it in somewhat of a roundabout way

URI::HTTP.class_eval {
  # Allow http URIs to accept a registry field
  def self.use_registry
    true
  end

  # If we get a nil host, set the host to the registry.
  # This allows us to accept non-standard hosts, like ___._
  def initialize(*args)
    super(*args)
    self.set_host(self.registry) if self.host.nil?
    self.set_registry(nil)
  end
} 
