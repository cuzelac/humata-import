require 'net/http'
require 'uri'
require 'json'
require 'optparse'

options = { verbose: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{$0} <pdf_id> [options]"
  opts.on('-v', '--verbose', 'Output HTTP status code and response body') do
    options[:verbose] = true
  end
end

# Parse options and get the remaining arguments
args = parser.parse!(ARGV)

if args.length != 1
  puts parser
  exit 1
end

pdf_id = args[0]
api_key = ENV['HUMATA_API_KEY']

if api_key.nil? || api_key.strip.empty?
  puts "Error: HUMATA_API_KEY environment variable not set."
  exit 1
end

endpoint = "https://app.humata.ai/api/v1/pdf/#{pdf_id}"

uri = URI(endpoint)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

headers = {
  "Authorization" => "Bearer #{api_key}",
  "Accept" => "*/*"
}

request = Net::HTTP::Get.new(uri.request_uri, headers)

response = http.request(request)

if options[:verbose]
  puts "Status: #{response.code}"
  puts "Response:"
end
puts response.body