# frozen_string_literal: true

require 'uri'

module HumataImport
  module Utils
    # Utility for building URLs for Humata submission and optimizing Google Drive URLs
    class UrlBuilder
      # Default domain for building Humata submission URLs
      DEFAULT_DOMAIN = 'https://gdrive-resource.cuzelac.workers.dev'

      # Builds a URL for Humata submission in the format: DOMAIN/FILE_ID/FILE_NAME
      #
      # @param file_id [String] The file ID (e.g., Google Drive file ID)
      # @param file_name [String] The file name
      # @param domain [String] The domain to use (defaults to DEFAULT_DOMAIN)
      # @return [String] The built URL for Humata submission
      def self.build_humata_url(file_id, file_name, domain: DEFAULT_DOMAIN)
        raise ArgumentError, 'file_id cannot be nil or empty' if file_id.nil? || file_id.empty?
        raise ArgumentError, 'file_name cannot be nil or empty' if file_name.nil? || file_name.empty?
        raise ArgumentError, 'domain cannot be nil or empty' if domain.nil? || domain.empty?

        # Ensure domain doesn't end with slash
        clean_domain = domain.chomp('/')
        
        # Build URL in format: DOMAIN/FILE_ID/FILE_NAME
        "#{clean_domain}/#{file_id}/#{file_name}"
      end

      # Converts various Google Drive URL formats to direct file view URLs
      # that work reliably with the Humata API
      #
      # @param url [String] The original Google Drive URL
      # @return [String] The converted URL optimized for Humata API
      def self.convert_google_drive_url(url)
        return url unless google_drive_url?(url)
        
        file_id = extract_file_id(url)
        return url unless file_id
        
        # Convert to direct file view format that works with Humata API
        "https://drive.google.com/file/d/#{file_id}/view?usp=drive_link"
      end
      
      # Checks if a URL is a Google Drive URL
      #
      # @param url [String] The URL to check
      # @return [Boolean] True if it's a Google Drive URL
      def self.google_drive_url?(url)
        return false unless url.is_a?(String)
        
        uri = URI.parse(url) rescue nil
        return false unless uri
        
        uri.host&.include?('drive.google.com') || uri.host&.include?('docs.google.com')
      end
      
      # Extracts the file ID from various Google Drive URL formats
      #
      # @param url [String] The Google Drive URL
      # @return [String, nil] The file ID or nil if not found
      def self.extract_file_id(url)
        # Pattern 1: /file/d/{id}/view
        match = url.match(%r{/file/d/([a-zA-Z0-9_-]+)/})
        return match[1] if match
        
        # Pattern 2: /document/d/{id}/
        match = url.match(%r{/document/d/([a-zA-Z0-9_-]+)/})
        return match[1] if match
        
        # Pattern 3: /spreadsheets/d/{id}/
        match = url.match(%r{/spreadsheets/d/([a-zA-Z0-9_-]+)/})
        return match[1] if match
        
        # Pattern 4: /presentation/d/{id}/
        match = url.match(%r{/presentation/d/([a-zA-Z0-9_-]+)/})
        return match[1] if match
        
        # Pattern 5: ?id={id}
        match = url.match(/[?&]id=([a-zA-Z0-9_-]+)/)
        return match[1] if match
        
        # Pattern 6: /open?id={id}
        match = url.match(%r{/open\?id=([a-zA-Z0-9_-]+)})
        return match[1] if match
        
        nil
      end
      
      # Sanitizes a URL to remove problematic characters and parameters
      #
      # @param url [String] The original URL
      # @return [String] The sanitized URL
      def self.sanitize_url(url)
        return url unless url.is_a?(String)
        
        uri = URI.parse(url) rescue nil
        return url unless uri
        
        # Remove problematic query parameters that might cause 500 errors
        # But preserve usp=drive_link which works with Humata API
        if uri.query
          params = URI.decode_www_form(uri.query)
          filtered_params = params.reject do |key, value|
            %w[sharing edit view].include?(key.downcase) || 
            (key.downcase == 'usp' && value != 'drive_link')
          end
          
          if filtered_params.empty?
            uri.query = nil
          else
            uri.query = URI.encode_www_form(filtered_params)
          end
        end
        
        # Remove fragments that might cause issues
        uri.fragment = nil
        
        uri.to_s
      end
      
      # Optimizes a URL for Humata API to reduce 500 errors
      #
      # @param url [String] The original URL
      # @return [String] The optimized URL
      def self.optimize_for_humata(url)
        return url unless url.is_a?(String)
        
        # First sanitize the URL
        sanitized = sanitize_url(url)
        
        # Then convert Google Drive URLs to direct download format
        convert_google_drive_url(sanitized)
      end
    end
  end
end
