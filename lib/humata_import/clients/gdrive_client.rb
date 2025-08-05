# lib/humata_import/clients/gdrive_client.rb
require 'google/apis/drive_v3'
require 'googleauth'
require 'logger'

module HumataImport
  module Clients
    # Client for interacting with Google Drive using the Drive API (v3).
    # Provides methods to authenticate and list files in a folder.
    class GdriveClient
      # Google Drive API scope for read-only access.
      SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

      # Initializes a new GdriveClient and authenticates with Google Drive API.
      # @param service [Google::Apis::DriveV3::DriveService, nil] Optional service instance for dependency injection
      # @param credentials [Google::Auth::Credentials, nil] Optional credentials for dependency injection
      # @param timeout [Integer] Timeout in seconds for API requests (default: 60)
      def initialize(service: nil, credentials: nil, timeout: 60)
        @service = service || Google::Apis::DriveV3::DriveService.new
        @credentials = credentials
        @timeout = timeout
        @logger = Logger.new($stdout).tap { |log| log.level = Logger::INFO }
        
        # Configure timeouts
        @service.client_options.read_timeout_sec = @timeout
        @service.client_options.open_timeout_sec = 30
        
        authenticate unless service || credentials
      end

      # Authenticates the client using application default credentials.
      # @return [void]
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
      end

      # Lists files in a Google Drive folder.
      # @param folder_url [String] The URL of the Google Drive folder.
      # @param recursive [Boolean] Whether to list files recursively in subfolders (default: true).
      # @return [Array<Hash>] Array of file metadata hashes.
      def list_files(folder_url, recursive: true)
        @logger.debug "Extracting folder ID from URL: #{folder_url}"
        folder_id = extract_folder_id(folder_url)
        @logger.debug "Folder ID: #{folder_id}"
        
        @logger.info "Starting file discovery in folder: #{folder_id}"
        files = []
        crawl_folder(folder_id, files, recursive)
        @logger.info "Completed file discovery. Found #{files.size} files"
        files
      end

      private

      # Recursively crawls a folder and collects file metadata.
      # @param folder_id [String] The ID of the folder to crawl.
      # @param files [Array<Hash>] The array to collect file metadata.
      # @param recursive [Boolean] Whether to crawl subfolders.
      # @return [void]
      def crawl_folder(folder_id, files, recursive)
        @logger.debug "Crawling folder: #{folder_id}"
        page_token = nil
        page_count = 0
        total_items = 0
        
        begin
          loop do
            page_count += 1
            @logger.debug "Fetching page #{page_count} for folder: #{folder_id}"
            
            response = @service.list_files(
              q: "'#{folder_id}' in parents",
              fields: 'nextPageToken, files(id, name, mimeType, webContentLink, size)',
              page_token: page_token,
              supports_all_drives: true,
              include_items_from_all_drives: true,
              page_size: 100 # Limit page size to avoid timeouts
            )
            
            items_in_page = response.files&.size || 0
            total_items += items_in_page
            @logger.debug "Page #{page_count}: Found #{items_in_page} items"
            
            response.files.each do |file|
              @logger.debug "Item: #{file.name} (#{file.id}) - Type: #{file.mime_type}"
              
              if file.mime_type == 'application/vnd.google-apps.folder'
                if recursive
                  @logger.debug "Found subfolder: #{file.name} (#{file.id})"
                  crawl_folder(file.id, files, recursive)
                else
                  @logger.debug "Skipping subfolder (non-recursive): #{file.name} (#{file.id})"
                end
              else
                files << {
                  id: file.id,
                  name: file.name,
                  mime_type: file.mime_type,
                  url: file.web_content_link,
                  size: file.respond_to?(:size) ? file.size : nil
                }
                @logger.debug "Found file: #{file.name} (#{file.id})"
              end
            end
            
            page_token = response.next_page_token
            break unless page_token
          end
          
          @logger.info "Folder #{folder_id}: Total items found: #{total_items}, Files collected: #{files.size}"
        rescue Google::Apis::Error => e
          @logger.error "Google Drive API error: #{e.message}"
          @logger.debug "Full error: #{e.class}: #{e.message}"
          raise
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          @logger.error "Network timeout error: #{e.message}"
          @logger.error "The folder may be too large or network connection is slow"
          raise
        rescue StandardError => e
          @logger.error "Unexpected error while crawling folder #{folder_id}: #{e.message}"
          @logger.debug "Full error: #{e.class}: #{e.message}"
          raise
        end
      end

      # Extracts the folder ID from a Google Drive folder URL.
      # @param url [String] The Google Drive folder URL.
      # @return [String] The extracted folder ID.
      # @raise [ArgumentError] If the URL does not contain a valid folder ID.
      def extract_folder_id(url)
        # Extracts the folder ID from a Google Drive folder URL
        if url =~ %r{(?:folders/|d/)([-\w]{5,})}
          url.match(%r{(?:folders/|d/)([-\w]{5,})})[1]
        elsif url =~ /^[-\w]{5,}$/
          url
        elsif url =~ %r{drive/folders/?([-\w]{5,})?}
          match = url.match(%r{drive/folders/?([-\w]{5,})?})
          raise ArgumentError, "Invalid Google Drive folder URL: #{url}" unless match[1]
          match[1]
        else
          raise ArgumentError, "Invalid Google Drive folder URL: #{url}"
        end
      end
    end
  end
end