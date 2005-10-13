module FeedTools
  # The <tt>FeedTools::FeedItem</tt> class represents the structure of
  # a single item within a web feed.
  class FeedItem
    include REXML
    
    # This class stores information about a feed item's file enclosures.
    class Enclosure
      # The url for the enclosure
      attr_accessor :url
      # The MIME type of the file referenced by the enclosure
      attr_accessor :type
      # The size of the file referenced by the enclosure
      attr_accessor :file_size
      # The total play time of the file referenced by the enclosure
      attr_accessor :duration
      # The height in pixels of the enclosed media
      attr_accessor :height
      # The width in pixels of the enclosed media
      attr_accessor :width
      # The bitrate of the enclosed media
      attr_accessor :bitrate
      # The framerate of the enclosed media
      attr_accessor :framerate
      # The thumbnail for this enclosure
      attr_accessor :thumbnail
      # The categories for this enclosure
      attr_accessor :categories
      # A hash of the enclosed file
      attr_accessor :hash
      # A website containing some kind of media player instead of a direct
      # link to the media file.
      attr_accessor :player
      # A list of credits for the enclosed media
      attr_accessor :credits
      # A text rendition of the enclosed media
      attr_accessor :text
      # A list of alternate version of the enclosed media file
      attr_accessor :versions
      # The default version of the enclosed media file
      attr_accessor :default_version
      
      # Returns true if this is the default enclosure
      def is_default?
        return @is_default
      end
      
      # Sets whether this is the default enclosure for the media group
      def is_default=(new_is_default)
        @is_default = new_is_default
      end
        
      # Returns true if the enclosure contains explicit material
      def explicit?
        return @explicit
      end
      
      # Sets the explicit attribute on the enclosure
      def explicit=(new_explicit)
        @explicit = new_explicit
      end
      
      # Determines if the object is a sample, or the full version of the
      # object, or if it is a stream.
      # Possible values are 'sample', 'full', 'nonstop'.
      def expression
        return @expression
      end
      
      # Sets the expression attribute on the enclosure.
      # Allowed values are 'sample', 'full', 'nonstop'.
      def expression=(new_expression)
        unless ['sample', 'full', 'nonstop'].include? new_expression.downcase
          raise ArgumentError,
            "Permitted values are 'sample', 'full', 'nonstop'."
        end
        @expression = new_expression.downcase
      end
      
      # Returns true if this enclosure contains audio content
      def audio?
        unless self.type.nil?
          return true if (self.type =~ /^audio/) != nil
        end
        # TODO: create a more complete list
        # =================================
        audio_extensions = ['mp3', 'm4a', 'm4p', 'wav', 'ogg', 'wma']
        audio_extensions.each do |extension|
          if (url =~ /#{extension}$/) != nil
            return true
          end
        end
        return false
      end

      # Returns true if this enclosure contains video content
      def video?
        unless self.type.nil?
          return true if (self.type =~ /^video/) != nil
          return true if self.type == "image/mov"
        end
        # TODO: create a more complete list
        # =================================
        video_extensions = ['mov', 'mp4', 'avi', 'wmv', 'asf']
        video_extensions.each do |extension|
          if (url =~ /#{extension}$/) != nil
            return true
          end
        end
        return false
      end
      
      alias_method :link, :url
      alias_method :link=, :url=
    end
    
    # TODO: Make these actual classes instead of structs
    # ==================================================
    EnclosureHash = Struct.new( "EnclosureHash", :hash, :type )
    EnclosurePlayer = Struct.new( "EnclosurePlayer", :url, :height, :width )
    EnclosureCredit = Struct.new( "EnclosureCredit", :name, :role )
    EnclosureThumbnail = Struct.new( "EnclosureThumbnail", :url, :height,
      :width )
    
    # Initialize the feed object
    def initialize
      super
      @feed = nil
      @feed_data = nil
      @feed_data_type = nil
      @xml_doc = nil
      @root_node = nil
      @title = nil
      @id = nil
      @time = nil
    end

    # Returns the parent feed of this feed item
    def feed
      return @feed
    end
    
    # Sets the parent feed of this feed item
    def feed=(new_feed)
      @feed = new_feed
    end

    # Returns the feed item's raw data.
    def feed_data
      return @feed_data
    end

    # Sets the feed item's data.
    def feed_data=(new_feed_data)
      @feed_data = new_feed_data
    end

    # Returns the feed item's data type.
    def feed_data_type
      return @feed_data_type
    end

    # Sets the feed item's data type.
    def feed_data_type=(new_feed_data_type)
      @feed_data_type = new_feed_data_type
    end

    # Returns a REXML Document of the feed_data
    def xml
      if self.feed_data_type != :xml
        @xml_doc = nil
      else
        if @xml_doc.nil?
          # TODO: :ignore_whitespace_nodes => :all
          # Add that?
          # ======================================
          @xml_doc = Document.new(self.feed_data)
        end
      end
      return @xml_doc
    end

    # Returns the first node within the root_node that matches the xpath query.
    def find_node(xpath)
      return XPath.first(root_node, xpath)
    end

    # Returns all nodes within the root_node that match the xpath query.
    def find_all_nodes(xpath)
      return XPath.match(root_node, xpath)
    end

    # Returns the root node of the feed item.
    def root_node
      if @root_node.nil?
        @root_node = xml.root
      end
      return @root_node
    end

    # Returns the feed items's unique id
    def id
      if @id.nil?
        unless root_node.nil?
          @id = XPath.first(root_node, "id/text()").to_s
          if @id == ""
            @id = XPath.first(root_node, "guid/text()").to_s
          end
        end
        @id = nil if @id == ""
      end
      return @id
    end

    # Sets the feed item's unique id
    def id=(new_id)
      @id = new_id
    end

    # Returns the feed item title
    def title
      if @title.nil?
        unless root_node.nil?
          repair_entities = false
          title_node = XPath.first(root_node, "title")
          if title_node.nil?
            title_node = XPath.first(root_node, "atom:title")
          end
          if title_node.nil?
            title_node = XPath.first(root_node, "dc:title")
          end
          if title_node.nil?
            title_node = XPath.first(root_node, "TITLE")
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
        if @title != ""
          # Some blogging tools include the number of comments in a post
          # in the title... this is supremely ugly, and breaks any
          # applications which expect the title to be static, so we're
          # gonna strip them out.
          #
          # If for some incredibly wierd reason you need the actual
          # unstripped title, just use find_node("title/text()").to_s
          @title = @title.strip.gsub(/\[\d*\]$/, "").strip
        end
        @title.gsub!(/>\n</, "><")
        @title.gsub!(/\n/, " ")
        @title.strip!
        @title = nil if @title == ""
      end
      return @title
    end
    
    # Sets the feed item title
    def title=(new_title)
      @title = new_title
    end

    # Returns the feed item description
    def description
      if @description.nil?
        unless root_node.nil?
          repair_entities = false
          description_node = XPath.first(root_node, "content:encoded")
          if description_node.nil?
            description_node = XPath.first(root_node, "content:encoded",
              FEED_TOOLS_NAMESPACES)
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "encoded")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "content")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "fullitem")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "xhtml:body")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "xhtml:body",
              FEED_TOOLS_NAMESPACES)
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "body")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "description")
          end          
          if description_node.nil?
            description_node = XPath.first(root_node, "tagline")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "subtitle")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "summary")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "abstract")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "ABSTRACT")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "blurb")
          end
          if description_node.nil?
            description_node = XPath.first(root_node, "info")
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

    # Sets the feed item description
    def description=(new_description)
      @description = new_description
    end
    
    # Returns the contents of the itunes:summary element
    def itunes_summary
      if @itunes_summary.nil?
        @itunes_summary = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:summary/text()").to_s)
        if @itunes_summary == ""
          @itunes_summary = nil
        end
        unless @itunes_summary.nil?
          @itunes_summary = FeedTools.sanitize_html(@itunes_summary)
        end
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
        @itunes_subtitle = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:subtitle/text()").to_s)
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

    # Returns the contents of the media:text element
    def media_text
      if @media_text.nil?
        @media_text = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:subtitle/text()").to_s)
        if @media_text == ""
          @media_text = nil
        end
        unless @media_text.nil?
          @media_text = FeedTools.sanitize_html(@media_text)
        end
      end
      return @media_text
    end

    # Sets the contents of the media:text element
    def media_text=(new_media_text)
      @media_text = new_media_text
    end

    # Returns the feed item link
    def link
      if @link.nil?
        unless root_node.nil?
          @link = XPath.first(root_node, "link[@rel='alternate']/@href").to_s
          if @link == ""
            @link = XPath.first(root_node, "link/@href").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "link/text()").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "@rdf:about").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "guid[@isPermaLink='true']/text()").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "@href").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "a/@href").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "@HREF").to_s
          end
          if @link == ""
            @link = XPath.first(root_node, "A/@HREF").to_s
          end
        end
        if @link == "" || @link.nil?
          if FeedTools.is_uri? self.guid
            @link = self.guid
          end
        end
        if @link != ""
          @link = FeedTools.unescape_entities(@link)
        end
