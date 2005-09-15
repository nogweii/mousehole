MouseHole.script do
    # declaration
    name "Comics Alt Text" 
    namespace "http://adamv.com/greases/" 
    description 'Shows the "hover text" for some comics on the page'
    include_match %r!^http://.*achewood\.com/!
    include_match %r!^http://.*qwantz\.com/!
    version "0.2" 

    # instance variables
    @comics = {
        'achewood' => '//img[starts-with(@src, "/comic.php?date=")]',
        'qwantz'   => '//img[starts-with(@src, "/comics/")]'
    }

    # the pages flow through here
    rewrite do |req, res|
        whichSite = case req.request_uri.host
            when /achewood/: "achewood" 
            when /qwantz/: "qwantz" 
        end
        return unless whichSite

        comic = document.elements[@comics[whichSite]]
        return unless comic

        if comic.attributes['title']
            div = Element.new 'div'
            div.attributes['className'] = 'msg'
            div.text = "(#{ comic.attributes['title'] })" 
            comic.parent.insert_after comic, div
        end
    end
end
