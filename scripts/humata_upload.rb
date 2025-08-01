require 'net/http'
require 'uri'
require 'json'
require 'optparse'

options = { verbose: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{$0} --url <file_url> --folder-id <folder_id> [options]"
  opts.on('--url URL', 'The public file URL to import (required)') { |v| options[:url] = v }
  opts.on('--folder-id ID', 'The Humata folder UUID (required)') { |v| options[:folder_id] = v }
  opts.on('-v', '--verbose', 'Output HTTP status code and response body') { options[:verbose] = true }
end

begin
  parser.parse!(ARGV)
rescue OptionParser::ParseError => e
  puts e.message
  puts parser
  exit 1
end

if options[:url].nil? || options[:folder_id].nil?
  puts parser
  exit 1
end

api_key = ENV['HUMATA_API_KEY']
if api_key.nil? || api_key.strip.empty?
  puts "Error: HUMATA_API_KEY environment variable not set."
  exit 1
end

endpoint = "https://app.humata.ai/api/v2/import-url"
uri = URI(endpoint)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

headers = {
  "Authorization" => "Bearer #{api_key}",
  "Content-Type" => "application/json",
  "Accept" => "*/*"
}

body = {
  "url" => options[:url],
  "folder_id" => options[:folder_id]
}

request = Net::HTTP::Post.new(uri.request_uri, headers)
request.body = body.to_json

response = http.request(request)

if options[:verbose]
  puts "Status: #{response.code}"
  puts "Response:"
end
puts response.body