require 'mouseHole/converters'

module MouseHole
module Converters

class Feed < Base

  mime_type "text/xml"
  mime_type "application/xml"
  mime_type "application/atom+xml"

  def self.parse(page, body)
    require 'feed_tools'
    FeedTools.feed_cache = nil
    feed = FeedTools::Feed.new
    feed.url = page.location.to_s
    feed.feed_data_type = :xml
    feed.feed_data = body
    feed
  end

  def self.output(feed, page)
    page['content-type'] = 'application/xml+atom'
    page.body = feed.build_xml('atom', 1.0)
  end

end

end
end
