# Simple MouseHole 2.0 script, based on the Greasemonkey script
# by Adam Vandenberg.  His is GPL, so this is GPL.
# <http://adamv.com/dev/grease/scripts/comicalt.user.js>
class ComicAlt < MouseHole::App
    title "Comics Alt Text"
    namespace "http://adamv.com/greases/"
    description 'Shows the "hover text" for some comics on the page'
    version "0.3"
    + url("http://achewood.com/*")
    + url("http://*.achewood.com/*")
    + url("http://qwantz.com/*")
    + url("http://*.qwantz.com/*")

    COMICS = {
        "achewood" => 'img[@src^="/comic.php?date="]',
        "qwantz" => 'img[@src^="http://www.qwantz.com/comics/"]'
    }     

    # the pages flow through here
    def rewrite(page)
        whichSite, xpath =
            COMICS.detect do |key,|
                page.location.host.include? key
            end
        return unless whichSite

        comic = document.at(xpath)
        return unless comic

        if comic['title']
          div = Hpricot.make("<div class='msg'>(#{ comic['title'] })</div>")
          comic.parent.insert_after div, comic
        end
    end
end
