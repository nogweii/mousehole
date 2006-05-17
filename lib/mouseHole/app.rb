module MouseHole
class App

    include REXML
    include Converters

    METADATA = [:name, :namespace, :description, :version, :rules, :accept]

    attr_reader :token
    attr_accessor :document, :path, :mount_on, :mtime, :active,
        :install_uri, :registered_uris, :klass, :model, :app_style,
        *METADATA

    def initialize
        yield self
        @accept ||= HTML
    end

    def rewrites? page
        if @rules
            rule = @rules.detect { |rule| rule.match_uri(page.location) }
            return false unless rule and rule.action == :rewrite
            @accept == page.converter
        end
    end

    def do_rewrite(page)
        @document = page.document
        rewrite(page)
    end

    def doorblocks
        if @klass
            k = Object.const_get(@klass)
            if k.const_defined? :MouseHole
                k::MouseHole.constants
            end
        end || []
    end

    def doorblock_classes
        doorblocks.map do |b|
            Object.const_get(@klass)::MouseHole.const_get(b)
        end
    end

    def self.load(server, rb, path)
        title = File.basename(rb)[/^(\w+)/,1]

        # Load the application at the toplevel.  We want everything to work as if it was loaded from
        # the commandline by Ruby.
        klass, klass_name = nil, nil
        begin
            eval(File.read(path), TOPLEVEL_BINDING)
            klass_name = Object.constants.grep(/^#{title}$/i)[0]
            klass = Object.const_get(klass_name)
            klass.create if klass.respond_to? :create
        rescue Exception => e
            p e
        end

        return unless klass and klass_name

        # Hook up the general configuration from the object.
        model = Models::App.find_by_script(rb) || Models::App.create(:script => rb)
        if klass.respond_to? :run
            server.uri "/#{title}", :handler => Mongrel::Camping::CampingHandler.new(klass)
        end

        if klass < App
            klass.new do |app|
                METADATA.each do |f|
                    app.send("#{f}=", klass.send("default_#{f}"))
                end
                app.klass = klass_name
                app.app_style = :MouseHole
                app.path = rb
            end
        else
            if klass.const_defined? :MouseHole
                klass::MouseHole.constants.each do |c|
                    klass::MouseHole.const_get(c).class_eval do
                        def method_missing(m, *a, &b)
                          str = m==:render ? markaview(*a, &b):eval("markaby.#{m}(*a, &b)")
                          r(200, str)
                        end
                        include C, Base, Models
                    end
                end
            end
            App.new do |app|
                app.mount_on = "/#{title}"
                app.name = klass_name
                app.klass = klass_name
                app.model = model
                app.app_style = :Camping
                app.path = rb
            end
        end
    end

    def unload
        Object.send :remove_const, @klass
    end

    class << self
        METADATA.each do |f|
            attr_accessor "default_#{f}"
            define_method(f) do |str|
                instance_variable_set("@default_#{f}", str)
            end
        end

        [:url].each do |rt|
            define_method(rt) do |*expr|
                r = const_get(constants.grep(/^#{rt}$/i)[0]).new(*expr)
                (@default_rules ||= []) << r
                r
            end
        end

        def rewrite(*a,&b)
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
    end

end
end
