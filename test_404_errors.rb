#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

# Test script to diagnose 404 errors with Humata API
class Humata404Tester
  API_BASE_URL = 'https://app.humata.ai'
  
  def initialize(api_key)
    @api_key = api_key
  end
  
  def test_endpoints
    puts "🔍 Testing Humata API endpoints for 404 errors..."
    puts "API Key: #{@api_key ? "#{@api_key[0..8]}..." : "NOT SET"}"
    puts
    
    # Test 1: Upload endpoint
    puts "1. Testing upload endpoint (/api/v2/import-url)..."
    test_upload_endpoint
    
    puts
    puts "2. Testing status endpoint (/api/v1/pdf/{id})..."
    test_status_endpoint
    
    puts
    puts "3. Testing with invalid folder ID..."
    test_invalid_folder
    
    puts
    puts "4. Testing API base URL..."
    test_base_url
  end
  
  private
  
  def test_upload_endpoint
    uri = URI.join(API_BASE_URL, '/api/v2/import-url')
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request.body = {
      url: 'https://example.com/test.pdf',
      folder_id: 'test-folder-123'
    }.to_json
    
    response = make_request(uri, request)
    puts "   Status: #{response.code}"
    puts "   Response: #{response.body[0..200]}..."
  end
  
  def test_status_endpoint
    uri = URI.join(API_BASE_URL, '/api/v1/pdf/test-id-123')
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    
    response = make_request(uri, request)
    puts "   Status: #{response.code}"
    puts "   Response: #{response.body[0..200]}..."
  end
  
  def test_invalid_folder
    uri = URI.join(API_BASE_URL, '/api/v2/import-url')
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request.body = {
      url: 'https://example.com/test.pdf',
      folder_id: 'invalid-folder-id'
    }.to_json
    
    response = make_request(uri, request)
    puts "   Status: #{response.code}"
    puts "   Response: #{response.body[0..200]}..."
  end
  
  def test_base_url
    uri = URI.join(API_BASE_URL, '/')
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    
    response = make_request(uri, request)
    puts "   Status: #{response.code}"
    puts "   Response: #{response.body[0..200]}..."
  end
  
  def make_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    
    begin
      http.request(request)
    rescue => e
      puts "   Error: #{e.message}"
      return nil
    end
  end
end

# Main execution
if ARGV.empty?
  puts "Usage: ruby test_404_errors.rb <your-humata-api-key>"
  puts "Or set HUMATA_API_KEY environment variable"
  exit 1
end

api_key = ARGV[0] || ENV['HUMATA_API_KEY']

unless api_key
  puts "❌ No API key provided. Please provide your Humata API key:"
  puts "   ruby test_404_errors.rb <your-api-key>"
  puts "   or set HUMATA_API_KEY environment variable"
  exit 1
end

tester = Humata404Tester.new(api_key)
tester.test_endpoints 