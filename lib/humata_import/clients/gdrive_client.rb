# lib/humata_import/clients/gdrive_client.rb
require 'google/apis/drive_v3'
require 'googleauth'

module HumataImport
  module Clients
    # Client for interacting with Google Drive using the Drive API (v3).
    # Provides methods to authenticate and list files in a folder.
    class GdriveClient
      # Google Drive API scope for read-only access.
      SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

      # Initializes a new GdriveClient and authenticates with Google Drive API.
      def initialize
        @service = Google::Apis::DriveV3::DriveService.new
        authenticate
      end

      # Authenticates the client using application default credentials.
      # @return [void]
      def authenticate
        return if ENV['GOOGLE_APPLICATION_CREDENTIALS'].nil? && ENV['TEST_ENV'] == 'true'
        credentials = Google::Auth.get_application_default([SCOPE])
        @service.authorization = credentials
      end

      # Lists files in a Google Drive folder.
      # @param folder_url [String] The URL of the Google Drive folder.
      # @param recursive [Boolean] Whether to list files recursively in subfolders (default: true).
      # @return [Array<Hash>] Array of file metadata hashes.
      def list_files(folder_url, recursive: true)
        folder_id = extract_folder_id(folder_url)
        files = []
        crawl_folder(folder_id, files, recursive)
        files
      end

      private

      # Recursively crawls a folder and collects file metadata.
      # @param folder_id [String] The ID of the folder to crawl.
      # @param files [Array<Hash>] The array to collect file metadata.
      # @param recursive [Boolean] Whether to crawl subfolders.
      # @return [void]
      def crawl_folder(folder_id, files, recursive)
        page_token = nil
        begin
          loop do
            response = @service.list_files(
              q: "'#{folder_id}' in parents",
              fields: 'nextPageToken, files(id, name, mimeType, webContentLink, size)',
              page_token: page_token,
              supports_all_drives: true,
              include_items_from_all_drives: true
            )
            response.files.each do |file|
              if file.mime_type == 'application/vnd.google-apps.folder'
                crawl_folder(file.id, files, recursive) if recursive
              else
                files << {
                  id: file.id,
                  name: file.name,
                  mime_type: file.mime_type,
                  url: file.web_content_link,
                  size: file.respond_to?(:size) ? file.size : nil
                }
              end
            end
            page_token = response.next_page_token
            break unless page_token
          end
        rescue Google::Apis::Error => e
          warn "Google Drive API error: #{e.message}"
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