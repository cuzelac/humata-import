#!/usr/bin/env ruby

require_relative 'lib/humata_import/clients/humata_client'

# Test script using the existing Humata client
class HumataClientTester
  def initialize(api_key)
    @api_key = api_key
    @client = HumataImport::Clients::HumataClient.new(
      api_key: api_key,
      logger: Logger.new($stdout)
    )
  end
  
  def test_upload
    puts "🔍 Testing Humata client upload functionality..."
    puts "API Key: #{@api_key ? "#{@api_key[0..8]}..." : "NOT SET"}"
    puts
    
    begin
      puts "1. Testing file upload with test folder ID..."
      response = @client.upload_file(
        'https://example.com/test.pdf',
        'test-folder-123'
      )
      puts "   ✅ Success: #{response.inspect}"
    rescue HumataImport::Clients::HumataError => e
      puts "   ❌ Error: #{e.message}"
      if e.message.include?('404')
        puts "   🔍 This is a 404 error - likely invalid endpoint or folder ID"
      end
    end
    
    puts
    begin
      puts "2. Testing file status check..."
      response = @client.get_file_status('test-id-123')
      puts "   ✅ Success: #{response.inspect}"
    rescue HumataImport::Clients::HumataError => e
      puts "   ❌ Error: #{e.message}"
      if e.message.include?('404')
        puts "   🔍 This is a 404 error - likely invalid file ID or endpoint"
      end
    end
  end
end

# Main execution
api_key = ARGV[0] || ENV['HUMATA_API_KEY']

unless api_key
  puts "❌ No API key provided. Please provide your Humata API key:"
  puts "   ruby test_humata_client.rb <your-api-key>"
  puts "   or set HUMATA_API_KEY environment variable"
  exit 1
end

tester = HumataClientTester.new(api_key)
tester.test_upload 