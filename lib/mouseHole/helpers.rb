module MouseHole::Helpers
    def rss( io )
        feed = Builder::XmlMarkup.new( :target => io, :indent => 2 )
        feed.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
        feed.rss( 'xmlns:admin' => 'http://webns.net/mvcb/',
                  'xmlns:sy' => 'http://purl.org/rss/1.0/modules/syndication/',
                  'xmlns:dc' => 'http://purl.org/dc/elements/1.1/',
                  'xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
                  'version' => '2.0' ) do |rss|
            rss.channel do |c|
                # channel stuffs
                c.dc :language, "en-us" 
                c.dc :creator, "MouseHole #{ MouseHole::VERSION }"
                c.dc :date, Time.now.utc.strftime( "%Y-%m-%dT%H:%M:%S+00:00" )
                c.admin :generatorAgent, "rdf:resource" => "http://builder.rubyforge.org/"
                c.sy :updatePeriod, "hourly"
                c.sy :updateFrequency, 1
                yield c
            end
        end 
    end
end

