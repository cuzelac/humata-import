#!/usr/bin/env ruby
# frozen_string_literal: true

# Humata File Upload Script
#
# This script uploads files to Humata by providing a public URL and folder ID.
# It demonstrates file import functionality using the Humata API v2.
#
# Usage:
#   ruby scripts/humata_upload.rb --url <file_url> --folder-id <folder_id> [options]
#   ruby scripts/humata_upload.rb --url "https://example.com/file.pdf" --folder-id "folder_uuid" --verbose
#
# Options:
#   --url URL           The public file URL to import (required)
#   --folder-id ID      The Humata folder UUID (required)
#   -v, --verbose       Output HTTP status code and response body
#
# Requirements:
#   - HUMATA_API_KEY environment variable must be set
#   - Valid public file URL
#   - Valid Humata folder UUID
#
# Example:
#   export HUMATA_API_KEY="your_api_key_here"
#   ruby scripts/humata_upload.rb --url "https://example.com/document.pdf" --folder-id "abc123-def456"

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