require 'ftools'
require 'mouseHole/page'

module MouseHole
class Central
    attr_accessor :apps, :sandbox, :options

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
        Models.create_schema
        # load_conf

        # read user apps on startup
        Dir["#{ @dir }/*.rb"].each do |rb|
            load_app File.basename(rb)
        end
    end

    def load_app rb
        path = File.join(@dir, rb)
        app = @apps[rb] = App.load(@server, rb, path)
    end

    def rewrites? page
        find_rewrites(page).any?
    end

    def find_rewrites page
        @apps.values.find_all do |app|
            app.rewrites? page
        end
    end

    def rewrite(page)
        find_rewrites(page).each do |app|
            app.do_rewrite(page)
        end
    end

end
end
