#
# kevin ballard's proof-of-concept for a google ping of mouseHole
# modified by why to count hits, simplified register_uri
#
MouseHole.script do
  # declaration
  name "Rewriting Test"
  namespace "kevin@sb.org"
  description "Tests the new rewriting stuff."
  include_match :scheme => 'http', :host => %r{^(www\.)?google\.com$}, :path => %r{^(/(index\.html)?)?$}
  version "0.2"
  
  rewrite do |req, res|
    document.elements['//head'].add_element 'script', 'type' => 'text/javascript', 'src' => reg('test.js')
    lucky = document.elements['//input[@name="btnI"]']
    lucky.parent.add_element 'input', 'type' => 'submit', 'value' => 'Random', 'onclick' => 'pingMouseHole(); return false;'
  end
  
  register_uri "test.js" do |uri, req, res|
    res['Content-Type'] = 'text/javascript'
    res.body = <<-EOF
function createRequestObject() {
  var ro;
  var browser = navigator.appName;
  if(browser == "Microsoft Internet Explorer"){
    ro = new ActiveXObject("Microsoft.XMLHTTP");
  }else{
    ro = new XMLHttpRequest();
  }
  return ro;
}

var http = createRequestObject();

function sndReq(action, handler) {
  http.open('get', action);
  http.onreadystatechange = function() {
    if(http.readyState == 4){
      handler(http.responseText);
    }
  };
  http.send(null);
}

(function () {
  sndReq('#{ reg 'ping' }', function(txt) {
    alert(txt);
  })
})();
    EOF
  end
  
  register_uri "ping" do
    host = request.request_uri.host
    @counter ||= {}
    @counter[host] ||= 0
    @counter[host] += 1
    response['Content-Type'] = 'text/plain'
    response.body = "You've hit #{ request.request_uri.host } #{ @counter[host] } times"
  end
end
