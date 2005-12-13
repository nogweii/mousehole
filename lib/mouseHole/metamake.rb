class Object
    def metaclass; class << self; self; end; end
    def meta_eval &blk; metaclass.class_eval &blk end
    def meta_def name, &blk
        meta_eval { define_method name, &blk }
    end
    def class_def name, &blk
        class_eval { define_method name, &blk }
    end
end

module MouseHole
    def self.MetaMake(klass, &blk)
        o = klass.new
        o.meta_eval { @__obj = o }
        class << o
            def self.method_missing(m, *args, &blk)
                set_attr(m, *args, &blk)
            end
            def self.set_attr(m, *args, &blk)
                v = @__obj.instance_variable_get("@#{m}")
                if blk
                    unless v.respond_to? :to_hash
                        val = "#{m}_#{WEBrick::Utils::random_string 10}"
                        define_method val, blk
                        blk = @__obj.method( val )
                    end
                    args << nil if args.empty?
                    args << blk 
                end
                if v.respond_to? :to_ary
                    (v = v.to_ary).push args
                elsif v.respond_to? :to_hash
                    val = args.pop
                    args.each do |k|
                        if blk
                            val = "#{m}_#{k.to_s.gsub(/^(.+)::/, '')}"
                            define_method val, blk
                            val = @__obj.method( val )
                        end
                        (v = v.to_hash)[k] = val
                    end
                elsif args.length <= 1
                    v = args.first
                else
                    v = args
                end
                @__obj.instance_variable_set("@#{m}", v)
            end
        end
        o.meta_eval &blk

        # allow instance variables in the class def
        o.metaclass.instance_variables.each do |mv|
            next if mv == "@__obj"
            o.instance_variable_set( mv, o.metaclass.instance_variable_get( mv ) )
        end
        o
    rescue => e
        p [e.class, e.message, e.backtrace]
    end
end
