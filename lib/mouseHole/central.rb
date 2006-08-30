require 'ftools'
require 'mouseHole/page'

module MouseHole

  class Central

    attr_accessor :sandbox, :options

    def initialize(server, options)
      @server, @options = server, options

      # add MouseHole hosts entries
      DOMAINS.each do |domain|
        HOSTS[domain] = "#{ options.host }:#{ options.port }"
      end

      # user-specific directories and utilities
      @etags, @apps, @sandbox = {}, {}, {}
      @working_dir = options.working_dir
      @dir = options.mouse_dir
      File.makedirs( @dir )
      @started = Time.now

      # connect to the database, get some data
      ActiveRecord::Base.establish_connection options.database
      ActiveRecord::Base.logger = Logger.new(STDOUT)
      MouseHole.create
      # load_conf

      # read user apps on startup
      @last_refresh = Time.now
      @min_interval = 5.seconds
      load_all_apps :force
    end

    def load_all_apps action = nil
      apps = @apps.keys + Dir["#{ @dir }/*.rb"].map { |rb| File.basename(rb) }
      apps.uniq!

      apps.each do |rb|
        path = File.join(@dir, rb)
        unless File.exists? path
          @apps.delete(rb) 
          next
        end
        unless action == :force
          next if @apps[rb] and File.mtime(path) <= @apps[rb].mtime
        end
        load_app rb
      end
    end

    def load_app rb
      if @apps.has_key? rb
        @apps[rb].unload
      end
      path = File.join(@dir, rb)
      app = @apps[rb] = App.load(@server, rb, path)
      app.mtime = Time.now
      app
    end

    def refresh_apps
      return if Time.now - @last_refresh < @min_interval
      load_all_apps
    end

    def find_rewrites page
      refresh_apps
      @apps.values.find_all do |app|
        app.rewrites? page
      end
    end

    def rewrite(page, resin)
      apps = find_rewrites(page)
      return false if apps.empty?

      if page.decode(resin)
        apps.each do |app|
          app.do_rewrite(page)
        end
      end
      true
    end
   
    def app_list
      refresh_apps
      @apps.values
    end

    def find_app name
      @apps[name]
    end

    def doorblocks
      app_list.inject([]) do |ary, app|
        app.doorblock_classes.each do |k|
          ary << [app, k]
        end
        ary
      end
    end

  end

end
