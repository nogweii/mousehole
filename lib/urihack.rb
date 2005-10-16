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
