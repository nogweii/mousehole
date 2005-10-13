module FeedTools
  # The <tt>FeedTools::Feed</tt> class represents a web feed's structure.
  class Feed    
    include REXML # :nodoc:
  
    # Represents a feed/feed item's category
    class Category
    
      # The category term value
      attr_accessor :term
      # The categorization scheme
      attr_accessor :scheme
      # A human-readable description of the category
      attr_accessor :label
    
      alias_method :value, :term
      alias_method :category, :term
      alias_method :domain, :scheme
    end
  
    # Represents a feed/feed item's author
    class Author

      # The author's real name
      attr_accessor :name
      # The author's email address
      attr_accessor :email
      # The url of the author's homepage
      attr_accessor :url
      # The raw value of the author tag if present
      attr_accessor :raw
    end
  
    # Represents a feed's image
    class Image

      # The image's title
      attr_accessor :title
      # The image's description
      attr_accessor :description
      # The image's url
      attr_accessor :url
      # The url to link the image to
      attr_accessor :link
      # The width of the image
      attr_accessor :width
      # The height of the image
      attr_accessor :height
      # The style of the image
      # Possible values are "icon", "image", or "image-wide"
      attr_accessor :style
    end

    # Represents a feed's text input element.
    # Be aware that this will be ignored for feed generation.  It's a
    # pointless element that aggregators usually ignore and it doesn't have an
    # equivalent in all feeds types.
    class TextInput

      # The label of the Submit button in the text input area.
      attr_accessor :title
      # The description explains the text input area.
      attr_accessor :description
      # The URL of the CGI script that processes text input requests.
      attr_accessor :link
      # The name of the text object in the text input area.
      attr_accessor :name
    end
  
    # Represents a feed's cloud.
    # Be aware that this will be ignored for feed generation.
    class Cloud

      # The domain of the cloud.
      attr_accessor :domain
      # The path for the cloud.
      attr_accessor :path
      # The port the cloud is listening on.
      attr_accessor :port
      # The web services protocol the cloud uses.
      # Possible values are either "xml-rpc" or "soap".
      attr_accessor :protocol
      # The procedure to use to request notification.
      attr_accessor :register_procedure
    end
  
    # Represents a simple hyperlink
    class Link

      # The url that is being linked to
      attr_accessor :url
      # The content of the hyperlink
      attr_accessor :value
    
      alias_method :href, :url
    end
  
    # Initialize the feed object
    def initialize
      super
      @cache_object = nil
      @http_headers = nil
      @xml_doc = nil
      @feed_data = nil
      @feed_data_type = nil
      @root_node = nil
      @channel_node = nil
      @url = nil
      @id = nil
      @title = nil
      @description = nil
      @link = nil
      @time_to_live = nil
      @items = nil
      @live = false
    end
  
    # Raises an exception if an invalid option has been specified to
    # prevent misspellings from slipping through 
    def Feed.validate_options(valid_option_keys, supplied_option_keys)
      unknown_option_keys = supplied_option_keys - valid_option_keys
      unless unknown_option_keys.empty?
        raise ArgumentError, "Unknown options: #{unknown_option_keys}"
      end
    end
    class << self; private :validate_options; end
  
    # Loads the feed specified by the url, pulling the data from the
    # cache if it hasn't expired.
    # Options are:
    # * <tt>:cache_only</tt> - If set to true, the feed will only be
    #   pulled from the cache.
    def Feed.open(url, options={})
      validate_options([ :cache_only ],
                       options.keys)
      options = { :cache_only => false }.merge(options)
          
      if options[:cache_only] && FeedTools.feed_cache.nil?
        raise(ArgumentError, "There is currently no caching mechanism set. " +
          "Cannot retrieve cached feeds.")
      end
      
      # clean up the url
      url = FeedTools.normalize_url(url)

      # create and load the new feed
      feed = Feed.new
      feed.url = url
      feed.update! unless options[:cache_only]
      return feed
    end

    # Loads the feed from the remote url if the feed has expired from the cache or cannot be
    # retrieved from the cache for some reason.
    def update!
      if self.http_headers.nil? && !(self.cache_object.nil?) &&
          !(self.cache_object.http_headers.nil?)
        @http_headers = YAML.load(self.cache_object.http_headers)
        @http_headers = {} unless @http_headers.kind_of? Hash
      end
      if self.expired? == false
        @live = false
      else
        load_remote_feed!
      end
    end
  
    # Attempts to load the feed from the remote location.  Requires the url
    # field to be set.  If an etag or the last_modified date has been set,
    # attempts to use them to prevent unnecessary reloading of identical
    # content.
    def load_remote_feed!
      @live = true
      if self.http_headers.nil? && !(self.cache_object.nil?) &&
          !(self.cache_object.http_headers.nil?)
        @http_headers = YAML.load(self.cache_object.http_headers)
      end
    
      if (self.url =~ /^feed:/) == 0
        # Woah, Nelly, how'd that happen?  You should've already been
        # corrected.  So let's fix that url.  And please,
        # just use less crappy browsers instead of badly defined
        # pseudo-protocol hacks.
        self.url = FeedTools.normalize_url(self.url)
      end
    
      # Find out what method we're going to be using to obtain this feed.
      uri = URI.parse(self.url)
      retrieval_method = "http"
      case uri.scheme
      when "http"
        retrieval_method = "http"
      when "ftp"
        retrieval_method = "ftp"
      when "file"
        retrieval_method = "file"
      when nil
        raise FeedAccessError,
          "No protocol was specified in the url."
      else
        raise FeedAccessError,
          "Cannot retrieve feed using unrecognized protocol: " + uri.scheme
      end
    
      # No need for http headers unless we're actually doing http
      if retrieval_method == "http"
        # Set up the appropriate http headers
        headers = {}
        unless self.http_headers.nil?
          headers["If-None-Match"] =
            self.http_headers['etag'] unless self.http_headers['etag'].nil?
          headers["If-Modified-Since"] =
            self.http_headers['last-modified'] unless
            self.http_headers['last-modified'].nil?
        end
        headers["User-Agent"] =
          FeedTools.user_agent unless FeedTools.user_agent.nil?

        # The http feed access method
        http_fetch = lambda do |feed_url, http_headers, redirect_limit,
            response_chain, no_headers|
          raise FeedAccessError, 'Redirect too deep' if redirect_limit == 0
          feed_uri = nil
          begin
            feed_uri = URI.parse(feed_url)
          rescue URI::InvalidURIError
            # Uh, maybe try to fix it?
            feed_uri = URI.parse(FeedTools.normalize_url(feed_url))
          end

          # Borrowed from open-uri:
          # According to RFC2616 14.23, Host: request-header field should be
          # set to an origin server.
          # But net/http wrongly set a proxy server if an absolute URI is
          # specified as a request URI.
          # So override it here explicitly.
          http_headers['Host'] = feed_uri.host
          http_headers['Host'] += ":#{feed_uri.port}" if feed_uri.port
        
          Net::HTTP.start(feed_uri.host, (feed_uri.port or 80)) do |http|
            final_uri = feed_uri.path 
            final_uri += ('?' + feed_uri.query) if feed_uri.query
            http_headers = {} if no_headers
            response = http.request_get(final_uri, http_headers)

            case response
            when Net::HTTPSuccess
              # We've reached the final destination, process all previous
              # redirections, and see if we need to update the url.
              for redirected_response in response_chain
                if redirected_response.last.code.to_i == 301
                  # Reset the cache object or we may get duplicate entries
                  self.cache_object = nil
                  self.url = redirected_response.last['location']
                else
                  # Jump out as soon as we hit anything that isn't a
                  # permanently moved redirection.
                  break
                end
              end
              response
            when Net::HTTPRedirection
              if response.code.to_i == 304
                response.error!
              else
                if response['location'].nil?
                  raise FeedAccessError,
                    "No location to redirect to supplied: " + response.code
                end
                response_chain << [feed_url, response]
                new_location = response['location']
                if response_chain.assoc(new_location) != nil
                  raise FeedAccessError, "Redirection loop detected."
                end
              
                # Find out if we've already seen the url we've been
                # redirected to.
                found_redirect = false
                begin
                  cached_feed = FeedTools::Feed.open(new_location,
                    :cache_only => true)
                  if cached_feed.cache_object != nil &&
                      cached_feed.cache_object.new_record? != true
                    unless cached_feed.expired?
                      # Copy the cached state, starting with the url
                      self.url = cached_feed.url
                      self.title = cached_feed.title
                      self.link = cached_feed.link
                      self.feed_data = cached_feed.feed_data
                      self.feed_data_type = cached_feed.feed_data_type
                      self.last_retrieved = cached_feed.last_retrieved
                      self.http_headers = cached_feed.http_headers
                      self.cache_object = cached_feed.cache_object
                      @live = false
                      found_redirect = true
                    end
                  end
                rescue
                  # If anything goes wrong, ignore it.
                end
                unless found_redirect
                  # TODO: deal with stupid people using relative urls
                  # in Location header
                  # =================================================
                  http_fetch.call(new_location, http_headers,
                    redirect_limit - 1, response_chain, no_headers)
                else
                  response
                end
              end
            else
              class << response
                def response_chain
                  return @response_chain
                end
              end
              response.instance_variable_set("@response_chain",
                response_chain)
              response.error!
            end
          end
        end
      
        begin
          begin
            @http_response = http_fetch.call(self.url, headers, 10, [], false)
          rescue => error
            if error.respond_to?(:response)
              # You might not believe this, but...
              #
              # Under certain circumstances, web servers will try to block
              # based on the User-Agent header.  This is *retarded*.  But
              # we won't let their stupid error stop us!
              #
              # This is, of course, a quick-n-dirty hack.  But at least
              # we get to blame other people's bad software and/or bad
              # configuration files.
              if error.response.code.to_i == 404 &&
                  FeedTools.user_agent != nil
                @http_response = http_fetch.call(self.url, {}, 10, [], true)
                if @http_response != nil && @http_response.code.to_i == 200
                  warn("The server appears to be blocking based on the " +
                    "User-Agent header.  This is stupid, and you should " +
                    "inform the webmaster of this.")
                end
              else
                raise error
              end
            else
              raise error
            end
          end
          unless @http_response.kind_of? Net::HTTPRedirection
            @http_headers = {}
            self.http_response.each_header do |header|
              self.http_headers[header.first.downcase] = header.last
            end
            self.last_retrieved = Time.now
            self.feed_data = self.http_response.body
          end
        rescue FeedAccessError
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue Timeout::Error
          # if we time out, do nothing, it should fall back to the feed_data
          # stored in the cache.
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue Errno::ECONNRESET
          # if the connection gets reset by peer, oh well, fall back to the
          # feed_data stored in the cache
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue => error
          # heck, if anything at all bad happens, fall back to the feed_data
          # stored in the cache.
        
          # If we can, get the HTTPResponse...
          @http_response = nil
          if error.respond_to?(:each_header)
            @http_response = error
          end
          if error.respond_to?(:response) &&
              error.response.respond_to?(:each_header)
            @http_response = error.response
          end
          if @http_response != nil
            @http_headers = {}
            self.http_response.each_header do |header|
              self.http_headers[header.first] = header.last
            end
            if self.http_response.code.to_i == 304
              self.last_retrieved = Time.now
            end
          end
          @live = false
          if self.feed_data.nil?
            if error.respond_to?(:response) &&
                error.response.respond_to?(:response_chain)
              redirects = error.response.response_chain.map do |pair|
                pair.first
              end
              error.message << (" - Redirects: " + redirects.inspect)
            end
            raise error
          end
        end
      elsif retrieval_method == "https"
        # Not supported... yet
      elsif retrieval_method == "ftp"
        # Not supported... yet
        # Technically, CDF feeds are supposed to be able to be accessed directly
        # from an ftp server.  This is silly, but we'll humor Microsoft.
        #
        # Eventually.
      elsif retrieval_method == "file"
        # Now that we've gone to all that trouble to ensure the url begins
        # with 'file://', strip the 'file://' off the front of the url.
        file_name = self.url.gsub(/^file:\/\//, "")
        begin
          open(file_name) do |file|
            @http_response = nil
            @http_headers = {}
            self.last_retrieved = Time.now
            self.feed_data = file.read
            self.feed_data_type = :xml
          end
        rescue
          @live = false
          # In this case, pulling from the cache is probably not going
          # to help at all, and the use should probably be immediately
          # appraised of the problem.  Raise the exception.
          raise
        end
      end
      unless self.cache_object.nil?
        begin
          self.save
        rescue
        end
      end
    end
      
    # Returns the relevant information from an http request.
    def http_response
      return @http_response
    end

    # Returns a hash of the http headers from the response.
    def http_headers
      return @http_headers
    end
  
    # Returns the feed's raw data.
    def feed_data
      if @feed_data.nil?
        unless self.cache_object.nil?
          @feed_data = self.cache_object.feed_data
        end
      end
      return @feed_data
    end
  
    # Sets the feed's data.
    def feed_data=(new_feed_data)
      @feed_data = new_feed_data
      unless self.cache_object.nil?
        self.cache_object.feed_data = new_feed_data
      end
    end
    
    # Returns the data type of the feed
    # Possible values:
    # * :xml
    # * :yaml
    # * :text
    def feed_data_type
      if @feed_data_type.nil?
        # Right now, nothing else is supported
        @feed_data_type = :xml
      end
      return @feed_data_type
    end

    # Sets the feed's data type.
    def feed_data_type=(new_feed_data_type)
      @feed_data_type = new_feed_data_type
      unless self.cache_object.nil?
        self.cache_object.feed_data_type = new_feed_data_type
      end
    end
  
    # Returns a REXML Document of the feed_data
    def xml
      if self.feed_data_type != :xml
        @xml_doc = nil
      else
        if @xml_doc.nil?
          begin
            # TODO: :ignore_whitespace_nodes => :all
            # Add that?
            # ======================================
            @xml_doc = Document.new(feed_data)
          rescue
            # Something failed, attempt to repair the xml with htree.
            @xml_doc = HTree.parse(feed_data).to_rexml
          end
        end
      end
      return @xml_doc
    end
  
    # Returns the first node within the channel_node that matches the xpath query.
    def find_node(xpath)
      return XPath.first(channel_node, xpath)
    end
  
    # Returns all nodes within the channel_node that match the xpath query.
    def find_all_nodes(xpath)
      return XPath.match(channel_node, xpath)
    end
  
    # Returns the root node of the feed.
    def root_node
      if @root_node.nil?
        # TODO: Fix this so that added content at the end of the file doesn't
        # break this stuff.
        # E.g.: http://smogzer.tripod.com/smog.rdf
        # ===================================================================
        @root_node = xml.root
      end
      return @root_node
    end
  
    # Returns the channel node of the feed.
    def channel_node
      if @channel_node.nil? && root_node != nil
        @channel_node = XPath.first(root_node, "channel")
        if @channel_node == nil
          @channel_node = XPath.first(root_node, "CHANNEL")
        end
        if @channel_node == nil
          @channel_node = XPath.first(root_node, "feedinfo")
        end
        if @channel_node == nil
          @channel_node = root_node
        end
      end
      return @channel_node
    end
  
    # The cache object that handles the feed persistence.
    def cache_object
      unless FeedTools.feed_cache.nil?
        if @cache_object.nil?
          begin
            if @id != nil
              @cache_object = FeedTools.feed_cache.find_by_id(@id)
            elsif @url != nil
              @cache_object = FeedTools.feed_cache.find_by_url(@url)
            end
            if @cache_object.nil?
              @cache_object = FeedTools.feed_cache.new
            end
          rescue
          end      
        end
      end
      return @cache_object
    end
  
    # Sets the cache object for this feed.
    #
    # This can be any object, but it must accept the following messages:
    # url
    # url=
    # title
    # title=
    # link
    # link=
    # feed_data
    # feed_data=
    # feed_data_type
    # feed_data_type=
    # etag
    # etag=
    # last_modified
    # last_modified=
    # save
    def cache_object=(new_cache_object)
      @cache_object = new_cache_object
    end
  
    # Returns the type of feed
    # Possible values:
    # "rss", "atom", "cdf", "!okay/news"
    def feed_type
      if @feed_type.nil?
        case self.root_node.name.downcase
        when "feed"
          @feed_type = "atom"
        when "rdf:rdf"
          @feed_type = "rss"
        when "rdf"
          @feed_type = "rss"
        when "rss"
          @feed_type = "rss"
        when "channel"
          @feed_type = "cdf"
        end
      end
      return @feed_type
    end
  
    # Sets the default feed type
    def feed_type=(new_feed_type)
      @feed_type = new_feed_type
    end
  
    # Returns the version number of the feed type.
    # Intentionally does not differentiate between the Netscape and Userland
    # versions of RSS 0.91.
    def feed_version
      if @feed_version.nil?
        version = nil
        begin
          version = XPath.first(root_node, "@version").to_s.strip.to_f
        rescue
        end
        version = nil if version == 0.0
        default_namespace = XPath.first(root_node, "@xmlns").to_s.strip
        case self.feed_type
        when "atom"
          if default_namespace == "http://www.w3.org/2005/Atom"
            @feed_version = 1.0
          elsif version != nil
            @feed_version = version
          elsif default_namespace == "http://purl.org/atom/ns#"
            @feed_version = 0.3
          end
        when "rss"
          if default_namespace == "http://my.netscape.com/rdf/simple/0.9/"
            @feed_version = 0.9
          elsif default_namespace == "http://purl.org/rss/1.0/"
            @feed_version = 1.0
          elsif default_namespace == "http://purl.org/net/rss1.1#"
            @feed_version = 1.1
          elsif version != nil
            case version
            when 2.1
              @feed_version = 2.0
            when 2.01
              @feed_version = 2.0
            else
              @feed_version = version
            end
          end
        when "cdf"
          @feed_version = 0.4
        when "!okay/news"
          @feed_version = nil
        end
      end
      return @feed_version
    end

    # Sets the default feed version
    def feed_version=(new_feed_version)
      @feed_version = new_feed_version
    end

    # Returns the feed's unique id
    def id
      if @id.nil?
        unless channel_node.nil?
          @id = XPath.first(channel_node, "id/text()").to_s
          if @id == ""
            @id = XPath.first(channel_node, "guid/text()").to_s
          end
        end
        unless root_node.nil?
          if @id == "" || @id.nil?
            @id = XPath.first(root_node, "id/text()").to_s
          end
          if @id == ""
            @id = XPath.first(root_node, "guid/text()").to_s
          end
        end
        @id = nil if @id == ""
      end
      return @id
    end
  
    # Sets the feed's unique id
    def id=(new_id)
      @id = new_id
    end
  
    # Returns the feed url.
    def url
      if @url.nil? && self.feed_data != nil
        @url = XPath.first(channel_node, "link[@rel='self']/@href").to_s
        @url = nil if @url == ""
      end
      return @url
    end
  
    # Sets the feed url and prepares the cache_object if necessary.
    def url=(new_url)
      @url = FeedTools.normalize_url(new_url)
      self.cache_object.url = new_url unless self.cache_object.nil?
    end
  
    # Returns the feed title
    def title
      if @title.nil?
        unless channel_node.nil?
          repair_entities = false
          title_node = XPath.first(channel_node, "title")
          if title_node.nil?
            title_node = XPath.first(channel_node, "dc:title")
          end
          if title_node.nil?
            title_node = XPath.first(channel_node, "TITLE")
          end
        end
        if title_node.nil?
          return nil
        end
        if XPath.first(title_node, "@type").to_s == "xhtml" || 
            XPath.first(title_node, "@mode").to_s == "xhtml" ||
            XPath.first(title_node, "@type").to_s == "xml" || 
            XPath.first(title_node, "@mode").to_s == "xml" ||
            XPath.first(title_node, "@type").to_s == "application/xhtml+xml"
          @title = title_node.inner_xml
        elsif XPath.first(title_node, "@type").to_s == "escaped" ||
            XPath.first(title_node, "@mode").to_s == "escaped"
          @title = FeedTools.unescape_entities(
            XPath.first(title_node, "text()").to_s)
        else
          @title = title_node.inner_xml
          repair_entities = true
        end
        unless @title.nil?
          @title = FeedTools.sanitize_html(@title, :strip)
          @title = FeedTools.unescape_entities(@title) if repair_entities
          @title = FeedTools.tidy_html(@title) unless repair_entities
        end
        @title.gsub!(/>\n</, "><")
        @title.gsub!(/\n/, " ")
        @title.strip!
        @title = nil if @title == ""
        self.cache_object.title = @title unless self.cache_object.nil?
      end
      return @title
    end
  
    # Sets the feed title
    def title=(new_title)
      @title = new_title
      self.cache_object.title = new_title unless self.cache_object.nil?
    end

    # Returns the feed description
    def description
      if @description.nil?
        unless channel_node.nil?
          repair_entities = false
          description_node = XPath.first(channel_node, "description")
          if description_node.nil?
            description_node = XPath.first(channel_node, "tagline")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "subtitle")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "summary")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "abstract")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "ABSTRACT")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "info")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "content:encoded")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "content:encoded",
              FEED_TOOLS_NAMESPACES)
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "encoded")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "content")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "xhtml:body")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "body")
          end
          if description_node.nil?
            description_node = XPath.first(channel_node, "blurb")
          end
        end
        if description_node.nil?
          return nil
        end
        unless description_node.nil?
          if XPath.first(description_node, "@encoding").to_s != ""
            @description =
              "[Embedded data objects are not currently supported.]"
          elsif description_node.cdatas.size > 0
            @description = description_node.cdatas.first.value
          elsif XPath.first(description_node, "@type").to_s == "xhtml" || 
              XPath.first(description_node, "@mode").to_s == "xhtml" ||
              XPath.first(description_node, "@type").to_s == "xml" || 
              XPath.first(description_node, "@mode").to_s == "xml" ||
              XPath.first(description_node, "@type").to_s ==
                "application/xhtml+xml"
            @description = description_node.inner_xml
          elsif XPath.first(description_node, "@type").to_s == "escaped" ||
              XPath.first(description_node, "@mode").to_s == "escaped"
            @description = FeedTools.unescape_entities(
              description_node.inner_xml)
          else
            @description = description_node.inner_xml
            repair_entities = true
          end
        end
        if @description == ""
          @description = self.itunes_summary
          @description = "" if @description.nil?
        end
        if @description == ""
          @description = self.itunes_subtitle
          @description = "" if @description.nil?
        end

        unless @description.nil?
          @description = FeedTools.sanitize_html(@description, :strip)
          @description = FeedTools.unescape_entities(@description) if repair_entities
          @description = FeedTools.tidy_html(@description) unless repair_entities
        end

        @description = @description.strip unless @description.nil?
        @description = nil if @description == ""
      end
      return @description
    end

    # Sets the feed description
    def description=(new_description)
      @description = new_description
    end

    # Returns the contents of the itunes:summary element
    def itunes_summary
      if @itunes_summary.nil?
        unless channel_node.nil?
          @itunes_summary = FeedTools.unescape_entities(XPath.first(channel_node,
            "itunes:summary/text()").to_s)
        end
        unless root_node.nil?
          if @itunes_summary == "" || @itunes_summary.nil?
            @itunes_summary = FeedTools.unescape_entities(XPath.first(root_node,
              "itunes:summary/text()").to_s)
          end
        end
        if @itunes_summary == ""
          @itunes_summary = nil
        end
        @itunes_summary =
          FeedTools.sanitize_html(@itunes_summary) unless @itunes_summary.nil?
      end
      return @itunes_summary
    end

    # Sets the contents of the itunes:summary element
    def itunes_summary=(new_itunes_summary)
      @itunes_summary = new_itunes_summary
    end

    # Returns the contents of the itunes:subtitle element
    def itunes_subtitle
      if @itunes_subtitle.nil?
        unless channel_node.nil?
          @itunes_subtitle = FeedTools.unescape_entities(XPath.first(channel_node,
            "itunes:subtitle/text()").to_s)
        end
        unless root_node.nil?
          if @itunes_subtitle == "" || @itunes_subtitle.nil?
            @itunes_subtitle = FeedTools.unescape_entities(XPath.first(root_node,
              "itunes:subtitle/text()").to_s)
          end
        end
        if @itunes_subtitle == ""
          @itunes_subtitle = nil
        end
        unless @itunes_subtitle.nil?
          @itunes_subtitle = FeedTools.sanitize_html(@itunes_subtitle)
        end
      end
      return @itunes_subtitle
    end

    # Sets the contents of the itunes:subtitle element
    def itunes_subtitle=(new_itunes_subtitle)
      @itunes_subtitle = new_itunes_subtitle
    end

    # Returns the feed link
    def link
      if @link.nil?
        unless channel_node.nil?
          # get the feed link from the xml document
          @link = XPath.first(channel_node, "link[@rel='alternate' @type='text/html']/@href").to_s
          if @link == ""
            @link = XPath.first(channel_node, "link[@rel='alternate']/@href").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "link/@href").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "link/text()").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "@href").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "@HREF").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "a/@href").to_s
          end
          if @link == ""
            @link = XPath.first(channel_node, "A/@HREF").to_s
          end
        end
        if @link == "" || @link.nil?
          if FeedTools.is_uri? self.guid
            @link = self.guid
          end
        end
        if @link == "" && channel_node != nil
          # Technically, we shouldn't use the base attribute for this, but if the href attribute
          # is missing, it's already a given that we're looking at a messed up CDF file.  We can
          # always pray it's correct.
          @link = XPath.first(channel_node, "@base").to_s
        end
        @link = FeedTools.normalize_url(@link)
        unless self.cache_object.nil?
          self.cache_object.link = @link
        end
      end
      return @link
    end

    # Sets the feed link
    def link=(new_link)
      @link = new_link
      unless self.cache_object.nil?
        self.cache_object.link = new_link
      end
    end

    # Returns the url to the icon file for this feed.
    #
    # This method uses the url from the link field in order to avoid grabbing
    # the favicon for services like feedburner.
    def icon
      if @icon.nil?
        icon_node = XPath.first(channel_node, "link[@rel='icon']")
        if icon_node.nil?
          icon_node = XPath.first(channel_node, "link[@rel='shortcut icon']")
        end
        if icon_node.nil?
          icon_node = XPath.first(channel_node, "link[@type='image/x-icon']")
        end
        if icon_node.nil?
          icon_node = XPath.first(channel_node, "icon")
        end
        if icon_node.nil?
          icon_node = XPath.first(channel_node, "logo[@style='icon']")
        end
        if icon_node.nil?
          icon_node = XPath.first(channel_node, "LOGO[@STYLE='ICON']")
        end
        unless icon_node.nil?
          @icon = FeedTools.unescape_entities(
            XPath.first(icon_node, "@href").to_s)
          if @icon == ""
            @icon = FeedTools.unescape_entities(
              XPath.first(icon_node, "text()").to_s)
            unless FeedTools.is_uri? @icon
              @icon = ""
            end
          end
          if @icon == "" && self.link != nil && self.link != ""
            link_uri = URI.parse(FeedTools.normalize_url(self.link))
            @icon =
              link_uri.scheme + "://" + link_uri.host + "/favicon.ico"
          end
          @icon = nil if @icon == ""
        end
      end
      return @icon
    end

    # Returns the feed author
    def author
      if @author.nil?
        @author = FeedTools::Feed::Author.new
        unless channel_node.nil?
          author_node = XPath.first(channel_node, "author")
          if author_node.nil?
            author_node = XPath.first(channel_node, "managingEditor")
          end
          if author_node.nil?
            author_node = XPath.first(channel_node, "dc:author")
          end
          if author_node.nil?
            author_node = XPath.first(channel_node, "dc:creator")
          end
          if author_node.nil?
            author_node = XPath.first(channel_node, "atom:author")
          end
        end
        unless author_node.nil?
          @author.raw = FeedTools.unescape_entities(
            XPath.first(author_node, "text()").to_s)
          @author.raw = nil if @author.raw == ""
          unless @author.raw.nil?
            raw_scan = @author.raw.scan(
              /(.*)\((\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\)/i)
            if raw_scan.nil? || raw_scan.size == 0
              raw_scan = @author.raw.scan(
                /(\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\s*\((.*)\)/i)
              author_raw_pair = raw_scan.first.reverse unless raw_scan.size == 0
            else
              author_raw_pair = raw_scan.first
            end
            if raw_scan.nil? || raw_scan.size == 0
              email_scan = @author.raw.scan(
                /\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b/i)
              if email_scan != nil && email_scan.size > 0
                @author.email = email_scan.first.strip
              end
            end
            unless author_raw_pair.nil? || author_raw_pair.size == 0
              @author.name = author_raw_pair.first.strip
              @author.email = author_raw_pair.last.strip
            else
              unless @author.raw.include?("@")
                # We can be reasonably sure we are looking at something
                # that the creator didn't intend to contain an email address if
                # it got through the preceeding regexes and it doesn't
                # contain the tell-tale '@' symbol.
                @author.name = @author.raw
              end
            end
          end
          @author.name = "" if @author.name.nil?
          if @author.name == ""
            @author.name = FeedTools.unescape_entities(
              XPath.first(author_node, "name/text()").to_s)
          end
          if @author.name == ""
            @author.name = FeedTools.unescape_entities(
              XPath.first(author_node, "@name").to_s)
          end
          if @author.email == ""
            @author.email = FeedTools.unescape_entities(
              XPath.first(author_node, "email/text()").to_s)
          end
          if @author.email == ""
            @author.email = FeedTools.unescape_entities(
              XPath.first(author_node, "@email").to_s)
          end
          if @author.url == ""
            @author.url = FeedTools.unescape_entities(
              XPath.first(author_node, "url/text()").to_s)
          end
          if @author.url == ""
            @author.url = FeedTools.unescape_entities(
              XPath.first(author_node, "@url").to_s)
          end
          @author.name = nil if @author.name == ""
          @author.raw = nil if @author.raw == ""
          @author.email = nil if @author.email == ""
          @author.url = nil if @author.url == ""
        end
        # Fallback on the itunes module if we didn't find an author name
        begin
          @author.name = self.itunes_author if @author.name.nil?
        rescue
          @author.name = nil
        end
      end
      return @author
    end

    # Sets the feed author
    def author=(new_author)
      if new_author.respond_to?(:name) &&
          new_author.respond_to?(:email) &&
          new_author.respond_to?(:url)
        # It's a complete author object, just set it.
        @author = new_author
      else
        # We're not looking at an author object, this is probably a string,
        # default to setting the author's name.
        if @author.nil?
          @author = FeedTools::Feed::Author.new
        end
        @author.name = new_author
      end
    end

    # Returns the feed publisher
    def publisher
      if @publisher.nil?
        @publisher = FeedTools::Feed::Author.new

        # Set the author name
        @publisher.raw = FeedTools.unescape_entities(
          XPath.first(channel_node, "dc:publisher/text()").to_s)
        if @publisher.raw == ""
          @publisher.raw = FeedTools.unescape_entities(
            XPath.first(channel_node, "webMaster/text()").to_s)
        end
        unless @publisher.raw == ""
          raw_scan = @publisher.raw.scan(
            /(.*)\((\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\)/i)
          if raw_scan.nil? || raw_scan.size == 0
            raw_scan = @publisher.raw.scan(
              /(\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\s*\((.*)\)/i)
            unless raw_scan.size == 0
              publisher_raw_pair = raw_scan.first.reverse
            end
          else
            publisher_raw_pair = raw_scan.first
          end
          if raw_scan.nil? || raw_scan.size == 0
            email_scan = @publisher.raw.scan(
              /\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b/i)
            if email_scan != nil && email_scan.size > 0
              @publisher.email = email_scan.first.strip
            end
          end
          unless publisher_raw_pair.nil? || publisher_raw_pair.size == 0
            @publisher.name = publisher_raw_pair.first.strip
            @publisher.email = publisher_raw_pair.last.strip
          else
            unless @publisher.raw.include?("@")
              # We can be reasonably sure we are looking at something
              # that the creator didn't intend to contain an email address if
              # it got through the preceeding regexes and it doesn't
              # contain the tell-tale '@' symbol.
              @publisher.name = @publisher.raw
            end
          end
        end

        @publisher.name = nil if @publisher.name == ""
        @publisher.raw = nil if @publisher.raw == ""
        @publisher.email = nil if @publisher.email == ""
        @publisher.url = nil if @publisher.url == ""
      end
      return @publisher
    end

    # Sets the feed publisher
    def publisher=(new_publisher)
      if new_publisher.respond_to?(:name) &&
          new_publisher.respond_to?(:email) &&
          new_publisher.respond_to?(:url)
        # It's a complete Author object, just set it.
        @publisher = new_publisher
      else
        # We're not looking at an Author object, this is probably a string,
        # default to setting the publisher's name.
        if @publisher.nil?
          @publisher = FeedTools::Feed::Author.new
        end
        @publisher.name = new_publisher
      end
    end
  
    # Returns the contents of the itunes:author element
    #
    # Returns any incorrectly placed channel-level itunes:author
    # elements.  They're actually amazingly common.  People don't read specs.
    # There is no setter for this, since this is an incorrectly placed
    # attribute.
    def itunes_author
      if @itunes_author.nil?
        @itunes_author = FeedTools.unescape_entities(XPath.first(channel_node,
          "itunes:author/text()").to_s)
        @itunes_author = nil if @itunes_author == ""
      end
      return @itunes_author
    end

    # Returns the feed item time
    def time
      if @time.nil?
        unless channel_node.nil?
          time_string = XPath.first(channel_node, "pubDate/text()").to_s
          if time_string == ""
            time_string = XPath.first(channel_node, "dc:date/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(channel_node, "issued/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(channel_node, "updated/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(channel_node, "time/text()").to_s
          end
        end
        begin
          if time_string != nil && time_string != ""
            @time = Time.parse(time_string) rescue self.succ_time
          elsif time_string == nil
            @time = self.succ_time
          end
          if @time == nil
            @time = Time.now
          end
        rescue
          @time = Time.now
        end
      end
      return @time
    end
  
    # Sets the feed item time
    def time=(new_time)
      @time = new_time
    end
  
    # Returns 1 second after the previous item's time.
    def succ_time #:nodoc:
      begin
        if feed.nil?
          return nil
        end
        feed.items
        unsorted_items = feed.instance_variable_get("@items")
        item_index = unsorted_items.index(self)
        if item_index.nil?
          return nil
        end
        if item_index <= 0
          return Time.now
        end
        previous_item = unsorted_items[item_index - 1]
        return previous_item.time.succ
      rescue
        return nil
      end
    end
    private :succ_time

    # Returns the feed item updated time
    def updated
      if @updated.nil?
        unless channel_node.nil?
          updated_string = XPath.first(channel_node, "updated/text()").to_s
          if updated_string == ""
            updated_string = XPath.first(channel_node, "modified/text()").to_s
          end
        end
        if updated_string != nil && updated_string != ""
          @updated = Time.parse(updated_string) rescue nil
        else
          @updated = nil
        end
      end
      return @updated
    end
  
    # Sets the feed item updated time
    def updated=(new_updated)
      @updated = new_updated
    end

    # Returns the feed item issued time
    def issued
      if @issued.nil?
        unless channel_node.nil?
          issued_string = XPath.first(channel_node, "issued/text()").to_s
          if issued_string == ""
            issued_string = XPath.first(channel_node, "pubDate/text()").to_s
          end
          if issued_string == ""
            issued_string = XPath.first(channel_node, "dc:date/text()").to_s
          end
          if issued_string == ""
            issued_string = XPath.first(channel_node, "published/text()").to_s
          end
        end
        if issued_string != nil && issued_string != ""
          @issued = Time.parse(issued_string) rescue nil
        else
          @issued = nil
        end
      end
      return @issued
    end
  
    # Sets the feed item issued time
    def issued=(new_issued)
      @issued = new_issued
    end

    # Returns the feed item published time
    def published
      if @published.nil?
        unless channel_node.nil?
          published_string = XPath.first(channel_node, "published/text()").to_s
          if published_string == ""
            published_string = XPath.first(channel_node, "pubDate/text()").to_s
          end
          if published_string == ""
            published_string = XPath.first(channel_node, "dc:date/text()").to_s
          end
          if published_string == ""
            published_string = XPath.first(channel_node, "issued/text()").to_s
          end
        end
        if published_string != nil && published_string != ""
          @published = Time.parse(published_string) rescue nil
        else
          @published = nil
        end
      end
      return @published
    end
  
    # Sets the feed item published time
    def published=(new_published)
      @published = new_published
    end

    # Returns a list of the feed's categories
    def categories
      if @categories.nil?
        @categories = []
        category_nodes = XPath.match(channel_node, "category")
        if category_nodes.nil? || category_nodes.empty?
          category_nodes = XPath.match(channel_node, "dc:subject")
        end
        unless category_nodes.nil?
          for category_node in category_nodes
            category = FeedTools::Feed::Category.new
            category.term = XPath.first(category_node, "@term").to_s
            if category.term == ""
              category.term = XPath.first(category_node, "text()").to_s
            end
            category.term.strip! unless category.term.nil?
            category.term = nil if category.term == ""
            category.label = XPath.first(category_node, "@label").to_s
            category.label.strip! unless category.label.nil?
            category.label = nil if category.label == ""
            category.scheme = XPath.first(category_node, "@scheme").to_s
            if category.scheme == ""
              category.scheme = XPath.first(category_node, "@domain").to_s
            end
            category.scheme.strip! unless category.scheme.nil?
            category.scheme = nil if category.scheme == ""
            @categories << category
          end
        end
      end
      return @categories
    end
  
    # Returns a list of the feed's images
    def images
      if @images.nil?
        @images = []
        unless channel_node.nil?
          image_nodes = XPath.match(channel_node, "image")
          if image_nodes.nil? || image_nodes.empty?
            image_nodes = XPath.match(channel_node, "link")
          end
          if image_nodes.nil? || image_nodes.empty?
            image_nodes = XPath.match(channel_node, "logo")
          end
          if image_nodes.nil? || image_nodes.empty?
            image_nodes = XPath.match(channel_node, "LOGO")
          end
          unless image_nodes.nil?
            for image_node in image_nodes
              image = FeedTools::Feed::Image.new
              image.url = XPath.first(image_node, "url/text()").to_s
              if image.url == ""
                image.url = XPath.first(image_node, "@rdf:resource").to_s
              end
              if image.url == "" && (image_node.name == "logo" ||
                  (image_node.attributes['type'] =~ /^image/) == 0)
                image.url = XPath.first(image_node, "@href").to_s
              end
              if image.url == "" && image_node.name == "LOGO"
                image.url = XPath.first(image_node, "@HREF").to_s
              end
              image.url.strip! unless image.url.nil?
              image.url = nil if image.url == ""
              image.title = XPath.first(image_node, "title/text()").to_s
              image.title.strip! unless image.title.nil?
              image.title = nil if image.title == ""
              image.description =
                XPath.first(image_node, "description/text()").to_s
              image.description.strip! unless image.description.nil?
              image.description = nil if image.description == ""
              image.link = XPath.first(image_node, "link/text()").to_s
              image.link.strip! unless image.link.nil?
              image.link = nil if image.link == ""
              image.height = XPath.first(image_node, "height/text()").to_s.to_i
              image.height = nil if image.height <= 0
              image.width = XPath.first(image_node, "width/text()").to_s.to_i
              image.width = nil if image.width <= 0
              image.style = XPath.first(image_node, "@style").to_s.downcase
              if image.style == ""
                image.style = XPath.first(image_node, "@STYLE").to_s.downcase
              end
              image.style.strip! unless image.style.nil?
              image.style = nil if image.style == ""
              @images << image
            end
          end
        end
      end
      return @images
    end
  
    # Returns the feed's text input field
    def text_input
      if @text_input.nil?
        @text_input = FeedTools::Feed::TextInput.new
        text_input_node = XPath.first(channel_node, "textInput")
        unless text_input_node.nil?
          @text_input.title =
            XPath.first(text_input_node, "title/text()").to_s
          @text_input.title = nil if @text_input.title == ""
          @text_input.description =
            XPath.first(text_input_node, "description/text()").to_s
          @text_input.description = nil if @text_input.description == ""
          @text_input.link =
            XPath.first(text_input_node, "link/text()").to_s
          @text_input.link = nil if @text_input.link == ""
          @text_input.name =
            XPath.first(text_input_node, "name/text()").to_s
          @text_input.name = nil if @text_input.name == ""
        end
      end
      return @text_input
    end
      
    # Returns the feed's copyright information
    def copyright
      if @copyright.nil?
        unless channel_node.nil?
          @copyright = XPath.first(channel_node, "copyright/text()").to_s
          if @copyright == ""
            @copyright = XPath.first(channel_node, "rights/text()").to_s
          end
          if @copyright == ""
            @copyright = XPath.first(channel_node, "dc:rights/text()").to_s
          end
          if @copyright == ""
            @copyright = XPath.first(channel_node, "copyrights/text()").to_s
          end
          @copyright = FeedTools.sanitize_html(@copyright, :strip)
          @copyright = nil if @copyright == ""
        end
      end
      return @copyright
    end

    # Sets the feed's copyright information
    def copyright=(new_copyright)
      @copyright = new_copyright
    end

    # Returns the number of seconds before the feed should expire
    def time_to_live
      if @time_to_live.nil?
        unless channel_node.nil?
          # get the feed time to live from the xml document
          update_frequency = XPath.first(channel_node, "syn:updateFrequency/text()").to_s
          if update_frequency != ""
            update_period = XPath.first(channel_node, "syn:updatePeriod/text()").to_s
            if update_period == "daily"
              @time_to_live = update_frequency.to_i.day
            elsif update_period == "weekly"
              @time_to_live = update_frequency.to_i.week
            elsif update_period == "monthly"
              @time_to_live = update_frequency.to_i.month
            elsif update_period == "yearly"
              @time_to_live = update_frequency.to_i.year
            else
              # hourly
              @time_to_live = update_frequency.to_i.hour
            end
          end
          if @time_to_live.nil?
            # usually expressed in minutes
            update_frequency = XPath.first(channel_node, "ttl/text()").to_s
            if update_frequency != ""
              update_span = XPath.first(channel_node, "ttl/@span").to_s
              if update_span == "seconds"
                @time_to_live = update_frequency.to_i
              elsif update_span == "minutes"
                @time_to_live = update_frequency.to_i.minute
              elsif update_span == "hours"
                @time_to_live = update_frequency.to_i.hour
              elsif update_span == "days"
                @time_to_live = update_frequency.to_i.day
              elsif update_span == "weeks"
                @time_to_live = update_frequency.to_i.week
              elsif update_span == "months"
                @time_to_live = update_frequency.to_i.month
              elsif update_span == "years"
                @time_to_live = update_frequency.to_i.year
              elsif update_frequency.to_i >= 3000
                # Normally, this should default to minutes, but realistically,
                # if they meant minutes, you're rarely going to see a value higher
                # than 120.  If we see >= 3000, we're either dealing with a stupid
                # pseudo-spec that decided to use seconds, or we're looking at
                # someone who only has weekly updated content.  Worst case, we
                # misreport the time, and we update too often.  Best case, we
                # avoid accidentally updating the feed only once a year.  In the
                # interests of being pragmatic, and since the problem we avoid
                # is a far greater one than the one we cause, just run the check
                # and hope no one actually gets hurt.
                @time_to_live = update_frequency.to_i
              else
                @time_to_live = update_frequency.to_i.minute
              end
            end
          end
          if @time_to_live.nil?
            @time_to_live = 0
            update_frequency_days =
              XPath.first(channel_node, "schedule/intervaltime/@days").to_s
            update_frequency_hours =
              XPath.first(channel_node, "schedule/intervaltime/@hour").to_s
            update_frequency_minutes =
              XPath.first(channel_node, "schedule/intervaltime/@min").to_s
            update_frequency_seconds =
              XPath.first(channel_node, "schedule/intervaltime/@sec").to_s
            if update_frequency_days != ""
              @time_to_live = @time_to_live + update_frequency_days.to_i.day
            end
            if update_frequency_hours != ""
              @time_to_live = @time_to_live + update_frequency_hours.to_i.hour
            end
            if update_frequency_minutes != ""
              @time_to_live = @time_to_live + update_frequency_minutes.to_i.minute
            end
            if update_frequency_seconds != ""
              @time_to_live = @time_to_live + update_frequency_seconds.to_i
            end
            if @time_to_live == 0
              @time_to_live = 1.hour
            end
          end
        end
      end
      if @time_to_live.nil? || @time_to_live == 0
        # Default to one hour
        @time_to_live = 1.hour
      end
      @time_to_live = @time_to_live.round
      return @time_to_live
    end

    # Sets the feed time to live
    def time_to_live=(new_time_to_live)
      @time_to_live = new_time_to_live.round
      @time_to_live = 1.hour if @time_to_live < 1.hour
    end

    # Returns the feed's cloud
    def cloud
      if @cloud.nil?
        @cloud = FeedTools::Feed::Cloud.new
        @cloud.domain = XPath.first(channel_node, "cloud/@domain").to_s
        @cloud.port = XPath.first(channel_node, "cloud/@port").to_s
        @cloud.path = XPath.first(channel_node, "cloud/@path").to_s
        @cloud.register_procedure =
          XPath.first(channel_node, "cloud/@registerProcedure").to_s
        @cloud.protocol =
          XPath.first(channel_node, "cloud/@protocol").to_s.downcase
        @cloud.domain = nil if @cloud.domain == ""
        @cloud.port = nil if @cloud.port == ""
        @cloud.port = @cloud.port.to_i unless @cloud.port.nil?
        @cloud.port = nil if @cloud.port == 0
        @cloud.path = nil if @cloud.path == ""
        @cloud.register_procedure = nil if @cloud.register_procedure == ""
        @cloud.protocol = nil if @cloud.protocol == ""
      end
      return @cloud
    end
  
    # Sets the feed's cloud
    def cloud=(new_cloud)
      @cloud = new_cloud
    end
  
    # Returns the feed generator
    def generator
      if @generator.nil?
        @generator = XPath.first(channel_node, "generator/text()").to_s
        @generator = FeedTools.strip_html(@generator)
        @generator = nil if @generator == ""
      end
      return @generator
    end

    # Sets the feed generator
    def generator=(new_generator)
      @generator = new_generator
    end

    # Returns the feed docs
    def docs
      if @docs.nil?
        @docs = XPath.first(channel_node, "docs/text()").to_s
        @docs = FeedTools.strip_html(@docs)
        @docs = nil if @docs == ""
      end
      return @docs
    end

    # Sets the feed docs
    def docs=(new_docs)
      @docs = new_docs
    end

    # Returns the feed language
    def language
      if @language.nil?
        unless channel_node.nil?
          @language = XPath.first(channel_node, "language/text()").to_s
          if @language == ""
            @language = XPath.first(channel_node, "dc:language/text()").to_s
          end
          if @language == ""
            @language = XPath.first(channel_node, "xml:lang/text()").to_s
          end
          if @language == ""
            @language = XPath.first(root_node, "xml:lang/text()").to_s
          end
        end
        if @language == "" || @language.nil?
          @language = "en-us"
        end
        @language = @language.downcase
        @language = nil if @language == ""
      end
      return @language
    end

    # Sets the feed language
    def language=(new_language)
      @language = new_language
    end
  
    # Returns true if this feed contains explicit material.
    def explicit?
      if @explicit.nil?
        if XPath.first(channel_node,
              "media:adult/text()").to_s.downcase == "true" ||
            XPath.first(channel_node,
              "itunes:explicit/text()").to_s.downcase == "yes" ||
            XPath.first(channel_node,
              "itunes:explicit/text()").to_s.downcase == "true"
          @explicit = true
        else
          @explicit = false
        end
      end
      return @explicit
    end

    # Sets whether or not the feed contains explicit material
    def explicit=(new_explicit)
      @explicit = (new_explicit ? true : false)
    end
  
    # Returns the feed items
    def items
      if @items.nil?
        unless root_node.nil?
          raw_items = XPath.match(root_node, "item")
          if raw_items == nil || raw_items == []
            raw_items = XPath.match(channel_node, "item")
          end
          if raw_items == nil || raw_items == []
            raw_items = XPath.match(channel_node, "ITEM")
          end
          if raw_items == nil || raw_items == []
            raw_items = XPath.match(root_node, "ITEM")
          end
          if raw_items == nil || raw_items == []
            raw_items = XPath.match(channel_node, "entry")
          end
          if raw_items == nil || raw_items == []
            raw_items = XPath.match(root_node, "entry")
          end
        end

        # create the individual feed items
        @items = []
        if raw_items != nil
          for item_node in raw_items
            new_item = FeedItem.new
            new_item.feed_data = item_node.to_s
            new_item.feed_data_type = self.feed_data_type
            new_item.feed = self
            @items << new_item
          end
        end
      end
    
      # Sort the items
      @items = @items.sort do |a,b|
        (b.time or Time.mktime(1970)) <=> (a.time or Time.mktime(1970))
      end
      return @items
    end
  
    # The time that the feed was last requested from the remote server.  Nil if it has
    # never been pulled, or if it was created from scratch.
    def last_retrieved
      unless self.cache_object.nil?
        @last_retrieved = self.cache_object.last_retrieved
      end
      return @last_retrieved
    end
  
    # Sets the time that the feed was last updated.
    def last_retrieved=(new_last_retrieved)
      @last_retrieved = new_last_retrieved
      unless self.cache_object.nil?
        self.cache_object.last_retrieved = new_last_retrieved
      end
    end
  
    # True if this feed contains audio content enclosures
    def podcast?
      podcast = false
      self.items.each do |item|
        item.enclosures.each do |enclosure|
          podcast = true if enclosure.audio?
        end
      end
      return podcast
    end

    # True if this feed contains video content enclosures
    def vidlog?
      vidlog = false
      self.items.each do |item|
        item.enclosures.each do |enclosure|
          vidlog = true if enclosure.video?
        end
      end
      return vidlog
    end
  
    # True if the feed was not last retrieved from the cache.
    def live?
      return @live
    end
  
    # True if the feed has expired and must be reacquired from the remote
    # server.
    def expired?
      return self.last_retrieved == nil ||
        (self.last_retrieved + self.time_to_live) < Time.now
    end
  
    # Forces this feed to expire.
    def expire!
      self.last_retrieved = Time.mktime(1970).gmtime
      self.save
    end

    # A hook method that is called during the feed generation process.
    # Overriding this method will enable additional content to be
    # inserted into the feed.
    def build_xml_hook(feed_type, version, xml_builder)
      return nil
    end

    # Generates xml based on the content of the feed
    def build_xml(feed_type=(self.feed_type or "rss"), version=nil,
        xml_builder=Builder::XmlMarkup.new(:indent => 2))
      if feed_type == "rss" && (version == nil || version == 0.0)
        version = 1.0
      elsif feed_type == "atom" && (version == nil || version == 0.0)
        version = 0.3
      end
      if feed_type == "rss" && (version == 0.9 || version == 1.0 ||
          version == 1.1)
        # RDF-based rss format
        return xml_builder.tag!("rdf:RDF",
            "xmlns" => "http://purl.org/rss/1.0/",
            "xmlns:rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
            "xmlns:syn" => "http://purl.org/rss/1.0/modules/syndication/",
            "xmlns:taxo" => "http://purl.org/rss/1.0/modules/taxonomy/",
            "xmlns:itunes" => "http://www.itunes.com/DTDs/Podcast-1.0.dtd",
            "xmlns:media" => "http://search.yahoo.com/mrss") do
          channel_attributes = {}
          unless self.link.nil?
            channel_attributes["rdf:about"] = CGI.escapeHTML(self.link)
          end
          xml_builder.channel(channel_attributes) do
            unless title.nil? || title == ""
              xml_builder.title(title)
            else
              xml_builder.title
            end
            unless link.nil? || link == ""
              xml_builder.link(link)
            else
              xml_builder.link
            end
            unless images.nil? || images.empty?
              xml_builder.image("rdf:resource" => CGI.escapeHTML(
                images.first.url))
            end
            unless description.nil? || description == ""
              xml_builder.description(description)
            else
              xml_builder.description
            end
            unless language.nil? || language == ""
              xml_builder.tag!("dc:language", language)
            end
            xml_builder.tag!("syn:updatePeriod", "hourly")
            xml_builder.tag!("syn:updateFrequency", (time_to_live / 1.hour).to_s)
            xml_builder.tag!("syn:updateBase", Time.mktime(1970).iso8601)
            xml_builder.items do
              xml_builder.tag!("rdf:Seq") do
                unless items.nil?
                  for item in items
                    if item.link.nil?
                      raise "Cannot generate an rdf-based feed with a nil item link field."
                    end
                    xml_builder.tag!("rdf:li", "rdf:resource" => CGI.escapeHTML(item.link))
                  end
                end
              end
            end
            build_xml_hook(feed_type, version, xml_builder)
          end
          unless images.nil? || images.empty?
            best_image = nil
            for image in self.images
              if image.link != nil
                best_image = image
                break
              end
            end
            best_image = images.first if best_image.nil?
            xml_builder.image("rdf:about" => CGI.escapeHTML(best_image.url)) do
              if best_image.title != nil && best_image.title != ""
                xml_builder.title(best_image.title)
              elsif self.title != nil && self.title != ""
                xml_builder.title(self.title)
              else
                xml_builder.title
              end
              unless best_image.url.nil? || best_image.url == ""
                xml_builder.url(best_image.url)
              end
              if best_image.link != nil && best_image.link != ""
                xml_builder.link(best_image.link)
              elsif self.link != nil && self.link != ""
                xml_builder.link(self.link)
              else
                xml_builder.link
              end
            end
          end
          unless items.nil?
            for item in items
              item.build_xml(feed_type, version, xml_builder)
            end
          end
        end
      elsif feed_type == "rss"
        # normal rss format
        return xml_builder.rss("version" => "2.0",
            "xmlns:rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
            "xmlns:taxo" => "http://purl.org/rss/1.0/modules/taxonomy/",
            "xmlns:trackback" =>
              "http://madskills.com/public/xml/rss/module/trackback/",
            "xmlns:itunes" => "http://www.itunes.com/DTDs/Podcast-1.0.dtd",
            "xmlns:media" => "http://search.yahoo.com/mrss") do
          xml_builder.channel do
            unless title.nil? || title == ""
              xml_builder.title(title)
            end
            unless link.nil? || link == ""
              xml_builder.link(link)
            end
            unless description.nil? || description == ""
              xml_builder.description(description)
            end
            xml_builder.ttl((time_to_live / 1.minute).to_s)
            xml_builder.generator(
              "http://www.sporkmonger.com/projects/feedtools")
            build_xml_hook(feed_type, version, xml_builder)
            unless items.nil?
              for item in items
                item.build_xml(feed_type, version, xml_builder)
              end
            end
          end
        end
      elsif feed_type == "atom" && version == 0.3
        # normal atom format
        return xml_builder.feed("xmlns" => "http://purl.org/atom/ns#",
            "version" => version,
            "xml:lang" => language) do
          unless title.nil? || title == ""
            xml_builder.title(title,
                "mode" => "escaped",
                "type" => "text/html")
          end
          xml_builder.author do
            unless self.author.nil? || self.author.name.nil?
              xml_builder.name(self.author.name)
            else
              xml_builder.name("n/a")
            end
            unless self.author.nil? || self.author.email.nil?
              xml_builder.email(self.author.email)
            end
            unless self.author.nil? || self.author.url.nil?
              xml_builder.url(self.author.url)
            end
          end
          unless link.nil? || link == ""
            xml_builder.link("href" => link,
                "rel" => "alternate",
                "type" => "text/html",
                "title" => title)
          end
          unless description.nil? || description == ""
            xml_builder.tagline(description,
                "mode" => "escaped",
                "type" => "text/html")
          end
          xml_builder.generator("FeedTools",
              "url" => "http://www.sporkmonger.com/projects/feedtools")
          build_xml_hook(feed_type, version, xml_builder)
          unless items.nil?
            for item in items
              item.build_xml(feed_type, version, xml_builder)
            end
          end
        end
      elsif feed_type == "atom" && version == 1.0
        # normal atom format
        return xml_builder.feed("xmlns" => "http://www.w3.org/2005/Atom",
            "xml:lang" => language) do
          unless title.nil? || title == ""
            xml_builder.title(title,
                "type" => "html")
          end
          xml_builder.author do
            unless self.author.nil? || self.author.name.nil?
              xml_builder.name(self.author.name)
            else
              xml_builder.name("n/a")
            end
            unless self.author.nil? || self.author.email.nil?
              xml_builder.email(self.author.email)
            end
            unless self.author.nil? || self.author.url.nil?
              xml_builder.url(self.author.url)
            end
          end
          unless self.url.nil? || self.url == ""
            xml_builder.link("href" => self.url,
                "rel" => "self",
                "type" => "application/atom+xml")
          end
          unless self.link.nil? || self.link == ""
            xml_builder.link("href" => self.link,
                "rel" => "alternate",
                "type" => "text/html",
                "title" => self.title)
          end
          unless description.nil? || description == ""
            xml_builder.subtitle(description,
                "type" => "html")
          else
            xml_builder.subtitle(FeedTools.no_content_string,
                "type" => "html")
          end
          if self.updated != nil
            xml_builder.updated(self.updated.iso8601)
          elsif self.time != nil
            # Not technically correct, but a heck of a lot better
            # than the Time.now fall-back.
            xml_builder.updated(self.time.iso8601)
          else
            xml_builder.updated(Time.now.iso8601)
          end
          unless self.published.nil?
            xml_builder.published(self.published.iso8601)            
          end
          xml_builder.generator("FeedTools - " +
            "http://www.sporkmonger.com/projects/feedtools")
          if self.id != nil
            unless FeedTools.is_uri? self.id
              if self.link != nil
                xml_builder.id(FeedTools.build_urn_uri(self.link))
              else
                raise "The unique id must be a valid URI."
              end
            else
              xml_builder.id(self.id)
            end
          elsif self.link != nil
            xml_builder.id(FeedTools.build_urn_uri(self.link))
          else
            raise "Cannot build feed, missing feed unique id."
          end
          build_xml_hook(feed_type, version, xml_builder)
          unless items.nil?
            for item in items
              item.build_xml(feed_type, version, xml_builder)
            end
          end
        end
      end
    end

    # Persists the current feed state to the cache.
    def save
      if FeedTools.feed_cache.nil?
        raise "Caching is currently disabled.  Cannot save to cache."
      elsif self.url.nil?
        raise "The url field must be set to save to the cache."
      elsif self.cache_object.nil?
        raise "The cache_object is currently nil.  Cannot save to cache."
      else
        self.cache_object.url = self.url
        unless self.feed_data.nil?
          self.cache_object.title = self.title
          self.cache_object.link = self.link
          self.cache_object.feed_data = self.feed_data
          self.cache_object.feed_data_type = self.feed_data_type.to_s
        end
        unless self.http_response.nil?
          self.cache_object.http_headers = self.http_headers.to_yaml
        end
        self.cache_object.last_retrieved = self.last_retrieved
        self.cache_object.save
      end
    end
  
    alias_method :tagline, :description
    alias_method :tagline=, :description=
    alias_method :subtitle, :description
    alias_method :subtitle=, :description=
    alias_method :abstract, :description
    alias_method :abstract=, :description=
    alias_method :content, :description
    alias_method :content=, :description=
    alias_method :ttl, :time_to_live
    alias_method :ttl=, :time_to_live=
    alias_method :guid, :id
    alias_method :guid=, :id=
    alias_method :entries, :items
  
    # passes missing methods to the cache_object
    def method_missing(msg, *params)
      if self.cache_object.nil?
        raise NoMethodError, "Invalid method #{msg.to_s}"
      end
      return self.cache_object.send(msg, params)
    end

    # passes missing methods to the FeedTools.feed_cache
    def Feed.method_missing(msg, *params)
      if FeedTools.feed_cache.nil?
        raise NoMethodError, "Invalid method Feed.#{msg.to_s}"
      end
      result = FeedTools.feed_cache.send(msg, params)
      if result.kind_of? FeedTools.feed_cache
        result = Feed.open(result.url)
      end
      return result
    end
  
    # Returns a simple representation of the feed object's state.
    def inspect
      return "#<FeedTools::Feed:0x#{self.object_id.to_s(16)} URL:#{self.url}>"
    end
  end
end