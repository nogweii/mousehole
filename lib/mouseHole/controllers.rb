module MouseHole::Controllers

  class RIndex < R '/'
    def get
      @doorblocks = 
        MouseHole::CENTRAL.doorblocks.map do |app, b|
          controller = b.new(nil, @env, @method)
          controller.instance_variable_set("@app", app)
          controller.service
          [app, b, controller.body.to_s]
        end
      doorway :index
    end
  end

  class RAbout < R '/about'
    def get
      doorway :about
    end
  end

  class RApps < R '/apps'
    def get
      @apps = MouseHole::CENTRAL.app_list.sort_by { |app| app.name }
      doorway :apps
    end
  end

  class RData < R '/data'
    def get
      doorway :data
    end
  end

  class RApp < R '/app/(.+)'
    def get(name)
      @app = MouseHole::CENTRAL.find_app name
      if @app
        doorway :app
      else
        r(404, 'Not Found')
      end
    end
  end

  class AppsRss < R '/apps.rss'
    def get
      @apps = MouseHole::CENTRAL.app_list.sort_by { |app| app.name }
      server_rss
    end
  end

  class MountsRss < R '/mounts.rss'
    def get
      @apps = MouseHole::CENTRAL.app_list.sort_by { |app| app.name }
      server_rss :mounts
    end
  end

  class Static < R '/static/(css|js|icons|images)/(.+)'
    MIME_TYPES = {'.css' => 'text/css', '.js' => 'text/javascript', '.png' => 'image/png'}
    def get(dir, path)
      @headers['Content-Type'] = MIME_TYPES[path[/\.\w+$/, 0]] || "text/plain"
      @headers['X-Sendfile'] = File.join(File.expand_path('../../../static', __FILE__), dir, path)
    end
  end
  
end
