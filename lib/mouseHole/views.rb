require 'redcloth'

module MouseHole::Views
    def layout
        html do
            head do
                title "MouseHole"
                link :href => '/mouseHole/rss', :title => 'RSS', :rel => 'alternate', :type => 'application/rss+xml'
                style "@import '/static/css/doorway.css';", :type => 'text/css'
            end
            body do
                div.doorway! do
                    img :src => '../static/images/doorway.png'
                    ul.control do
                        li.help { a "about", :href => R(RAbout) }
                        li.doorway { a "doorway", :href => R(RIndex) }
                        li.apps { a "apps", :href => R(RApps) }
                        li.data { a "data", :href => R(RData) }
                    end
                    div.page! do
                        self << yield
                    end
                end
            end
        end
    end
    def index
        div.scripts do
            p %{Welcome to MouseHole.}
            @doorblocks.each do |app, klass, body|
                div.doorblock do
                    div.title do
                        h1 klass.name.gsub(/^(.+)::(\w+)$/, '\2')
                        if app.mount_on
                            h2 do
                                text "from "
                                a app.name, :href => "..#{app.mount_on}"
                            end
                        else
                            h2 "from #{app.name}"
                        end
                    end
                    self << body
                end
            end
        end
    end
    def about
        div.scripts do
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
                During the end of "August 2005":http://redhanded.hobix.com//2005/08/.

                Right now, MouseHole is under the care of "why the lucky stiff":http://whytheluckystiff.net/.
                It's a very small operation and you are welcome to come hop aboard!

                The icons included with MouseHole are from the "Silk":http://www.famfamfam.com/lab/icons/silk/
                set by a nice British guy named Mark James.  He even had Ruby kinds. Thankyyouu!!
            }
        end
    end
    def apps
        div.scripts do
            h1 { self << "<span>Your Installed</span> Apps" } 
            ul do
                @apps.each do |app|
                    li do
                        div.title do
                            a app.name, :href => R(RApp, app.path)
                            if app.mount_on
                                span.mount { a app.mount_on, :href => "..#{app.mount_on}" }
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
                            div.description app.description
                        end
                    end
                end
            end
        end
    end
    def data
        div.scripts do
            h1 { self << "Data <span>Viewer</span>" } 
            p %{Welcome to MouseHole.}
        end
    end
    def red str
        RedCloth.new(str.gsub(/^ +/, '')).to_html
    end
end
