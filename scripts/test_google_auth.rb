#!/usr/bin/env ruby
# frozen_string_literal: true

# Google Authentication Test Script
# Tests Google Drive API authentication and connectivity
#
# Usage:
#   bundle exec ruby scripts/test_google_auth.rb [options]
#
# Options:
#   --credentials-file PATH    Path to Google service account JSON file
#   --test-folder-id ID        Google Drive folder ID to test file listing
#   --verbose                  Enable verbose output
#   --help                     Show this help message

# Load bundler and gems
require 'bundler/setup'

require 'optparse'
require 'json'
require 'logger'
require 'google/apis/drive_v3'
require 'googleauth'

class GoogleAuthTester
  # Google Drive API scope for read-only access
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

  def initialize(options = {})
    @credentials_file = options[:credentials_file]
    @test_folder_id = options[:test_folder_id]
    @verbose = options[:verbose]
    @logger = setup_logger
    @service = nil
  end

  def run
    puts "🔐 Google Authentication Test Script"
    puts "=" * 50
    
    test_results = []
    
    # Test 1: Check environment variables
    test_results << test_environment_variables
    
    # Test 2: Validate credentials file
    test_results << test_credentials_file
    
    # Test 3: Test authentication
    test_results << test_authentication
    
    # Test 4: Test API connectivity
    test_results << test_api_connectivity
    
    # Test 5: Test file listing (if folder ID provided)
    test_results << test_file_listing if @test_folder_id
    
    # Print summary
    print_summary(test_results)
    
    # Exit with appropriate code
    exit(test_results.all? ? 0 : 1)
  end

  private

  def setup_logger
    logger = Logger.new($stdout)
    logger.level = @verbose ? Logger::DEBUG : Logger::INFO
    logger.formatter = proc do |severity, datetime, progname, msg|
      "#{severity}: #{msg}\n"
    end
    logger
  end

  def test_environment_variables
    puts "\n📋 Test 1: Environment Variables"
    puts "-" * 30
    
    credentials_env = ENV['GOOGLE_APPLICATION_CREDENTIALS']
    
    if credentials_env
      puts "✅ GOOGLE_APPLICATION_CREDENTIALS is set: #{credentials_env}"
      
      if File.exist?(credentials_env)
        puts "✅ Credentials file exists at specified path"
        file_size = File.size(credentials_env)
        puts "📊 File size: #{file_size} bytes"
        
        if file_size > 0
          puts "✅ Credentials file is not empty"
          true
        else
          puts "❌ Credentials file is empty"
          false
        end
      else
        puts "❌ Credentials file does not exist at specified path"
        false
      end
    else
      puts "⚠️  GOOGLE_APPLICATION_CREDENTIALS environment variable is not set"
      puts "   This is required for Google Drive API authentication"
      false
    end
  end

  def test_credentials_file
    puts "\n📄 Test 2: Credentials File Validation"
    puts "-" * 35
    
    file_path = @credentials_file || ENV['GOOGLE_APPLICATION_CREDENTIALS']
    
    unless file_path
      puts "❌ No credentials file specified"
      return false
    end
    
    unless File.exist?(file_path)
      puts "❌ Credentials file does not exist: #{file_path}"
      return false
    end
    
    begin
      credentials_data = JSON.parse(File.read(file_path))
      
      # Check for required fields in service account JSON
      required_fields = ['type', 'project_id', 'private_key_id', 'private_key', 'client_email']
      missing_fields = required_fields - credentials_data.keys
      
      if missing_fields.empty?
        puts "✅ Credentials file contains all required fields"
        puts "📊 Project ID: #{credentials_data['project_id']}"
        puts "📧 Client Email: #{credentials_data['client_email']}"
        puts "🔑 Type: #{credentials_data['type']}"
        true
      else
        puts "❌ Credentials file is missing required fields: #{missing_fields.join(', ')}"
        false
      end
    rescue JSON::ParserError => e
      puts "❌ Credentials file is not valid JSON: #{e.message}"
      false
    rescue StandardError => e
      puts "❌ Error reading credentials file: #{e.message}"
      false
    end
  end

  def test_authentication
    puts "\n🔑 Test 3: Authentication"
    puts "-" * 20
    
    begin
      @logger.debug("Attempting to authenticate with Google Drive API...")
      
      # Set credentials file if provided
      if @credentials_file
        ENV['GOOGLE_APPLICATION_CREDENTIALS'] = @credentials_file
        @logger.debug("Set GOOGLE_APPLICATION_CREDENTIALS to: #{@credentials_file}")
      end
      
      # Get application default credentials
      credentials = Google::Auth.get_application_default([SCOPE])
      
      if credentials
        puts "✅ Successfully obtained application default credentials"
        puts "📊 Scope: #{SCOPE}"
        
        # Initialize the service
        @service = Google::Apis::DriveV3::DriveService.new
        @service.authorization = credentials
        
        puts "✅ Successfully initialized Google Drive service"
        true
      else
        puts "❌ Failed to obtain application default credentials"
        false
      end
    rescue Google::Auth::DefaultCredentialsError => e
      puts "❌ Default credentials error: #{e.message}"
      puts "   Make sure your credentials file is properly configured"
      false
    rescue StandardError => e
      puts "❌ Authentication error: #{e.message}"
      @logger.debug("Full error: #{e.class}: #{e.message}")
      @logger.debug(e.backtrace.join("\n")) if @verbose
      false
    end
  end

  def test_api_connectivity
    puts "\n🌐 Test 4: API Connectivity"
    puts "-" * 22
    
    unless @service
      puts "❌ Service not initialized - skipping API connectivity test"
      return false
    end
    
    begin
      @logger.debug("Testing API connectivity with a simple about request...")
      
      # Make a simple API call to test connectivity
      about = @service.get_about(fields: 'user,storageQuota')
      
      if about
        puts "✅ Successfully connected to Google Drive API"
        puts "📊 User: #{about.user&.display_name || 'Unknown'}"
        puts "📊 Email: #{about.user&.email_address || 'Unknown'}"
        
        if about.storage_quota
          puts "💾 Storage Quota:"
          puts "   - Total: #{format_bytes(about.storage_quota.limit)}"
          puts "   - Used: #{format_bytes(about.storage_quota.usage)}"
          puts "   - Available: #{format_bytes(about.storage_quota.limit - about.storage_quota.usage)}"
        end
        
        true
      else
        puts "❌ API call returned no response"
        false
      end
    rescue Google::Apis::AuthorizationError => e
      puts "❌ Authorization error: #{e.message}"
      puts "   Check that your service account has the necessary permissions"
      false
    rescue Google::Apis::ServerError => e
      puts "❌ Server error: #{e.message}"
      puts "   Google Drive API is experiencing issues"
      false
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      puts "❌ Network timeout: #{e.message}"
      puts "   Check your internet connection"
      false
    rescue StandardError => e
      puts "❌ API connectivity error: #{e.message}"
      @logger.debug("Full error: #{e.class}: #{e.message}")
      @logger.debug(e.backtrace.join("\n")) if @verbose
      false
    end
  end

  def test_file_listing
    puts "\n📁 Test 5: File Listing"
    puts "-" * 18
    
    unless @service
      puts "❌ Service not initialized - skipping file listing test"
      return false
    end
    
    begin
      @logger.debug("Testing file listing for folder: #{@test_folder_id}")
      
      # List files in the specified folder
      response = @service.list_files(
        q: "'#{@test_folder_id}' in parents",
        fields: 'files(id, name, mimeType, size)',
        page_size: 10,
        supports_all_drives: true,
        include_items_from_all_drives: true
      )
      
      if response&.files
        file_count = response.files.size
        puts "✅ Successfully listed files in folder"
        puts "📊 Found #{file_count} files"
        
        if file_count > 0
          puts "📋 Sample files:"
          response.files.first(5).each do |file|
            size_str = file.respond_to?(:size) && file.size ? format_bytes(file.size) : 'Unknown'
            puts "   - #{file.name} (#{file.mime_type}, #{size_str})"
          end
        end
        
        true
      else
        puts "❌ No files found or API returned empty response"
        false
      end
    rescue Google::Apis::AuthorizationError => e
      puts "❌ Authorization error: #{e.message}"
      puts "   Check that your service account has access to the specified folder"
      false
    rescue Google::Apis::ClientError => e
      puts "❌ Client error: #{e.message}"
      puts "   The folder ID may be invalid or the folder may not exist"
      false
    rescue StandardError => e
      puts "❌ File listing error: #{e.message}"
      @logger.debug("Full error: #{e.class}: #{e.message}")
      @logger.debug(e.backtrace.join("\n")) if @verbose
      false
    end
  end

  def format_bytes(bytes)
    return '0 B' if bytes.nil? || bytes == 0
    
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    size = bytes.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end

  def print_summary(test_results)
    puts "\n" + "=" * 50
    puts "📊 Test Summary"
    puts "=" * 50
    
    passed = test_results.count(true)
    total = test_results.size
    
    puts "✅ Passed: #{passed}/#{total}"
    puts "❌ Failed: #{total - passed}/#{total}"
    
    if passed == total
      puts "\n🎉 All tests passed! Google authentication is working correctly."
    else
      puts "\n⚠️  Some tests failed. Please check the errors above and fix the issues."
    end
    
    puts "\n💡 Troubleshooting Tips:"
    puts "   - Ensure your service account JSON file is valid and complete"
    puts "   - Verify the service account has the necessary Google Drive permissions"
    puts "   - Check that the GOOGLE_APPLICATION_CREDENTIALS environment variable is set"
    puts "   - Ensure your internet connection is working"
    puts "   - Verify the folder ID is correct and accessible"
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/test_google_auth.rb [options]"
  
  opts.on("--credentials-file PATH", "Path to Google service account JSON file") do |path|
    options[:credentials_file] = path
  end
  
  opts.on("--test-folder-id ID", "Google Drive folder ID to test file listing") do |id|
    options[:test_folder_id] = id
  end
  
  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Run the tests
tester = GoogleAuthTester.new(options)
tester.run 