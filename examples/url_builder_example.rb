#!/usr/bin/env ruby
# frozen_string_literal: true

# Example usage of the new UrlBuilder class
# This demonstrates both the new URL building functionality and the existing URL optimization

require_relative '../lib/humata_import'

puts "=== HumataImport UrlBuilder Examples ===\n"

# Example 1: Build Humata submission URLs
puts "1. Building Humata submission URLs:"
puts "   Default domain: #{HumataImport::Utils::UrlBuilder::DEFAULT_DOMAIN}"

file_id = "1P46B9iPFw93kUmsAVJcKBtCgPRVjOk8S"
file_name = "technical_documentation.pdf"
mime_type = "application/pdf"

humata_url = HumataImport::Utils::UrlBuilder.build_humata_url(file_id, file_name, mime_type)
puts "   File ID: #{file_id}"
puts "   File Name: #{file_name}"
puts "   MIME Type: #{mime_type}"
puts "   Built URL: #{humata_url}"
puts

# Example 2: Custom domain
puts "2. Custom domain example:"
custom_domain = "https://custom-resource.example.com"
custom_url = HumataImport::Utils::UrlBuilder.build_humata_url(file_id, file_name, mime_type, domain: custom_domain)
puts "   Custom Domain: #{custom_domain}"
puts "   Built URL: #{custom_url}"
puts

# Example 3: URL optimization (existing functionality)
puts "3. URL optimization (existing functionality):"
gdrive_url = "https://drive.google.com/file/d/#{file_id}/view?usp=sharing&edit=true#section1"
optimized_url = HumataImport::Utils::UrlBuilder.optimize_for_humata(gdrive_url)
puts "   Original Google Drive URL: #{gdrive_url}"
puts "   Optimized URL: #{optimized_url}"
puts

# Example 4: File ID extraction
puts "4. File ID extraction:"
extracted_id = HumataImport::Utils::UrlBuilder.extract_file_id(gdrive_url)
puts "   Extracted File ID: #{extracted_id}"
puts

# Example 5: Integration example
puts "5. Integration example - building Humata URL from Google Drive URL:"
puts "   Step 1: Extract file ID from Google Drive URL"
puts "   Step 2: Build Humata submission URL"
puts "   Result: #{HumataImport::Utils::UrlBuilder.build_humata_url(extracted_id, file_name, mime_type)}"
puts

puts "=== End Examples ==="
