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

$proxy_address = ['127.0.0.1', 9998]
$server = Mongrel::HttpServer.new(*$proxy_address)
MouseHole::CENTRAL = MouseHole::Central.new($server, options)

class TestProxy < Test::Unit::TestCase
  def setup
    $server.run

    doorway = Mongrel::Camping::CampingHandler.new(MouseHole)
    $server.register("/doorway", doorway)
    $server.register('http:', MouseHole::ProxyHandler.new(MouseHole::CENTRAL))
    $server.register('/', Mongrel::Camping::CampingHandler.new(MouseHole))
    sleep(1)

    @client = Net::HTTP.new(*$proxy_address)
    @proxy_class = Net::HTTP::Proxy(*$proxy_address)
  end
  
  def teardown
  end
  
  def test_doorway
    res = @client.request_get('/doorway')
    assert res != nil, "Didn't get a response"
    assert res.body =~ /MouseHole/, "Couldn't find doorway"
  end
  
  def test_proxy
    def lagado_test(klass)
      res = klass.get_response(URI.parse('http://www.lagado.com/proxy-test'))
      assert res != nil, "Didn't get a response"
      res
    end

    res = lagado_test(Net::HTTP)
    assert res.body =~ /NOT to have come via a proxy/, "Non-proxy didn't work as expected"
    
    res = lagado_test(Net::HTTP::Proxy(*$proxy_address))
    assert res.body =~ /This request appears to have come via a proxy/, "Proxy didn't work"
  end

  # def test_ssl
  #  # Mongrel does not support SSL
  #  url = "https://javacc.dev.java.net/"
  #  res = @proxy_class.get_response(URI.parse(url))
  #  assert res != nil, "Didn't get a response"
  #end
end
