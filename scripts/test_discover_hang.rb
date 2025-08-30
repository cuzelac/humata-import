#!/usr/bin/env ruby
# frozen_string_literal: true

# Discover Command Hang Diagnostic Tool
#
# This script diagnoses hanging issues in the discover command by testing
# individual components in isolation with timeout protection.
#
# Usage:
#   ruby scripts/test_discover_hang.rb <gdrive-url> [options]
#   ruby scripts/test_discover_hang.rb "https://drive.google.com/drive/folders/abc123" --timeout 120
#
# Options:
#   --timeout SECONDS    Timeout for authentication tests (default: 60)
#
# What It Tests:
#   1. Environment setup and Ruby configuration
#   2. Database initialization and connectivity
#   3. Google Drive authentication process
#   4. URL parsing and validation
#   5. File listing functionality
#
# Requirements:
#   - GOOGLE_APPLICATION_CREDENTIALS environment variable set
#   - Valid Google Drive folder URL
#   - Ruby dependencies installed via bundler
#
# Example:
#   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
#   ruby scripts/test_discover_hang.rb "https://drive.google.com/drive/folders/abc123"

require 'bundler/setup'
require 'logger'
require 'timeout'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'humata_import/clients/gdrive_client'
require 'humata_import/database'

class DiscoverHangTester
  def initialize(gdrive_url, timeout: 60)
    @gdrive_url = gdrive_url
    @timeout = timeout
    @logger = Logger.new($stdout).tap { |log| log.level = Logger::INFO }
  end

  def run_tests
    puts "🔍 Discover Command Hang Diagnostic Tool"
    puts "=" * 50
    puts "URL: #{@gdrive_url}"
    puts "Timeout: #{@timeout} seconds"
    puts

    test_environment
    test_database
    test_authentication
    test_url_parsing
    test_file_listing
  end

  private

  def test_environment
    puts "🌍 Test 1: Environment Check"
    puts "-" * 25
    
    puts "✅ Ruby version: #{RUBY_VERSION}"
    puts "✅ Load path: #{$LOAD_PATH.first}"
    
    # Check for Google credentials
    if ENV['GOOGLE_APPLICATION_CREDENTIALS']
      puts "✅ GOOGLE_APPLICATION_CREDENTIALS: #{ENV['GOOGLE_APPLICATION_CREDENTIALS']}"
      if File.exist?(ENV['GOOGLE_APPLICATION_CREDENTIALS'])
        puts "✅ Credentials file exists"
      else
        puts "❌ Credentials file does not exist"
      end
    else
      puts "⚠️  GOOGLE_APPLICATION_CREDENTIALS not set"
    end
    
    puts
  end

  def test_database
    puts "🗄️  Test 2: Database Initialization"
    puts "-" * 30
    
    begin
      Timeout.timeout(10) do
        HumataImport::Database.initialize_schema('./test_discover_hang.db')
        puts "✅ Database schema initialized successfully"
      end
    rescue Timeout::Error
      puts "❌ Database initialization timed out"
    rescue StandardError => e
      puts "❌ Database initialization failed: #{e.message}"
    end
    
    puts
  end

  def test_authentication
    puts "🔑 Test 3: Google Drive Authentication"
    puts "-" * 35
    
    begin
      Timeout.timeout(@timeout) do
        @logger.info "Initializing Google Drive client..."
        client = HumataImport::Clients::GdriveClient.new(timeout: 30)
        puts "✅ Google Drive client initialized successfully"
        @client = client
      end
    rescue Timeout::Error
      puts "❌ Authentication timed out after #{@timeout} seconds"
      puts "   This suggests the issue is in Google::Auth.get_application_default"
    rescue StandardError => e
      puts "❌ Authentication failed: #{e.message}"
      puts "   Error class: #{e.class}"
    end
    
    puts
  end

  def test_url_parsing
    puts "🔗 Test 4: URL Parsing"
    puts "-" * 20
    
    begin
      Timeout.timeout(5) do
        if @client
          folder_id = @client.send(:extract_folder_id, @gdrive_url)
          puts "✅ URL parsed successfully"
          puts "   Folder ID: #{folder_id}"
        else
          puts "⚠️  Skipping URL parsing (client not available)"
        end
      end
    rescue Timeout::Error
      puts "❌ URL parsing timed out"
    rescue StandardError => e
      puts "❌ URL parsing failed: #{e.message}"
    end
    
    puts
  end

  def test_file_listing
    puts "📁 Test 5: File Listing"
    puts "-" * 20
    
    unless @client
      puts "⚠️  Skipping file listing (client not available)"
      puts
      return
    end
    
    begin
      Timeout.timeout(@timeout) do
        puts "Starting file discovery (this may take a while)..."
        files = @client.list_files(@gdrive_url, recursive: false) # Start with non-recursive
        puts "✅ File listing completed successfully"
        puts "   Found #{files.size} files"
        
        if files.any?
          puts "   Sample files:"
          files.first(3).each do |file|
            puts "     - #{file[:name]} (#{file[:id]})"
          end
        end
        
        # Test max files limit
        puts "\n🧪 Testing max files limit..."
        max_files_test = @client.list_files(@gdrive_url, recursive: false, max_files: 5)
        puts "✅ Max files test completed"
        puts "   Limited to 5 files, found: #{max_files_test.size} files"
      end
    rescue Timeout::Error
      puts "❌ File listing timed out after #{@timeout} seconds"
      puts "   The folder may be too large or have too many items"
    rescue StandardError => e
      puts "❌ File listing failed: #{e.message}"
      puts "   Error class: #{e.class}"
    end
    
    puts
  end
end

# Main execution
if ARGV.empty?
  puts "Usage: ruby scripts/test_discover_hang.rb <gdrive-url>"
  puts "Example: ruby scripts/test_discover_hang.rb https://drive.google.com/drive/u/0/folders/1IcuPBd2sdA8mkGApx7OAokbrqOT7fWre"
  exit 1
end

gdrive_url = ARGV[0]
timeout = ARGV[1]&.to_i || 60

tester = DiscoverHangTester.new(gdrive_url, timeout: timeout)
tester.run_tests 