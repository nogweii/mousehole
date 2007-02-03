#!/usr/bin/env ruby
#

require 'test/unit'
require 'ostruct'
require 'rubygems'
require 'mouseHole'
require 'mongrel'
require 'mongrel/camping'
require 'net/http'
require 'uri'
require 'timeout'

options = Camping::H[]
options.logger = Logger.new STDOUT
options.logger.level = Logger::INFO
options.database ||= {:adapter => 'sqlite3', :database => 'mh_test.db'}

$address = ['127.0.0.1', 9998]
$server = Mongrel::HttpServer.new(*$address)
MouseHole::CENTRAL = MouseHole::Central.new($server, options)

class TestProxy < Test::Unit::TestCase
  def setup
    @client = Net::HTTP.new(*$address)
    $server.run
  end
  
  def teardown
  end
  
  def test_doorway
    doorway = Mongrel::Camping::CampingHandler.new(MouseHole)
    $server.register("/doorway", doorway)
    sleep(1)
    
    res = @client.request_get('/doorway')
    assert res != nil, "Didn't get a response"
    assert res.body =~ /MouseHole/, "Couldn't find doorway"
  end
  
  def test_proxy
    $server.register('http:', MouseHole::ProxyHandler.new(MouseHole::CENTRAL))
    $server.register('/', Mongrel::Camping::CampingHandler.new(MouseHole))
    sleep(1)
    
    def lagado_test(klass)
      res = klass.get_response(URI.parse('http://www.lagado.com/proxy-test'))
      assert res != nil, "Didn't get a response"
      res
    end

    res = lagado_test(Net::HTTP)
    assert res.body =~ /NOT to have come via a proxy/, "Non-proxy didn't work as expected"
    
    res = lagado_test(Net::HTTP::Proxy(*$address))
    assert res.body =~ /This request appears to have come via a proxy/, "Proxy didn't work"
  end
end