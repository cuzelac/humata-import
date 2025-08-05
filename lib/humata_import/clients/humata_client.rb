# frozen_string_literal: true

# Client for interacting with the Humata API.
#
# This file provides the HumataClient class for uploading files to Humata.ai
# and checking their processing status. Handles authentication, rate limiting,
# and error management.
#
# Dependencies:
#   - net/http (stdlib)
#   - json (stdlib)
#   - uri (stdlib)
#   - HumataImport::Logger
#
# Configuration:
#   - Requires HUMATA_API_KEY environment variable
#
# Side Effects:
#   - Makes HTTP requests to Humata API
#   - Logs API interactions
#
# @author Humata Import Team
# @since 0.1.0
require 'net/http'
require 'json'
require 'uri'
require_relative '../logger'

module HumataImport
  module Clients
    # Client for interacting with the Humata API.
    # Provides methods to upload files via URL and check processing status.
    class HumataClient
      # @return [Integer] Default rate limit (requests per minute)
      RATE_LIMIT = 120

      # @return [String] Base URL for the Humata API
      API_BASE_URL = 'https://app.humata.ai'

      # Initializes a new HumataClient.
      #
      # @param api_key [String] The Humata API key
      # @param http_client [Net::HTTP, nil] Optional HTTP client for dependency injection
      # @param base_url [String] Optional base URL for the API (defaults to API_BASE_URL)
      # @raise [HumataImport::ConfigurationError] If API key is missing or invalid
      def initialize(api_key:, http_client: nil, base_url: API_BASE_URL)
        raise HumataImport::ConfigurationError, 'API key is required' if api_key.nil? || api_key.empty?
        
        @api_key = api_key
        @logger = HumataImport::Logger.instance
        @http_client = http_client
        @base_url = base_url
        @last_request_time = nil
      end

      # Uploads a file to Humata via URL.
      #
      # @param url [String] The public URL of the file to upload
      # @param folder_id [String] The Humata folder ID to upload to
      # @return [Hash] The API response containing the Humata file ID
      # @raise [HumataImport::HumataError] If the API request fails
      # @raise [HumataImport::NetworkError] If network communication fails
      # @raise [HumataImport::ValidationError] If URL or folder_id is invalid
      def upload_file(url, folder_id)
        validate_upload_params(url, folder_id)
        enforce_rate_limit
        
        uri = URI.join(@base_url, '/api/v2/import-url')
        
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'
        request.body = {
          url: url,
          folder_id: folder_id
        }.to_json

        response = make_request(uri, request)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise HumataImport::HumataError, "Failed to parse API response: #{e.message}"
      end

      # Gets the processing status of a file.
      #
      # @param humata_id [String] The Humata file ID
      # @return [Hash] The API response containing the file status
      # @raise [HumataImport::HumataError] If the API request fails
      # @raise [HumataImport::NetworkError] If network communication fails
      # @raise [HumataImport::ValidationError] If humata_id is invalid
      def get_file_status(humata_id)
        raise HumataImport::ValidationError, 'Humata ID is required' if humata_id.nil? || humata_id.empty?
        
        enforce_rate_limit
        uri = URI.join(@base_url, "/api/v1/pdf/#{humata_id}")
        
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"

        response = make_request(uri, request)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise HumataImport::HumataError, "Failed to parse API response: #{e.message}"
      end

      private

      # Validates upload parameters.
      #
      # @param url [String] The file URL
      # @param folder_id [String] The folder ID
      # @raise [HumataImport::ValidationError] If parameters are invalid
      def validate_upload_params(url, folder_id)
        raise HumataImport::ValidationError, 'URL is required' if url.nil? || url.empty?
        raise HumataImport::ValidationError, 'Folder ID is required' if folder_id.nil? || folder_id.empty?
        raise HumataImport::ValidationError, 'URL must be a valid HTTP/HTTPS URL' unless url.match?(/\Ahttps?:\/\//)
      end

      # Makes an HTTP request with error handling.
      #
      # @param uri [URI] The request URI
      # @param request [Net::HTTP::Request] The request object
      # @return [Net::HTTP::Response] The response object
      # @raise [HumataImport::HumataError] If the request fails
      # @raise [HumataImport::NetworkError] If network communication fails
      def make_request(uri, request)
        begin
          if @http_client
            # Use injected HTTP client
            @logger.debug "Making request to #{uri}"
            response = @http_client.request(request)
            @last_request_time = Time.now
            response
          else
            # Use default HTTP client
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true

            @logger.debug "Making request to #{uri}"
            response = http.request(request)
            @last_request_time = Time.now

            case response
            when Net::HTTPSuccess
              response
            else
              error_message = begin
                JSON.parse(response.body)['message']
              rescue JSON::ParserError
                "HTTP #{response.code}: #{response.message}"
              end
              
              case response.code.to_i
              when 401, 403
                raise HumataImport::AuthenticationError, "Authentication failed: #{error_message}"
              when 404
                raise HumataImport::ValidationError, "Resource not found: #{error_message}"
              when 429
                raise HumataImport::TransientError, "Rate limit exceeded: #{error_message}"
              when 500..599
                raise HumataImport::TransientError, "Server error: #{error_message}"
              else
                raise HumataImport::HumataError, "API request failed: #{error_message}"
              end
            end
          end
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise HumataImport::NetworkError, "Request timeout: #{e.message}"
        rescue SocketError, Errno::ECONNREFUSED => e
          raise HumataImport::NetworkError, "Connection failed: #{e.message}"
        rescue StandardError => e
          raise HumataImport::HumataError, "Unexpected error: #{e.message}"
        end
      end

      # Enforces rate limiting by sleeping if necessary.
      #
      # @return [void]
      def enforce_rate_limit
        return unless @last_request_time
        
        elapsed = Time.now - @last_request_time
        min_interval = 60.0 / RATE_LIMIT
        
        if elapsed < min_interval
          sleep_time = min_interval - elapsed
          sleep(sleep_time)
        end
      end
    end
  end
end