module MouseHole::Controllers
    class RIndex < R '/'
        def get
            render :index
        end
    end
    class RAbout < R '/about'
        def get
            render :about
        end
    end
    class RApps < R '/apps'
        def get
            @apps = MouseHole::CENTRAL.app_list.sort_by { |app| app.name }
            render :apps
        end
    end
    class RData < R '/data'
        def get
            render :data
        end
    end
    class RApp < R '/app/(.+)'
        def get(app)
        end
    end
end
