#--
# Copyright (c) 2005 Robert Aman
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

if Object.const_defined?(:FEED_TOOLS_ENV)
  warn("FeedTools may have been loaded improperly.  This may be caused " +
    "by the presence of the RUBYOPT environment variable or by using " +
    "load instead of require.  This can also be caused by missing " +
    "the Iconv library, which is common on Windows.")
end

FEED_TOOLS_ENV = ENV['FEED_TOOLS_ENV'] ||
                 ENV['RAILS_ENV'] ||
                 'production' # :nodoc:

FEED_TOOLS_VERSION = "0.2.15"

FEED_TOOLS_NAMESPACES = {
  "admin" => "http://webns.net/mvcb/",
  "ag" => "http://purl.org/rss/1.0/modules/aggregation/",
  "annotate" => "http://purl.org/rss/1.0/modules/annotate/",
  "atom" => "http://www.w3.org/2005/Atom",
  "audio" => "http://media.tangent.org/rss/1.0/",
  "blogChannel" => "http://backend.userland.com/blogChannelModule",
  "cc" => "http://web.resource.org/cc/",
  "creativeCommons" => "http://backend.userland.com/creativeCommonsRssModule",
  "co" => "http://purl.org/rss/1.0/modules/company",
  "content" => "http://purl.org/rss/1.0/modules/content/",
  "cp" => "http://my.theinfo.org/changed/1.0/rss/",
  "dc" => "http://purl.org/dc/elements/1.1/",
  "dcterms" => "http://purl.org/dc/terms/",
  "email" => "http://purl.org/rss/1.0/modules/email/",
  "ev" => "http://purl.org/rss/1.0/modules/event/",
  "icbm" => "http://postneo.com/icbm/",
  "image" => "http://purl.org/rss/1.0/modules/image/",
  "feedburner" => "http://rssnamespace.org/feedburner/ext/1.0",
  "foaf" => "http://xmlns.com/foaf/0.1/",
  "fm" => "http://freshmeat.net/rss/fm/",
  "itunes" => "http://www.itunes.com/DTDs/Podcast-1.0.dtd",
  "l" => "http://purl.org/rss/1.0/modules/link/",
  "media" => "http://search.yahoo.com/mrss",
  "pingback" => "http://madskills.com/public/xml/rss/module/pingback/",
  "prism" => "http://prismstandard.org/namespaces/1.2/basic/",
  "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
  "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
  "ref" => "http://purl.org/rss/1.0/modules/reference/",
  "reqv" => "http://purl.org/rss/1.0/modules/richequiv/",
  "search" => "http://purl.org/rss/1.0/modules/search/",
  "slash" => "http://purl.org/rss/1.0/modules/slash/",
  "soap" => "http://schemas.xmlsoap.org/soap/envelope/",
  "ss" => "http://purl.org/rss/1.0/modules/servicestatus/",
  "str" => "http://hacks.benhammersley.com/rss/streaming/",
  "sub" => "http://purl.org/rss/1.0/modules/subscription/",
  "sy" => "http://purl.org/rss/1.0/modules/syndication/",
  "taxo" => "http://purl.org/rss/1.0/modules/taxonomy/",
  "thr" => "http://purl.org/rss/1.0/modules/threading/",
  "ti" => "http://purl.org/rss/1.0/modules/textinput/",
  "trackback" => "http://madskills.com/public/xml/rss/module/trackback/",
  "wfw" => "http://wellformedweb.org/CommentAPI/",
  "wiki" => "http://purl.org/rss/1.0/modules/wiki/",
  "xhtml" => "http://www.w3.org/1999/xhtml",
  "xml" => "http://www.w3.org/XML/1998/namespace"
}

begin
  require 'iconv'
rescue LoadError
  warn("The Iconv library does not appear to be installed properly.  " +
    "FeedTools cannot function properly without it.")
  raise
end

require 'builder'

begin
  require 'tidy'
rescue LoadError
  # Ignore the error for now.
end

require 'htree'

require 'net/http'
require 'net/https'
require 'net/ftp'

require 'rexml/document'

require 'uri'
require 'time'
require 'cgi'
require 'pp'
require 'yaml'

require 'feed_tools/feed'
require 'feed_tools/feed_item'

