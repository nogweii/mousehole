# This is a script written for why's MouseHole (2.0+), the personal web proxy,
# as part of an effort to support "environmentally friendly!" web browsing.
#
# Whenever you visit a site such as slashdot or digg (through your own personal
# MouseHole proxy), this script will rewrite http links to use the Coral Content
# Distribution Network. Thus, it encourages web surfers to be responsible and
# avoid oversaturating the infrastructure of the long tail of the Web. 
#
# ~L
#
# For more information on installing and configuring the MouseHole, see
#   http://code.whytheluckystiff.net/mouseHole
#

class Coral < MouseHole::App
  title 'Coral'
  namespace 'http://www.stanford.edu'
  description "environmentally friendly! web browsing"
  version '1.0'

  + url("http://slashdot.org/*")
  + url("http://*.slashdot.org/*")
  + url("http://reddit.com/*")
  + url("http://*.reddit.com/*")
  + url("http://digg.com/*")
  + url("http://*.digg.com/*")

  # coralize! for more info, see http://www.coralcdn.org/
  #
  def coralize(href)
    begin
      uri = URI(href)
      return href if uri.port != 80
      href.gsub(uri.host, uri.host + '.nyud.net:8080')
    rescue
      href
    end
  end

  def rewrite(page)
    (document/'a[@href]').each do |link|
      # link.attributes['href'] = coralize(link.attributes['href']) # doesn't work!
      link['href'] = coralize(link['href']) # 'tis okay.
    end
  end
end
