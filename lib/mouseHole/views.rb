require 'redcloth'

module MouseHole::Views

  def doorway(meth)
    html do
      head do
        title "MouseHole"
        link :href => R(AppsRss), :title => 'Apps RSS', 
          :rel => 'alternate', :type => 'application/rss+xml'
        link :href => R(MountsRss), :title => 'Apps (Mounts Only) RSS', 
          :rel => 'alternate', :type => 'application/rss+xml'
        script :type => "text/javascript", :src => R(Static, 'js', 'jquery.js')
        script :type => "text/javascript", :src => R(Static, 'js', 'interface.js')
        script :type => "text/javascript", :src => R(Static, 'js', 'mouseHole.js')
        style "@import '#{R(Static, 'css', 'doorway.css')}';", :type => 'text/css'
      end
      body do
        div.mousehole! do
          img :src => R(Static, 'images', 'doorway.png')
          ul.control do
            li.help { a "about", :href => R(RAbout) }
            li.doorway { a "doorway", :href => R(RIndex) }
            li.apps { a "apps", :href => R(RApps) }
            li.data { a "data", :href => R(RData) }
          end
          div.page! do
            div.send("#{meth}!") do
              send(meth)
            end
            div.footer! do
              strong "feeds: "
              a :href => R(AppsRss) do
                img :src => R(Static, 'icons', 'feed.png')
                text "apps"
              end
              a :href => R(MountsRss) do
                img :src => R(Static, 'icons', 'feed.png')
                text "mounts"
              end
            end
          end
        end
      end
    end
  end

  def block_list blocks
    blocks.each do |app, klass, body|
      li.blocksort :id => "#{MouseHole.token}=#{klass.name}" do
        div.block.send("#{klass.title}") do
          div.title do
            div.actions do
              a.del "hide", :href => "javascript://"
            end
            h1 klass.title
            if app.mount_on
              h2 do
                text "from "
                a app.title, :href => "..#{app.mount_on}"
              end
            else
              h2 "from #{app.title}"
            end
          end
          div.inside do
            self << body
          end
        end
      end
    end
  end

  def index
    div.main do
      if @allblocks.any?
        ol.doorblocks.userpool! do
          block_list @doorblocks
        end
        div.pool do
          ol.doorblocks.fullpool! do
            li "Blocks:"
            block_list @allblocks
          end
        end
      else
        p "None of your installed apps have any doorblocks."
      end
    end
  end

  def about
    div.main do
      red %{
        h1. About %MouseHole 2%

        It's true.  This is the *second* MouseHole.  The first only lasted a few months.  Very experimental.
        Meaning: slow and sloppy.  You now hold the much improved *MouseHole 2*, a personal-sized web server.

        About your installation: You are running %MouseHole #{MouseHole::VERSION}% on top of
        %Ruby #{::RUBY_VERSION}%, built on #{::RUBY_RELEASE_DATE} for the #{::RUBY_PLATFORM} platform.

        h2. Credits

        MouseHole was first conceived by the readers of RedHanded, a blog exploring the fringes of the Ruby
        programming language.  First it was called Hoodlum, then it was called Wonderland.  We traded
        code back and forth and got it hacked together.  
        During the end of "August 2005":http://redhanded.hobix.com/2005/08/.

        Right now, MouseHole is under the care of "why the lucky stiff":http://whytheluckystiff.net/.
        It's a very small operation and you are welcome to come hop aboard!

        The icons included with MouseHole are from the "Silk":http://www.famfamfam.com/lab/icons/silk/
        set by a nice British guy named Mark James.  He even had Ruby kinds. Thankyyouu!!
      }
    end
  end

  def apps
    div.main do
      h1 { "#{span('Your Installed')} Apps" } 
      ul.apps do
        @apps.each do |app|
          li :class => "app-#{app.icon}" do
            if app.broken?
              h2.broken { a app.title, :href => R(RApp, app.path) }
              div.description "This app is broken."
            else
              div.title do
                h2 { a app.title, :href => R(RApp, app.path) }
                if app.mount_on
                  div.mount do
                    "mounted on:" + br +
                      a(app.mount_on, :href => "..#{app.mount_on}")
                  end
                end
              end
              blocks = app.doorblocks
              unless blocks.blank?
                div.blocks {
                  strong "Blocks:"
                  blocks.each do |b|
                    text " #{b}"
                  end
                }
              end
              if app.description
                div.description app.summary
              end
            end
          end
        end
      end
    end
  end

  def app
    div.main do
      h1 { "#{span(@app.title)} Setup" }
      case @app
      when MouseHole::BrokenApp
        div.description do
          "This app is broken.  The exception causing the problem is listed below:"
        end
        div.exception do
          h2 "#{@app.error.class}"
          self << h3(@app.error.message).gsub(/\n/, '<br />')
          ul.backtrace do
            @app.error.backtrace.each do |bt|
              li "from #{bt}"
            end
          end
        end
      when MouseHole::CampingApp
      when MouseHole::App
        div.config do
          div.description @app.description if @app.description
          ul do
            li do
              input :type => 'checkbox'
              span "Enabled"
            end
          end
        end
        div.rules do
          h2 "Rules"
          select :size => 5 do
            @app.rules.each do |rule|
              option rule
            end
          end
          div.submits do
            input :type => 'button', :value => 'Add...'
            input :type => 'button', :value => 'Remove'
          end
        end
      end
      p "Originally installed by hand."
    end
  end

  def data
    div.main do
      h1 { 'Data ' + span('Viewer') } 
      p %{Welcome to MouseHole.}
    end
  end

  def red str
    RedCloth.new(str.gsub(/^ +/, '')).to_html
  end

  # RSS feed of all user scripts.  Two good uses of this: your browser can build a bookmark list of all
  # your user scripts from the feed (or) if you share a proxy, you can be informed concerning the user scripts
  # people are installing.
  def server_rss(only = nil)
    @headers['Content-Type'] = 'text/xml'
    rss( @body = "" ) do |c|
      uri = URL('/')
      uri.scheme = "http"

      c.title "MouseHole User Scripts: #{ uri.host }"
      c.link "#{ uri }"
      c.description "A list of user script installed for the MouseHole proxy at #{ uri }"

      c.item do |item|
        item.title "MouseHole"
        item.link "#{ uri }"
        item.guid "#{ uri }"
        item.dc :creator, "MouseHole"
        item.dc :date, @started
        item.description "The primary MouseHole configuration page."
      end

      @apps.each do |app|
        uri = URL(RApp, app.path)
        uri.scheme = "http"

        unless only == :mounts
          c.item do |item|
            item.title "#{ app.title }: Configuration"
            item.link "#{ uri }"
            item.guid "#{ uri }"
            item.dc :creator, "MouseHole"
            item.dc :date, app.mtime
            item.description app.description
          end
        end
        if app.mount_on
          c.item do |item|
            uri.path = app.mount_on
            item.title "#{ app.title }: Mounted at #{ app.mount_on }"
            item.link "#{ uri }"
            item.guid "#{ uri }"
          end
        end
      end
    end
  end

end
