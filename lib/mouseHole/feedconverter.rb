require 'mouseHole/converters'

module MouseHole
module Converters

class Feed < Base
    mime_type "text/xml"
    mime_type "application/xml"
    mime_type "application/atom+xml"

    def self.parse(script, req, res)
        require 'feed_tools'
        FeedTools.feed_cache = nil
        feed = FeedTools::Feed.new
        feed.url = req.request_uri.to_s
        feed.feed_data_type = :xml
        feed.feed_data = res.body
        feed
    end
    def self.output(feed, res)
        res['content-type'] = 'application/xml+atom'
        res.body = feed.build_xml('atom', 1.0)
    end
end

end
end