# TODO: Actually implement proper relative url resolving instead of this crap
# ===========================================================================
# 
#        if @link != "" && (@link =~ /http:\/\//) != 0 && (@link =~ /https:\/\//) != 0
#          if (feed.base[-1..-1] == "/" && @link[0..0] == "/")
#            @link = @link[1..-1]
#          end
#          # prepend the base to the link since they seem to have used a relative path
#          @link = feed.base + @link
#        end
        @link = FeedTools.normalize_url(@link)
      end
      return @link
    end
    
    # Sets the feed item link
    def link=(new_link)
      @link = new_link
    end
        
    # Returns a list of the feed item's categories
    def categories
      if @categories.nil?
        @categories = []
        category_nodes = XPath.match(root_node, "category")
        if category_nodes.nil? || category_nodes.empty?
          category_nodes = XPath.match(root_node, "dc:subject")
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
    
    # Returns a list of the feed items's images
    def images
      if @images.nil?
        @images = []
        image_nodes = XPath.match(root_node, "link")
        if image_nodes.nil? || image_nodes.empty?
          image_nodes = XPath.match(root_node, "logo")
        end
        if image_nodes.nil? || image_nodes.empty?
          image_nodes = XPath.match(root_node, "LOGO")
        end
        if image_nodes.nil? || image_nodes.empty?
          image_nodes = XPath.match(root_node, "image")
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
      return @images
    end
    
    # Returns the feed item itunes image link
    #
    # If it's not present, falls back to the normal image link.
    # Technically, the itunes spec says that the image needs to be
    # square and larger than 300x300, but hey, if there's an image
    # to be had, it's better than none at all.
    def itunes_image_link
      if @itunes_image_link.nil?
        # get the feed item itunes image link from the xml document
        @itunes_image_link = XPath.first(root_node, "itunes:image/@href").to_s
        if @itunes_image_link == ""
          @itunes_image_link = XPath.first(root_node, "itunes:link[@rel='image']/@href").to_s
        end
        @itunes_image_link = FeedTools.normalize_url(@itunes_image_link)
      end
      return @itunes_image_link
    end

    # Sets the feed item itunes image link
    def itunes_image_link=(new_itunes_image_link)
      @itunes_image_link = new_itunes_image_link
    end
    
    # Returns the feed item media thumbnail link
    #
    # If it's not present, falls back to the normal image link.
    def media_thumbnail_link
      if @media_thumbnail_link.nil?
        # get the feed item itunes image link from the xml document
        @media_thumbnail_link = XPath.first(root_node, "media:thumbnail/@url").to_s
        @media_thumbnail_link = FeedTools.normalize_url(@media_thumbnail_link)
      end
      return @media_thumbnail_link
    end

    # Sets the feed item media thumbnail url
    def media_thumbnail_link=(new_media_thumbnail_link)
      @media_thumbnail_link = new_media_thumbnail_link
    end

    # Returns the feed item's copyright information
    def copyright
      if @copyright.nil?
        unless root_node.nil?
          @copyright = XPath.first(root_node, "dc:rights/text()").to_s
          if @copyright == ""
            @copyright = XPath.first(root_node, "rights/text()").to_s
          end
          if @copyright == ""
            @copyright = XPath.first(root_node, "copyright/text()").to_s
          end
          if @copyright == ""
            @copyright = XPath.first(root_node, "copyrights/text()").to_s
          end
          @copyright = FeedTools.sanitize_html(@copyright, :strip)
          @copyright = nil if @copyright == ""
        end
      end
      return @copyright
    end

    # Sets the feed item's copyright information
    def copyright=(new_copyright)
      @copyright = new_copyright
    end

    # Returns all feed item enclosures
    def enclosures
      if @enclosures.nil?
        @enclosures = []
        
        # First, load up all the different possible sources of enclosures
        rss_enclosures = XPath.match(root_node, "enclosure")
        atom_enclosures = XPath.match(root_node, "link[@rel='enclosure']")
        media_content_enclosures = XPath.match(root_node, "media:content")
        media_group_enclosures = XPath.match(root_node, "media:group")
        
        # Parse RSS-type enclosures.  Thanks to a few buggy enclosures implementations,
        # sometimes these also manage to show up in atom files.
        for enclosure_node in rss_enclosures
          enclosure = Enclosure.new
          enclosure.url = FeedTools.unescape_entities(enclosure_node.attributes["url"].to_s)
          enclosure.type = enclosure_node.attributes["type"].to_s
          enclosure.file_size = enclosure_node.attributes["length"].to_i
          enclosure.credits = []
          enclosure.explicit = false
          @enclosures << enclosure
        end
        
        # Parse atom-type enclosures.  If there are repeats of the same enclosure object,
        # we merge the two together.
        for enclosure_node in atom_enclosures
          enclosure_url = FeedTools.unescape_entities(enclosure_node.attributes["href"].to_s)
          enclosure = nil
          new_enclosure = false
          for existing_enclosure in @enclosures
            if existing_enclosure.url == enclosure_url
              enclosure = existing_enclosure
              break
            end
          end
          if enclosure.nil?
            new_enclosure = true
            enclosure = Enclosure.new
          end
          enclosure.url = enclosure_url
          enclosure.type = enclosure_node.attributes["type"].to_s
          enclosure.file_size = enclosure_node.attributes["length"].to_i
          enclosure.credits = []
          enclosure.explicit = false
          if new_enclosure
            @enclosures << enclosure
          end
        end

        # Creates an anonymous method to parse content objects from the media module.  We
        # do this to avoid excessive duplication of code since we have to do identical
        # processing for content objects within group objects.
        parse_media_content = lambda do |media_content_nodes|
          affected_enclosures = []
          for enclosure_node in media_content_nodes
            enclosure_url = FeedTools.unescape_entities(enclosure_node.attributes["url"].to_s)
            enclosure = nil
            new_enclosure = false
            for existing_enclosure in @enclosures
              if existing_enclosure.url == enclosure_url
                enclosure = existing_enclosure
                break
              end
            end
            if enclosure.nil?
              new_enclosure = true
              enclosure = Enclosure.new
            end
            enclosure.url = enclosure_url
            enclosure.type = enclosure_node.attributes["type"].to_s
            enclosure.file_size = enclosure_node.attributes["fileSize"].to_i
            enclosure.duration = enclosure_node.attributes["duration"].to_s
            enclosure.height = enclosure_node.attributes["height"].to_i
            enclosure.width = enclosure_node.attributes["width"].to_i
            enclosure.bitrate = enclosure_node.attributes["bitrate"].to_i
            enclosure.framerate = enclosure_node.attributes["framerate"].to_i
            enclosure.expression = enclosure_node.attributes["expression"].to_s
            enclosure.is_default =
              (enclosure_node.attributes["isDefault"].to_s.downcase == "true")
            if XPath.first(enclosure_node, "media:thumbnail/@url").to_s != ""
              enclosure.thumbnail = EnclosureThumbnail.new(
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:thumbnail/@url").to_s),
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:thumbnail/@height").to_s),
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:thumbnail/@width").to_s)
              )
              if enclosure.thumbnail.height == ""
                enclosure.thumbnail.height = nil
              end
              if enclosure.thumbnail.width == ""
                enclosure.thumbnail.width = nil
              end
            end
            enclosure.categories = []
            for category in XPath.match(enclosure_node, "media:category")
              enclosure.categories << FeedTools::Feed::Category.new
              enclosure.categories.last.term =
                FeedTools.unescape_entities(category.text)
              enclosure.categories.last.scheme =
                FeedTools.unescape_entities(category.attributes["scheme"].to_s)
              enclosure.categories.last.label =
                FeedTools.unescape_entities(category.attributes["label"].to_s)
              if enclosure.categories.last.scheme == ""
                enclosure.categories.last.scheme = nil
              end
              if enclosure.categories.last.label == ""
                enclosure.categories.last.label = nil
              end
            end
            if XPath.first(enclosure_node, "media:hash/text()").to_s != ""
              enclosure.hash = EnclosureHash.new(
                FeedTools.sanitize_html(FeedTools.unescape_entities(XPath.first(
                  enclosure_node, "media:hash/text()").to_s), :strip),
                "md5"
              )
            end
            if XPath.first(enclosure_node, "media:player/@url").to_s != ""
              enclosure.player = EnclosurePlayer.new(
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:player/@url").to_s),
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:player/@height").to_s),
                FeedTools.unescape_entities(XPath.first(enclosure_node, "media:player/@width").to_s)
              )
              if enclosure.player.height == ""
                enclosure.player.height = nil
              end
              if enclosure.player.width == ""
                enclosure.player.width = nil
              end
            end
            enclosure.credits = []
            for credit in XPath.match(enclosure_node, "media:credit")
              enclosure.credits << EnclosureCredit.new(
                FeedTools.unescape_entities(credit.text),
                FeedTools.unescape_entities(credit.attributes["role"].to_s.downcase)
              )
              if enclosure.credits.last.role == ""
                enclosure.credits.last.role = nil
              end
            end
            enclosure.explicit = (XPath.first(enclosure_node,
              "media:adult/text()").to_s.downcase == "true")
            if XPath.first(enclosure_node, "media:text/text()").to_s != ""
              enclosure.text = FeedTools.unescape_entities(XPath.first(enclosure_node,
                "media:text/text()").to_s)
            end
            affected_enclosures << enclosure
            if new_enclosure
              @enclosures << enclosure
            end
          end
          affected_enclosures
        end
        
        # Parse the independant content objects.
        parse_media_content.call(media_content_enclosures)
        
        media_groups = []
        
        # Parse the group objects.
        for media_group in media_group_enclosures
          group_media_content_enclosures =
            XPath.match(media_group, "media:content")
          
          # Parse the content objects within the group objects.
          affected_enclosures =
            parse_media_content.call(group_media_content_enclosures)
          
          # Now make sure that content objects inherit certain properties from
          # the group objects.
          for enclosure in affected_enclosures
            if enclosure.thumbnail.nil? &&
                XPath.first(media_group, "media:thumbnail/@url").to_s != ""
              enclosure.thumbnail = EnclosureThumbnail.new(
                FeedTools.unescape_entities(
                  XPath.first(media_group, "media:thumbnail/@url").to_s),
                FeedTools.unescape_entities(
                  XPath.first(media_group, "media:thumbnail/@height").to_s),
                FeedTools.unescape_entities(
                  XPath.first(media_group, "media:thumbnail/@width").to_s)
              )
              if enclosure.thumbnail.height == ""
                enclosure.thumbnail.height = nil
              end
              if enclosure.thumbnail.width == ""
                enclosure.thumbnail.width = nil
              end
            end
            if (enclosure.categories.nil? || enclosure.categories.size == 0)
              enclosure.categories = []
              for category in XPath.match(media_group, "media:category")
                enclosure.categories << FeedTools::Feed::Category.new
                enclosure.categories.last.term =
                  FeedTools.unescape_entities(category.text)
                enclosure.categories.last.scheme =
                  FeedTools.unescape_entities(category.attributes["scheme"].to_s)
                enclosure.categories.last.label =
                  FeedTools.unescape_entities(category.attributes["label"].to_s)
                if enclosure.categories.last.scheme == ""
                  enclosure.categories.last.scheme = nil
                end
                if enclosure.categories.last.label == ""
                  enclosure.categories.last.label = nil
                end
              end
            end
            if enclosure.hash.nil? &&
                XPath.first(media_group, "media:hash/text()").to_s != ""
              enclosure.hash = EnclosureHash.new(
                FeedTools.unescape_entities(XPath.first(media_group, "media:hash/text()").to_s),
                "md5"
              )
            end
            if enclosure.player.nil? &&
                XPath.first(media_group, "media:player/@url").to_s != ""
              enclosure.player = EnclosurePlayer.new(
                FeedTools.unescape_entities(XPath.first(media_group, "media:player/@url").to_s),
                FeedTools.unescape_entities(XPath.first(media_group, "media:player/@height").to_s),
                FeedTools.unescape_entities(XPath.first(media_group, "media:player/@width").to_s)
              )
              if enclosure.player.height == ""
                enclosure.player.height = nil
              end
              if enclosure.player.width == ""
                enclosure.player.width = nil
              end
            end
            if enclosure.credits.nil? || enclosure.credits.size == 0
              enclosure.credits = []
              for credit in XPath.match(media_group, "media:credit")
                enclosure.credits << EnclosureCredit.new(
                  FeedTools.unescape_entities(credit.text),
                  FeedTools.unescape_entities(credit.attributes["role"].to_s.downcase)
                )
                if enclosure.credits.last.role == ""
                  enclosure.credits.last.role = nil
                end
              end
            end
            if enclosure.explicit?.nil?
              enclosure.explicit = (XPath.first(media_group,
                "media:adult/text()").to_s.downcase == "true") ? true : false
            end
            if enclosure.text.nil? &&
                XPath.first(media_group, "media:text/text()").to_s != ""
              enclosure.text = FeedTools.sanitize_html(FeedTools.unescape_entities(
                XPath.first(media_group, "media:text/text()").to_s), :strip)
            end
          end
          
          # Keep track of the media groups
          media_groups << affected_enclosures
        end
        
        # Now we need to inherit any relevant item level information.
        if self.explicit?
          for enclosure in @enclosures
            enclosure.explicit = true
          end
        end
        
        # Add all the itunes categories
        for itunes_category in XPath.match(root_node, "itunes:category")
          genre = "Podcasts"
          category = itunes_category.attributes["text"].to_s
          subcategory = XPath.first(itunes_category, "itunes:category/@text").to_s
          category_path = genre
          if category != ""
            category_path << "/" + category
          end
          if subcategory != ""
            category_path << "/" + subcategory
          end          
          for enclosure in @enclosures
            if enclosure.categories.nil?
              enclosure.categories = []
            end
            enclosure.categories << EnclosureCategory.new(
              FeedTools.unescape_entities(category_path),
              FeedTools.unescape_entities("http://www.apple.com/itunes/store/"),
              FeedTools.unescape_entities("iTunes Music Store Categories")
            )
          end
        end

        for enclosure in @enclosures
          # Clean up any of those attributes that incorrectly have ""
          # or 0 as their values        
          if enclosure.type == ""
            enclosure.type = nil
          end
          if enclosure.file_size == 0
            enclosure.file_size = nil
          end
          if enclosure.duration == 0
            enclosure.duration = nil
          end
          if enclosure.height == 0
            enclosure.height = nil
          end
          if enclosure.width == 0
            enclosure.width = nil
          end
          if enclosure.bitrate == 0
            enclosure.bitrate = nil
          end
          if enclosure.framerate == 0
            enclosure.framerate = nil
          end
          if enclosure.expression == "" || enclosure.expression.nil?
            enclosure.expression = "full"
          end

          # If an enclosure is missing the text field, fall back on the itunes:summary field
          if enclosure.text.nil? || enclosure.text = ""
            enclosure.text = self.itunes_summary
          end

          # Make sure we don't have duplicate categories
          unless enclosure.categories.nil?
            enclosure.categories.uniq!
          end
        end
        
        # And finally, now things get complicated.  This is where we make
        # sure that the enclosures method only returns either default
        # enclosures or enclosures with only one version.  Any enclosures
        # that are wrapped in a media:group will be placed in the appropriate
        # versions field.
        affected_enclosure_urls = []
        for media_group in media_groups
          affected_enclosure_urls =
            affected_enclosure_urls | (media_group.map do |enclosure|
              enclosure.url
            end)
        end
        @enclosures.delete_if do |enclosure|
          (affected_enclosure_urls.include? enclosure.url)
        end
        for media_group in media_groups
          default_enclosure = nil
          for enclosure in media_group
            if enclosure.is_default?
              default_enclosure = enclosure
            end
          end
          for enclosure in media_group
            enclosure.default_version = default_enclosure
            enclosure.versions = media_group.clone
            enclosure.versions.delete(enclosure)
          end
          @enclosures << default_enclosure
        end
      end

      # If we have a single enclosure, it's safe to inherit the itunes:duration field
      # if it's missing.
      if @enclosures.size == 1
        if @enclosures.first.duration.nil? || @enclosures.first.duration == 0
          @enclosures.first.duration = self.itunes_duration
        end
      end

      return @enclosures
    end
    
    def enclosures=(new_enclosures)
      @enclosures = new_enclosures
    end
    
    # Returns the feed item author
    def author
      if @author.nil?
        @author = FeedTools::Feed::Author.new
        unless root_node.nil?
          author_node = XPath.first(root_node, "author")
          if author_node.nil?
            author_node = XPath.first(root_node, "managingEditor")
          end
          if author_node.nil?
            author_node = XPath.first(root_node, "dc:author")
          end
          if author_node.nil?
            author_node = XPath.first(root_node, "dc:creator")
          end
          if author_node.nil?
            author_node = XPath.first(root_node, "atom:author")
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
    
    # Sets the feed item author
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
          XPath.first(root_node, "dc:publisher/text()").to_s)
        if @publisher.raw == ""
          @publisher.raw = FeedTools.unescape_entities(
            XPath.first(root_node, "webMaster/text()").to_s)
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
    # This inherits from any incorrectly placed channel-level itunes:author
    # elements.  They're actually amazingly common.  People don't read specs.
    def itunes_author
      if @itunes_author.nil?
        @itunes_author = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:author/text()").to_s)
        @itunes_author = feed.itunes_author if @itunes_author == ""
        @itunes_author = nil if @itunes_author == ""
      end
      return @itunes_author
    end

    # Sets the contents of the itunes:author element
    def itunes_author=(new_itunes_author)
      @itunes_author = new_itunes_author
    end        
        
    # Returns the number of seconds that the associated media runs for
    def itunes_duration
      if @itunes_duration.nil?
        raw_duration = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:duration/text()").to_s)
        if raw_duration != ""
          hms = raw_duration.split(":").map { |x| x.to_i }
          if hms.size == 3
            @itunes_duration = hms[0].hour + hms[1].minute + hms[2]
          elsif hms.size == 2
            @itunes_duration = hms[0].minute + hms[1]
          elsif hms.size == 1
            @itunes_duration = hms[0]
          end
        end
      end
      return @itunes_duration
    end
    
    # Sets the number of seconds that the associate media runs for
    def itunes_duration=(new_itunes_duration)
      @itunes_duration = new_itunes_duration
    end
    
    # Returns the feed item time
    def time
      if @time.nil?
        unless root_node.nil?
          time_string = XPath.first(root_node, "pubDate/text()").to_s
          if time_string == ""
            time_string = XPath.first(root_node, "dc:date/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(root_node, "issued/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(root_node, "updated/text()").to_s
          end
          if time_string == ""
            time_string = XPath.first(root_node, "time/text()").to_s
          end
        end
        if time_string != nil && time_string != ""
          @time = Time.parse(time_string) rescue Time.now
        elsif time_string == nil
          @time = Time.now
        end
      end
      return @time
    end
    
    # Sets the feed item time
    def time=(new_time)
      @time = new_time
    end

    # Returns the feed item updated time
    def updated
      if @updated.nil?
        unless root_node.nil?
          updated_string = XPath.first(root_node, "updated/text()").to_s
          if updated_string == ""
            updated_string = XPath.first(root_node, "modified/text()").to_s
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
        unless root_node.nil?
          issued_string = XPath.first(root_node, "issued/text()").to_s
          if issued_string == ""
            issued_string = XPath.first(root_node, "published/text()").to_s
          end
          if issued_string == ""
            issued_string = XPath.first(root_node, "pubDate/text()").to_s
          end
          if issued_string == ""
            issued_string = XPath.first(root_node, "dc:date/text()").to_s
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
        
    # Returns the url for posting comments
    def comments
      if @comments.nil?
        @comments = FeedTools.normalize_url(
          XPath.first(root_node, "comments/text()").to_s)
        @comments = nil if @comments == ""
      end
      return @comments
    end
    
    # Sets the url for posting comments
    def comments=(new_comments)
      @comments = new_comments
    end
    
    # The source that this post was based on
    def source
      if @source.nil?
        @source = FeedTools::Feed::Link.new
        @source.url = XPath.first(root_node, "source/@url").to_s
        @source.url = nil if @source.url == ""
        @source.value = XPath.first(root_node, "source/text()").to_s
        @source.value = nil if @source.value == ""
      end
      return @source
    end
        
    # Returns the feed item tags
    def tags
      # TODO: support the rel="tag" microformat
      # =======================================
      if @tags.nil?
        @tags = []
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = XPath.match(root_node, "dc:subject/rdf:Bag/rdf:li/text()")
          if tag_list.size > 1
            for tag in tag_list
              @tags << tag.to_s.downcase.strip
            end
          end
        end
        if @tags.nil? || @tags.size == 0
          # messy effort to find ourselves some tags, mainly for del.icio.us
          @tags = []
          rdf_bag = XPath.match(root_node, "taxo:topics/rdf:Bag/rdf:li")
          if rdf_bag != nil && rdf_bag.size > 0
            for tag_node in rdf_bag
              begin
                tag_url = XPath.first(root_node, "@resource").to_s
                tag_match = tag_url.scan(/\/(tag|tags)\/(\w+)/)
                if tag_match.size > 0
                  @tags << tag_match.first.last.downcase.strip
                end
              rescue
              end
            end
          end
        end
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = XPath.match(root_node, "category/text()")
          for tag in tag_list
            @tags << tag.to_s.downcase.strip
          end
        end
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = XPath.match(root_node, "dc:subject/text()")
          for tag in tag_list
            @tags << tag.to_s.downcase.strip
          end
        end
        if @tags.nil? || @tags.size == 0
          begin
            @tags = XPath.first(root_node, "itunes:keywords/text()").to_s.downcase.split(" ")
          rescue
            @tags = []
          end
        end
        if @tags.nil?
          @tags = []
        end
        @tags.uniq!
      end
      return @tags
    end
    
    # Sets the feed item tags
    def tags=(new_tags)
      @tags = new_tags
    end
    
    # Returns true if this feed item contains explicit material.  If the whole
    # feed has been marked as explicit, this will return true even if the item
    # isn't explicitly marked as explicit.
    def explicit?
      if @explicit.nil?
        if XPath.first(root_node,
              "media:adult/text()").to_s.downcase == "true" ||
            XPath.first(root_node,
              "itunes:explicit/text()").to_s.downcase == "yes" ||
            XPath.first(root_node,
              "itunes:explicit/text()").to_s.downcase == "true" ||
            feed.explicit?
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
    
    # A hook method that is called during the feed generation process.  Overriding this method
    # will enable additional content to be inserted into the feed.
    def build_xml_hook(feed_type, version, xml_builder)
      return nil
    end

    # Generates xml based on the content of the feed item
    def build_xml(feed_type=(self.feed.feed_type or "rss"), version=nil,
        xml_builder=Builder::XmlMarkup.new(:indent => 2))
      if feed_type == "rss" && (version == nil || version == 0.0)
        version = 1.0
      elsif feed_type == "atom" && (version == nil || version == 0.0)
        version = 0.3
      end
      if feed_type == "rss" && (version == 0.9 || version == 1.0 || version == 1.1)
        # RDF-based rss format
        if link.nil?
          raise "Cannot generate an rdf-based feed item with a nil link field."
        end
        return xml_builder.item("rdf:about" => CGI.escapeHTML(link)) do
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
          unless description.nil? || description == ""
            xml_builder.description(description)
          else
            xml_builder.description
          end
          unless time.nil?
            xml_builder.tag!("dc:date", time.iso8601)            
          end
          unless tags.nil? || tags.size == 0
            xml_builder.tag!("taxo:topics") do
              xml_builder.tag!("rdf:Bag") do
                for tag in tags
                  xml_builder.tag!("rdf:li", tag)
                end
              end
            end
            xml_builder.tag!("itunes:keywords", tags.join(" "))
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      elsif feed_type == "rss"
        # normal rss format
        return xml_builder.item do
          unless title.nil? || title == ""
            xml_builder.title(title)
          end
          unless link.nil? || link == ""
            xml_builder.link(link)
          end
          unless description.nil? || description == ""
            xml_builder.description(description)
          end
          unless time.nil?
            xml_builder.pubDate(time.rfc822)            
          end
          unless tags.nil? || tags.size == 0
            xml_builder.tag!("taxo:topics") do
              xml_builder.tag!("rdf:Bag") do
                for tag in tags
                  xml_builder.tag!("rdf:li", tag)
                end
              end
            end
            xml_builder.tag!("itunes:keywords", tags.join(" "))
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      elsif feed_type == "atom" && version == 0.3
        # normal atom format
        return xml_builder.entry("xmlns" => "http://purl.org/atom/ns#") do
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
            xml_builder.content(description,
                "mode" => "escaped",
                "type" => "text/html")            
          end
          unless time.nil?
            xml_builder.issued(time.iso8601)            
          end
          unless tags.nil? || tags.size == 0
            for tag in tags
              xml_builder.category(tag)
            end
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      elsif feed_type == "atom" && version == 1.0
        # normal atom format
        return xml_builder.entry("xmlns" => "http://www.w3.org/2005/Atom") do
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
          unless link.nil? || link == ""
            xml_builder.link("href" => link,
                "rel" => "alternate",
                "type" => "text/html",
                "title" => title)
          end
          unless description.nil? || description == ""
            xml_builder.content(description,
                "type" => "html")
          else
            xml_builder.content(FeedTools.no_content_string,
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
          if self.id != nil
            unless FeedTools.is_uri? self.id
              if self.time != nil && self.link != nil
                xml_builder.id(FeedTools.build_tag_uri(self.link, self.time))
              elsif self.link != nil
                xml_builder.id(FeedTools.build_urn_uuid_uri(self.link))
              else
                raise "The unique id must be a URI. " +
                  "(Attempted to generate id, but failed.)"
              end
            else
              xml_builder.id(self.id)
            end
          elsif self.time != nil && self.link != nil
            xml_builder.id(FeedTools.build_tag_uri(self.link, self.time))
          else
            raise "Cannot build feed, missing feed unique id."
          end
          unless self.tags.nil? || self.tags.size == 0
            for tag in self.tags
              xml_builder.category("term" => tag)
            end
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      end
    end
    
    alias_method :tagline, :description
    alias_method :tagline=, :description=
    alias_method :subtitle, :description
    alias_method :subtitle=, :description=
    alias_method :summary, :description
    alias_method :summary=, :description=
    alias_method :abstract, :description
    alias_method :abstract=, :description=
    alias_method :content, :description
    alias_method :content=, :description=
    alias_method :guid, :id
    alias_method :guid=, :id=
    alias_method :published, :issued
    alias_method :published=, :issued=
    
    # Returns a simple representation of the feed item object's state.
    def inspect
      return "#<FeedTools::FeedItem:0x#{self.object_id.to_s(16)} " +
        "LINK:#{self.link}>"
    end
  end
end