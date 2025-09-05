# frozen_string_literal: true

# Client for interacting with Google Drive using the Drive API (v3).
#
# This file provides the GdriveClient class for discovering files in Google Drive
# folders. Handles authentication, recursive crawling, and file metadata extraction.
#
# Dependencies:
#   - google-api-client (gem)
#   - googleauth (gem)
#   - HumataImport::Logger
#
# Configuration:
#   - Requires GOOGLE_APPLICATION_CREDENTIALS environment variable
#
# Side Effects:
#   - Makes HTTP requests to Google Drive API
#   - Logs API interactions
#
# @author Humata Import Team
# @since 0.1.0
require 'google/apis/drive_v3'
require 'googleauth'
require_relative '../logger'

module HumataImport
  module Clients
    # Client for interacting with Google Drive using the Drive API (v3).
    # Provides methods to authenticate and list files in a folder.
    class GdriveClient
      # Google Drive API scope for read-only access.
      SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

      # Initializes a new GdriveClient and authenticates with Google Drive API.
      #
      # @param service [Google::Apis::DriveV3::DriveService, nil] Optional service instance for dependency injection
      # @param credentials [Google::Auth::Credentials, nil] Optional credentials for dependency injection
      # @param timeout [Integer] Timeout in seconds for API requests (default: 60)
      # @raise [HumataImport::ConfigurationError] If authentication fails
      def initialize(service: nil, credentials: nil, timeout: 60)
        @service = service || Google::Apis::DriveV3::DriveService.new
        @credentials = credentials
        @timeout = timeout
        @logger = HumataImport::Logger.instance
        
        # Configure timeouts (only if service has client_options)
        if @service.respond_to?(:client_options) && @service.client_options
          @service.client_options.read_timeout_sec = @timeout
          @service.client_options.open_timeout_sec = 30
        end
        
        authenticate unless service || credentials
      end

      # Authenticates the client using application default credentials.
      #
      # @return [void]
      # @raise [HumataImport::AuthenticationError] If authentication fails
      def authenticate
        return if @credentials || (ENV['GOOGLE_APPLICATION_CREDENTIALS'].nil? && ENV['TEST_ENV'] == 'true')
        
        @logger.debug "Starting Google Drive authentication..."
        
        if @credentials
          @service.authorization = @credentials
          @logger.debug "Using provided credentials"
        else
          @logger.debug "Getting application default credentials..."
          credentials = Google::Auth.get_application_default([SCOPE])
          @service.authorization = credentials
          @logger.debug "Successfully obtained application default credentials"
        end
        
        @logger.debug "Authentication completed"
      rescue StandardError => e
        raise HumataImport::AuthenticationError, "Authentication failed: #{e.message}"
      end

      # Lists files in a Google Drive folder.
      #
      # @param folder_url [String] The URL of the Google Drive folder
      # @param recursive [Boolean] Whether to list files recursively in subfolders (default: true)
      # @param max_files [Integer, nil] Maximum number of files to collect (nil for unlimited)
      # @param max_retries [Integer] Maximum retry attempts for API calls (default: 3)
      # @param retry_delay [Integer] Base delay in seconds between retries (default: 5)
      # @return [Array<Hash>] Array of file metadata hashes
      # @raise [HumataImport::ValidationError] If folder URL is invalid
      # @raise [HumataImport::GoogleDriveError] If API request fails
      # @raise [HumataImport::NetworkError] If network communication fails
      def list_files(folder_url, recursive = true, max_files = nil, max_retries = 3, retry_delay = 5)
        validate_folder_url(folder_url)
        
        @logger.debug "Extracting folder ID from URL: #{folder_url}"
        folder_id = extract_folder_id(folder_url)
        @logger.debug "Folder ID: #{folder_id}"
        
        @logger.info "Starting file discovery in folder: #{folder_id}"
        @logger.info "Max files limit: #{max_files || 'unlimited'}"
        @logger.info "Retry configuration: max_retries=#{max_retries}, retry_delay=#{retry_delay}s"
        files = []
        crawl_folder(folder_id, files, recursive, max_files, max_retries, retry_delay)
        @logger.info "Completed file discovery. Found #{files.size} files"
        files
      end

      private

      # Validates the folder URL format.
      #
      # @param folder_url [String] The folder URL to validate
      # @raise [HumataImport::ValidationError] If URL is invalid
      def validate_folder_url(folder_url)
        raise HumataImport::ValidationError, 'Folder URL is required' if folder_url.nil? || folder_url.empty?
        raise HumataImport::ValidationError, 'Invalid Google Drive folder URL format' unless folder_url.match?(/drive\.google\.com/)
      end

      # Recursively crawls a folder and collects file metadata.
      #
      # @param folder_id [String] The ID of the folder to crawl
      # @param files [Array<Hash>] The array to collect file metadata
      # @param recursive [Boolean] Whether to crawl subfolders
      # @param max_files [Integer, nil] Maximum number of files to collect (nil for unlimited)
      # @param max_retries [Integer] Maximum retry attempts for API calls (default: 3)
      # @param retry_delay [Integer] Base delay in seconds between retries (default: 5)
      # @return [void]
      # @raise [HumataImport::GoogleDriveError] If API request fails
      # @raise [HumataImport::NetworkError] If network communication fails
      def crawl_folder(folder_id, files, recursive, max_files = nil, max_retries = 3, retry_delay = 5)
        @logger.debug "Crawling folder: #{folder_id}"
        page_token = nil
        page_count = 0
        total_items = 0
        
        retries = 0
        begin
          loop do
            page_count += 1
            @logger.debug "Fetching page #{page_count} for folder: #{folder_id}"
            
            response = @service.list_files(
              q: "'#{folder_id}' in parents",
              fields: 'nextPageToken, files(id, name, mimeType, webContentLink, size, createdTime, modifiedTime)',
              page_token: page_token,
              supports_all_drives: true,
              include_items_from_all_drives: true,
              page_size: 100 # Limit page size to avoid timeouts
            )
            
            items_in_page = response.files&.size || 0
            total_items += items_in_page
            
            if response.files
              response.files.each do |file|
                if file.mime_type == 'application/vnd.google-apps.folder'
                  # Handle folders
                  if recursive
                    # Recursively crawl subfolders if enabled
                    crawl_folder(file.id, files, recursive, max_files, max_retries, retry_delay)
                    return if max_files && files.size >= max_files
                  end
                  # Skip folders if not recursive (they're not added to results)
                else
                  # Add files to collection
                  files << {
                    id: file.id,
                    name: file.name,
                    mimeType: file.mime_type,
                    webContentLink: file.web_content_link,
                    size: file.size,
                    createdTime: file.created_time&.iso8601,
                    modifiedTime: file.modified_time&.iso8601
                  }
                  
                  # Check max files limit
                  if max_files && files.size >= max_files
                    @logger.info "Reached max files limit (#{max_files})"
                    return
                  end
                end
              end
            end
            
            # Check for next page
            page_token = response.next_page_token
            break unless page_token
            
            @logger.debug "Found next page token, continuing..."
          end
          
          @logger.debug "Completed crawling folder: #{folder_id}. Total items: #{total_items}"
        rescue Google::Apis::Error => e
          case e.message
          when /rate limit/i
            error = HumataImport::TransientError, "Rate limit exceeded: #{e.message}"
          when /unauthorized|forbidden/i
            error = HumataImport::AuthenticationError, "Authorization failed: #{e.message}"
          when /invalid|bad request/i
            error = HumataImport::ValidationError, "Invalid request: #{e.message}"
          when /server error|internal error/i
            error = HumataImport::TransientError, "Server error: #{e.message}"
          else
            error = HumataImport::GoogleDriveError, "Google Drive API error: #{e.message}"
          end
          
          # Handle retryable errors
          if error[0] == HumataImport::TransientError && retries < max_retries
            retries += 1
            delay = calculate_retry_delay(retry_delay, retries)
            @logger.warn "Transient error (attempt #{retries}/#{max_retries}): #{error[1]}. Retrying in #{delay}s..."
            sleep(delay)
            retry
          else
            raise error[0], error[1]
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          if retries < max_retries
            retries += 1
            delay = calculate_retry_delay(retry_delay, retries)
            @logger.warn "Request timeout (attempt #{retries}/#{max_retries}): #{e.message}. Retrying in #{delay}s..."
            sleep(delay)
            retry
          else
            raise HumataImport::NetworkError, "Request timeout: #{e.message}"
          end
        rescue SocketError, Errno::ECONNREFUSED => e
          if retries < max_retries
            retries += 1
            delay = calculate_retry_delay(retry_delay, retries)
            @logger.warn "Connection failed (attempt #{retries}/#{max_retries}): #{e.message}. Retrying in #{delay}s..."
            sleep(delay)
            retry
          else
            raise HumataImport::NetworkError, "Connection failed: #{e.message}"
          end
        rescue StandardError => e
          if retries < max_retries
            retries += 1
            delay = calculate_retry_delay(retry_delay, retries)
            @logger.warn "Network error (attempt #{retries}/#{max_retries}): #{e.message}. Retrying in #{delay}s..."
            sleep(delay)
            retry
          else
            raise HumataImport::NetworkError, "Network error: #{e.message}"
          end
        end
      end

      # Calculates retry delay using exponential backoff.
      #
      # @param base_delay [Integer] Base delay in seconds
      # @param retry_number [Integer] Current retry attempt number
      # @return [Integer] Calculated delay in seconds (capped at 300 seconds)
      def calculate_retry_delay(base_delay, retry_number)
        delay = base_delay * (2 ** (retry_number - 1))
        [delay, 300].min # Cap at 5 minutes
      end

      # Extracts the folder ID from a Google Drive folder URL.
      #
      # @param url [String] The Google Drive folder URL
      # @return [String] The folder ID
      # @raise [HumataImport::ValidationError] If folder ID cannot be extracted
      def extract_folder_id(url)
        # Extracts the folder ID from a Google Drive folder URL
        if url =~ %r{(?:folders/|d/)([-\w]{5,})}
          $1
        elsif url =~ %r{[?&]id=([-\w]{5,})}
          $1
        elsif url =~ %r{/open\?id=([-\w]{5,})}
          $1
        elsif url =~ /^[-\w]{5,}$/
          url
        else
          raise HumataImport::ValidationError, "Could not extract folder ID from URL: #{url}"
        end
      end
    end
  end
end