module MouseHole

  class App

    include REXML
    include Converters
    include LoggerMixin

    METADATA = [:title, :namespace, :description, :version, :rules, :handlers, :accept]

    attr_reader :token
    attr_accessor :document, :path, :mount_on, :mtime, :active,
      :registered_uris, :klass, :model, :app_style,
      *METADATA

    def basic_setup
      @accept ||= HTML
      @token ||= MouseHole.token
    end

    def initialize server, klass_name = nil, model = nil, rb = nil
      klass_name ||= self.class.name
      self.model = model
      self.title = klass_name
      METADATA.each do |f|
        self.send("#{f}=", self.class.send("default_#{f}"))
      end
      self.klass = klass_name
      self.path = rb
      if self.handlers
        self.handlers.each do |h_is, h_name, h_blk|
          next unless h_is == :mount
          server.unregister "/#{h_name}"
          server.register "/#{h_name}", h_blk
        end
      end
      basic_setup
    end

    def install_uri; @model.uri if @model end

    def icon; "ruby_gear" end

    def broken?; false end

    def summary
      s = description[/.{10,100}[.?!\)]+|^.{1,100}(\b|$)/m, 0]
      s += "..." if s =~ /\w$/ and s.length < description.length
      s
    end

    def rewrites? page
      if @rules
        return false unless @accept == page.converter
        rule = @rules.detect { |rule| rule.match_uri(page.location) }
        return false unless rule and rule.action == :rewrite
        true
      end
    end

    def do_rewrite(page)
      @document = page.document
      begin
        rewrite(page)
      rescue Exception => e
        error "[#{self.title}] #{e.class}: #{e.message}"
      end
    end

    def find_handler(opts = {})
      if handlers
        handlers.each do |h_is, h_name, h_blk, h_opts|
          next unless h_is == opts[:is] if opts[:is]
          next unless h_name == opts[:name] if opts[:name]
          next unless h_opts[:on] == opts[:on] if opts[:on]
          return h_blk
        end
      end
    end

    def mount_path(path)
      p = path.to_s.gsub(%r!^/!, '')
      hdlr = find_handler :is => :mount, :name => p, :on => :all
      if hdlr
        "/#@token/#{p}"
      else
        raise MountError, "no `#{path}' mount found on app #{self.class.name}."
      end
    end

    def doorblocks
      if @klass
        k = Object.const_get(@klass)
        if k.const_defined? :MouseHole
          k::MouseHole.constants
        end
      end || []
    end

    def doorblock_get(b)
      Object.const_get(@klass)::MouseHole.const_get(b) rescue nil
    end

    def doorblock_classes
      doorblocks.map do |b|
        doorblock_get(b)
      end
    end

    def self.load(server, rb, path)
      title = File.basename(rb)[/^(\w+)/,1]

      # Load the application at the toplevel.  We want everything to work as if it was loaded from
      # the commandline by Ruby.
      klass, klass_name, source = nil, nil, File.read(path)
      begin
        source.gsub!('__FILE__', "'" + path + "'")
        eval(source, TOPLEVEL_BINDING)
        klass_name = Object.constants.grep(/^#{title}$/i)[0]
        klass = Object.const_get(klass_name)
        klass.create if klass.respond_to? :create
      rescue Exception => e
        warn "Warning, found broken app: '#{title}'"
        return BrokenApp.new(source[/\b#{title}\b/i, 0], rb, e)
      end

      return unless klass and klass_name

      # Hook up the general configuration from the object.
      model = Models::App.find_by_script(rb) || Models::App.create(:script => rb)
      if klass.respond_to? :run
        server.register "/#{title}", Mongrel::Camping::CampingHandler.new(klass)
      end

      if klass < App
        klass.new(server, klass_name, model, rb)
      else
        if klass.const_defined? :MouseHole
          klass::MouseHole.constants.each do |c|
            dk = klass::MouseHole.const_get(c)
            if dk.is_a? Class
              dk.class_eval do
                def self.title
                  name[/::([^:]+?)$/, 1]
                end
                include C, Base, Models
              end
            end
          end
        end
        klass.meta_eval do
          alias_method :__run__, :run
          define_method :run do |*a|
            x = __run__(*a)
            x_is_html = true unless x.respond_to? :headers and x.headers['Content-Type'] != 'text/html'
            if (x.respond_to? :body and not x.body.nil?) and x_is_html
              begin
                doc = Hpricot(x.body)
                (doc/:head).append("<style type='text/css'>@import '/doorway/static/css/mounts.css';</style>")
                (doc/:body).prepend("<div id='mh2'><b><a href='/'>MouseHole</a></b> // You are using <b>#{klass_name}</b> (<a href='/doorway/app/#{rb}'>edit</a>)</div>")
                x.body = doc.to_original_html
              rescue
                warn "Couldn't parse #{x.headers['Location']}" if x.respond_to? :headers
              end
            end
            x
          end
        end
        CampingApp.new(title, klass_name, model, rb)
      end
    end

    def unload(server)
      if @mount_on
        server.unregister @mount_on
      end
      if handlers
        handlers.each do |h_is, h_name, h_blk|
          next unless h_is == :mount
          server.unregister "/#{h_name}"
        end
      end
      if @klass
        Object.send :remove_const, @klass
      end
    end

    class << self
      METADATA.each do |f|
        attr_accessor "default_#{f}"
        define_method(f) do |str|
          instance_variable_set("@default_#{f}", str)
        end
      end

      def mount(path, opts = {}, &b)
        (@default_handlers ||= []) << [:mount, path.to_s.gsub(%r!^/!, ''), MouseHole::MountHandler.new(b), opts]
      end

      [:url].each do |rt|
        define_method(rt) do |*expr|
          r = const_get(constants.grep(/^#{rt}$/i)[0]).new(*expr)
          (@default_rules ||= []) << r
          r
        end
      end

    end

    class Rule
      attr_accessor :expr, :action
      def initialize(*expr)
        @expr = expr
      end
      def -@; @action = :ignore end
      def +@; @action = :rewrite end
    end
    
    class URL < Rule
      def initialize(expr)
        @expr = expr
        @action = :rewrite
      end
      def match_uri(uri)
        if @expr.respond_to? :source
          uri.to_s.match @expr
        elsif @expr.respond_to? :to_str
          uri.to_s.match /^#{ Regexp.quote(@expr).gsub( "\\*", '.*' ) }$/
        elsif @expr.respond_to? :keys
          @expr.detect do |k, v|
            uri.__send__(k) == v
          end
        end
      end
      def to_s
        "#{@action} #{@expr}"
      end
    end

  end

  class CampingApp < App
    def initialize title, klass_name, model, rb
      self.mount_on = "/#{title}"
      self.title = klass_name
      self.klass = klass_name
      self.model = model
      self.path = rb
      basic_setup
    end
    def icon; "ruby" end
  end

  class BrokenApp < App
    def initialize(title, path, e)
      self.title = title
      self.path = path
      self.error = e
      basic_setup
    end
    attr_accessor :error
    def icon; "broken" end
    def broken?; true end
  end

  class MountError < Exception; end

end