#= feed_tools.rb
#
# FeedTools was designed to be a simple XML feed parser, generator, and translator with a built-in
# caching system.
#
#== Example
#  slashdot_feed = FeedTools::Feed.open('http://www.slashdot.org/index.rss')
#  slashdot_feed.title
#  => "Slashdot"
#  slashdot_feed.description
#  => "News for nerds, stuff that matters"
#  slashdot_feed.link       
#  => "http://slashdot.org/"
#  slashdot_feed.items.first.find_node("slash:hitparade/text()").value
#  => "43,37,28,23,11,3,1"
module FeedTools
  
  @force_tidy_enabled = true
  @tidy_enabled = false
  @feed_cache = nil
  @user_agent = "FeedTools/#{FEED_TOOLS_VERSION} " + 
    "+http://www.sporkmonger.com/projects/feedtools/"
  @no_content_string = "[no description]"
  
  # Error raised when a feed cannot be retrieved    
  class FeedAccessError < StandardError
  end
  
  # Returns the current caching mechanism.
  def FeedTools.feed_cache
    return @feed_cache
  end
  
  # Sets the current caching mechanism.  If set to nil, disables caching.
  #
  # Objects of this class must accept the following messages:
  #  url
  #  url=
  #  title
  #  title=
  #  link
  #  link=
  #  xml_data
  #  xml_data=
  #  etag
  #  etag=
  #  last_modified
  #  last_modified=
  #  save
  #
  # Additionally, the class itself must accept the following messages:
  #  find_by_id
  #  find_by_url
  #  initialize_cache
  #  connected?
  def FeedTools.feed_cache=(new_feed_cache)
    # TODO: ensure that the feed cache class actually does those things.
    # ==================================================================
    @feed_cache = new_feed_cache
  end
    
  # Returns true if FeedTools.feed_cache is not nil and a connection with
  # the cache has been successfully established.  Also returns false if an
  # error is raised while trying to determine the status of the cache.
  def FeedTools.feed_cache_connected?
    begin
      return false if FeedTools.feed_cache.nil?
      return FeedTools.feed_cache.connected?
    rescue
      return false
    end
  end
  
  # Returns the currently used user agent string.
  def FeedTools.user_agent
    return @user_agent
  end
  
  # Sets the user agent string to send in the http headers.
  def FeedTools.user_agent=(new_user_agent)
    @user_agent = new_user_agent
  end

  # Returns the currently used no content string.
  def FeedTools.no_content_string
    return @no_content_string
  end
  
  # Sets the no content string to use when a feed is missing a content element.
  # Used only for xml output.
  def FeedTools.no_content_string=(new_no_content_string)
    @no_content_string = new_no_content_string
  end
  
  # Returns true if the html tidy module can be used.
  #
  # Obviously, you need the tidy gem installed in order to run with html
  # tidy features turned on.
  #
  # This method does a fairly complicated, and probably unnecessarily
  # desperate search for the libtidy library.  If you want this thing to
  # execute fast, the best thing to do is to set Tidy.path ahead of time.
  # If Tidy.path is set, this method doesn't do much.  If it's not set,
  # it will do it's darnedest to find the libtidy library.  If you set
  # the LIBTIDYPATH environment variable to the libtidy library, it should
  # be able to find it.
  #
  # Once the library is located, this method will run much faster.
  def FeedTools.tidy_enabled?
    # This is an override variable to keep tidy from being used even if it
    # is available.
    if @force_tidy_enabled == false
      return false
    end
    if @tidy_enabled.nil? || @tidy_enabled == false
      @tidy_enabled = false
      begin
        require 'tidy'
        if Tidy.path.nil?
          # *Shrug*, just brute force it, I guess.  There's a lot of places
          # this thing might be hiding in, depending on platform and general
          # sanity of the person who installed the thing.  Most of these are
          # probably unlikely, but it's not like checking unlikely locations
          # hurts.  Much.  Especially if you actually find it.
          libtidy_locations = [
            '/usr/local/lib/libtidy.dylib',
            '/opt/local/lib/libtidy.dylib',
            '/usr/lib/libtidy.dylib',
            '/usr/local/lib/tidylib.dylib',
            '/opt/local/lib/tidylib.dylib',
            '/usr/lib/tidylib.dylib',
            '/usr/local/lib/tidy.dylib',
            '/opt/local/lib/tidy.dylib',
            '/usr/lib/tidy.dylib',
            '/usr/local/lib/libtidy.so',
            '/opt/local/lib/libtidy.so',
            '/usr/lib/libtidy.so',
            '/usr/local/lib/tidylib.so',
            '/opt/local/lib/tidylib.so',
            '/usr/lib/tidylib.so',
            '/usr/local/lib/tidy.so',
            '/opt/local/lib/tidy.so',
            '/usr/lib/tidy.so',
            'C:\Program Files\Tidy\tidy.dll',
            'C:\Tidy\tidy.dll',
            'C:\Ruby\bin\tidy.dll',
            'C:\Ruby\tidy.dll',
            '/usr/local/lib',
            '/opt/local/lib',
            '/usr/lib'
          ]
          # We just made this thing up, but if someone sets it, we'll
          # go ahead and check it
          unless ENV['LIBTIDYPATH'].nil?
            libtidy_locations =
              libtidy_locations.reverse.push(ENV['LIBTIDYPATH'])
          end
          for path in libtidy_locations
            if File.exists? path
              if File.ftype(path) == "file"
                Tidy.path = path
                @tidy_enabled = true
                break
              elsif File.ftype(path) == "directory"
                # Ok, now perhaps we're getting a bit more desperate
                lib_paths =
                  `find #{path} -name '*tidy*' | grep '\\.\\(so\\|dylib\\)$'`
                # If there's more than one, grab the first one and
                # hope for the best, and if it doesn't work, then blame the
                # user for not specifying more accurately.
                tidy_path = lib_paths.split("\n").first
                unless tidy_path.nil?
                  Tidy.path = tidy_path
                  @tidy_enabled = true
                  break
                end
              end
            end
          end
          # Still couldn't find it.
          unless @tidy_enabled
            @tidy_enabled = false
          end
        else
          @tidy_enabled = true
        end
      rescue LoadError
        # Tidy not installed, disable features that rely on tidy.
        @tidy_enabled = false
      end
    end
    return @tidy_enabled
  end
  
  # Turns html tidy support on or off.  Be aware, that setting this to true
  # does not mean tidy will be enabled.  It simply means that tidy will be
  # enabled if it is available to be enabled.
  def FeedTools.tidy_enabled=(new_tidy_enabled)
    @force_tidy_enabled = new_tidy_enabled
  end

  # Attempts to ensures that the passed url is valid and sane.  Accepts very, very ugly urls
  # and makes every effort to figure out what it was supposed to be.  Also translates from
  # the feed: and rss: pseudo-protocols to the http: protocol.
  def FeedTools.normalize_url(url)
    if url.nil? || url == ""
      return nil
    end
    normalized_url = url.strip
    
    # if a url begins with the '/' character, it only makes sense that they
    # meant to be using a file:// url.  Fix it for them.
    if normalized_url.length > 0 && normalized_url[0..0] == "/"
      normalized_url = "file://" + normalized_url
    end
    
    # if a url begins with javascript:, it's quite possibly an attempt at
    # doing something malicious.  Let's keep that from getting anywhere,
    # shall we?
    if (normalized_url.downcase =~ /javascript:/) != nil
      return "#"
    end
    
    # deal with all of the many ugly possibilities involved in the rss:
    # and feed: pseudo-protocols (incidentally, whose crazy idea was this
    # mess?)
    normalized_url.gsub!(/^http:\/*(feed:\/*)?/, "http://")
    normalized_url.gsub!(/^http:\/*(rss:\/*)?/, "http://")
    normalized_url.gsub!(/^feed:\/*(http:\/*)?/, "http://")
    normalized_url.gsub!(/^rss:\/*(http:\/*)?/, "http://")
    normalized_url.gsub!(/^file:\/*/, "file:///")
    normalized_url.gsub!(/^https:\/*/, "https://")
    # fix (very) bad urls (usually of the user-entered sort)
    normalized_url.gsub!(/^http:\/*(http:\/*)*/, "http://")
    if (normalized_url =~ /^file:/) == 0
      # fix bad Windows-based entries
      normalized_url.gsub!(/file:\/\/\/([a-zA-Z]):/, 'file:///\1|')

      # maybe this is too aggressive?
      normalized_url.gsub!(/\\/, '/')
      return normalized_url
    else
      if (normalized_url =~ /https?:\/\//) == nil
        normalized_url = "http://" + normalized_url
      end
      if normalized_url == "http://"
        return nil
      end
      begin
        feed_uri = URI.parse(normalized_url)
        if feed_uri.scheme == nil
          feed_uri.scheme = "http"
        end
        if feed_uri.path == nil || feed_uri.path == ""
          feed_uri.path = "/"
        end
        if (feed_uri.path =~ /^[\/]+/) == 0
          feed_uri.path.gsub!(/^[\/]+/, "/")
        end
        feed_uri.host.downcase!
        return feed_uri.to_s
      rescue URI::InvalidURIError
        return normalized_url
      end
    end
  end
  
  # Converts a url into a tag uri
  def FeedTools.build_tag_uri(url, date)
    unless url.kind_of? String
      raise ArgumentError, "Expected String, got #{url.class.name}"
    end
    unless date.kind_of? Time
      raise ArgumentError, "Expected Time, got #{date.class.name}"
    end
    tag_uri = normalize_url(url)
    unless FeedTools.is_uri?(tag_uri)
      raise ArgumentError, "Must supply a valid URL."
    end
    host = URI.parse(tag_uri).host
    tag_uri.gsub!(/^(http|ftp|file):\/*/, "")
    tag_uri.gsub!(/#/, "/")
    tag_uri = "tag:#{host},#{date.strftime('%Y-%m-%d')}:" +
      "#{tag_uri[(tag_uri.index(host) + host.size)..-1]}"
    return tag_uri
  end

  # Converts a url into a urn:uuid: uri
  def FeedTools.build_urn_uri(url)
    unless url.kind_of? String
      raise ArgumentError, "Expected String, got #{url.class.name}"
    end
    normalized_url = normalize_url(url)
    require 'uuidtools'
    return UUID.sha1_create(UUID_URL_NAMESPACE, normalized_url).to_uri_string
  end
  
  # Returns true if the parameter appears to be a valid uri
  def FeedTools.is_uri?(url)
    return false if url.nil?
    begin
      uri = URI.parse(url)
      if uri.scheme.nil? || uri.scheme == ""
        return false
      end
    rescue URI::InvalidURIError
      return false
    end
    return true
  end
  
  # Escapes all html entities
  def FeedTools.escape_entities(html)
    return nil if html.nil?
    escaped_html = CGI.escapeHTML(html)
    unescaped_html.gsub!(/'/, "&apos;")
    unescaped_html.gsub!(/"/, "&quot;")
    return escaped_html
  end
  
  # Unescapes all html entities
  def FeedTools.unescape_entities(html)
    return nil if html.nil?
    unescaped_html = html
    unescaped_html.gsub!(/&#x26;/, "&amp;")
    unescaped_html.gsub!(/&#38;/, "&amp;")
    unescaped_html = CGI.unescapeHTML(unescaped_html)
    unescaped_html.gsub!(/&apos;/, "'")
    unescaped_html.gsub!(/&quot;/, "\"")
    return unescaped_html
  end
  
  # Removes all html tags from the html formatted text.
  def FeedTools.strip_html(html)
    return nil if html.nil?
    # TODO: do this properly
    # ======================
    stripped_html = html.gsub(/<\/?[^>]+>/, "")
    return stripped_html
  end

  # Tidys up the html
  def FeedTools.tidy_html(html, options = {})
    return nil if html.nil?
    if FeedTools.tidy_enabled?
      is_fragment = true
      html.gsub!(/&lt;!'/, "&amp;lt;!'")
      if (html.strip =~ /<html>(.|\n)*<body>/) != nil ||
          (html.strip =~ /<\/body>(.|\n)*<\/html>$/) != nil
        is_fragment = false
      end
      if (html.strip =~ /<\?xml(.|\n)*\?>/) != nil
        is_fragment = false
      end
      tidy_html = Tidy.open(:show_warnings=>false) do |tidy|
        tidy.options.output_xml = true
        tidy.options.numeric_entities = true
        tidy.options.markup = true
        tidy.options.indent = false
        tidy.options.wrap_attributes = true
        tidy.options.logical_emphasis = true
        # TODO: Make this match the actual encoding of the feed
        # =====================================================
        tidy.options.char_encoding = "utf8"
        tidy.options.ascii_chars = true
        tidy.options.doctype = "omit"        
        xml = tidy.clean(html)
        xml
      end
      if is_fragment
        # Tidy sticks <html>...<body>[our html]</body>...</html> in.
        # We don't want this.
        tidy_html.strip!
        tidy_html.gsub!(/^<html>(.|\n)*<body>/, "")
        tidy_html.gsub!(/<\/body>(.|\n)*<\/html>$/, "")
        tidy_html.strip!
      end
      tidy_html.gsub!(/&#x26;/, "&amp;")
      tidy_html.gsub!(/&#38;/, "&amp;")
    else
      tidy_html = html
    end
    return tidy_html
  end

  # Removes all dangerous html tags from the html formatted text.
  # If mode is set to :escape, dangerous and unknown elements will
  # be escaped.  If mode is set to :strip, dangerous and unknown
  # elements and all children will be removed entirely.
  # Dangerous or unknown attributes are always removed.
  def FeedTools.sanitize_html(html, mode=:strip)
    return nil if html.nil?
    
    # Lists borrowed from Mark Pilgrim's feedparser
    acceptable_elements = ['a', 'abbr', 'acronym', 'address', 'area', 'b',
      'big', 'blockquote', 'br', 'button', 'caption', 'center', 'cite',
      'code', 'col', 'colgroup', 'dd', 'del', 'dfn', 'dir', 'div', 'dl',
      'dt', 'em', 'fieldset', 'font', 'form', 'h1', 'h2', 'h3', 'h4',
      'h5', 'h6', 'hr', 'i', 'img', 'input', 'ins', 'kbd', 'label', 'legend',
      'li', 'map', 'menu', 'ol', 'optgroup', 'option', 'p', 'pre', 'q', 's',
      'samp', 'select', 'small', 'span', 'strike', 'strong', 'sub', 'sup',
      'table', 'tbody', 'td', 'textarea', 'tfoot', 'th', 'thead', 'tr', 'tt',
      'u', 'ul', 'var']

    acceptable_attributes = ['abbr', 'accept', 'accept-charset', 'accesskey',
      'action', 'align', 'alt', 'axis', 'border', 'cellpadding',
      'cellspacing', 'char', 'charoff', 'charset', 'checked', 'cite', 'class',
      'clear', 'cols', 'colspan', 'color', 'compact', 'coords', 'datetime',
      'dir', 'disabled', 'enctype', 'for', 'frame', 'headers', 'height',
      'href', 'hreflang', 'hspace', 'id', 'ismap', 'label', 'lang',
      'longdesc', 'maxlength', 'media', 'method', 'multiple', 'name',
      'nohref', 'noshade', 'nowrap', 'prompt', 'readonly', 'rel', 'rev',
      'rows', 'rowspan', 'rules', 'scope', 'selected', 'shape', 'size',
      'span', 'src', 'start', 'summary', 'tabindex', 'target', 'title',
      'type', 'usemap', 'valign', 'value', 'vspace', 'width']

    # Replace with appropriate named entities
    html.gsub!(/&#x26;/, "&amp;")
    html.gsub!(/&#38;/, "&amp;")
    html.gsub!(/&lt;!'/, "&amp;lt;!'")
    
    # Hackity hack.  But it works, and it seems plenty fast enough.
    html_doc = HTree.parse_xml("<root>" + html + "</root>").to_rexml
    
    sanitize_node = lambda do |html_node|
      if html_node.respond_to? :children
        for child in html_node.children
          if child.kind_of? REXML::Element
            unless acceptable_elements.include? child.name
              if mode == :strip
                html_node.delete_element(child)
              else
                new_child = REXML::Text.new(CGI.escapeHTML(child.to_s))
                html_node.insert_after(child, new_child)
                html_node.delete_element(child)
              end
            end
            for attribute in child.attributes.keys
              unless acceptable_attributes.include? attribute
                child.delete_attribute(attribute)
              end
            end
          end
          sanitize_node.call(child)
        end
      end
      html_node
    end
    sanitize_node.call(html_doc.root)
    html = html_doc.root.inner_xml
    return html
  end
  
  # Creates a merged "planet" feed from a set of urls.
  def FeedTools.build_merged_feed(url_array)
    return nil if url_array.nil?
    merged_feed = Feed.new
    retrieved_feeds = []
    feed_threads = []
    url_array.each do |feed_url|
      feed_threads << Thread.new do
        feed = Feed.open(feed_url)
        retrieved_feeds << feed
      end
    end
    feed_threads.each do |thread|
      thread.join
    end
    retrieved_feeds.each do |feed|
      merged_feed.entries.concat(
        feed.entries.collect do |entry|
          entry.title = "#{feed.title}: #{entry.title}"
          entry
        end )
    end
    return merged_feed
  end
end

module REXML # :nodoc:
  class Element # :nodoc:
    unless REXML::Element.public_instance_methods.include? :inner_xml
      def inner_xml # :nodoc:
        result = ""
        self.each_child do |child|
          result << child.to_s
        end
        return result
      end
    end
    
    unless REXML::Element.public_instance_methods.include? :base_uri
      def base_uri # :nodoc:
        if not attribute('xml:base')
          return parent.base_uri
        elsif parent
          return URI.join(parent.base_uri, attribute('xml:base').value).to_s
        else
          return (attribute('xml:base').value or '')
        end
      end
    end
  end
end

begin
  unless FeedTools.feed_cache.nil?
    FeedTools.feed_cache.initialize_cache
  end
rescue
end
