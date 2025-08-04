# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'logger'

module HumataImport
  module Clients
    # Client for interacting with the Humata API.
    # Provides methods to upload files via URL and check processing status.
    class HumataClient
      # @return [Integer] Default rate limit (requests per minute)
      RATE_LIMIT = 120

      # @return [String] Base URL for the Humata API
      API_BASE_URL = 'https://api.humata.ai'

      # Initializes a new HumataClient.
      # @param api_key [String] The Humata API key
      # @param logger [Logger] Optional logger instance
      def initialize(api_key:, logger: Logger.new($stdout))
        @api_key = api_key
        @logger = logger
        @last_request_time = nil
      end

      # Uploads a file to Humata via URL.
      # @param url [String] The public URL of the file to upload
      # @param folder_id [String] The Humata folder ID to upload to
      # @return [Hash] The API response containing the Humata file ID
      # @raise [HumataError] If the API request fails
      def upload_file(url, folder_id)
        enforce_rate_limit
        uri = URI.join(API_BASE_URL, '/api/v2/import-url')
        
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
        raise HumataError, "Failed to parse API response: #{e.message}"
      end

      # Gets the processing status of a file.
      # @param humata_id [String] The Humata file ID
      # @return [Hash] The API response containing the file status
      # @raise [HumataError] If the API request fails
      def get_file_status(humata_id)
        enforce_rate_limit
        uri = URI.join(API_BASE_URL, "/api/v1/pdf/#{humata_id}")
        
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"

        response = make_request(uri, request)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise HumataError, "Failed to parse API response: #{e.message}"
      end

      private

      # Makes an HTTP request with error handling.
      # @param uri [URI] The request URI
      # @param request [Net::HTTP::Request] The request object
      # @return [Net::HTTP::Response] The response object
      # @raise [HumataError] If the request fails
      def make_request(uri, request)
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
            response.body
          end
          raise HumataError, "API request failed (#{response.code}): #{error_message}"
        end
      rescue Net::HTTPError, SocketError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Net::OpenTimeout, Timeout::Error => e
        raise HumataError, "HTTP request failed: #{e.message}"
      end

      # Enforces the API rate limit.
      # @return [void]
      def enforce_rate_limit
        return unless @last_request_time

        elapsed = Time.now - @last_request_time
        min_interval = 60.0 / RATE_LIMIT
        
        if elapsed < min_interval
          sleep_time = min_interval - elapsed
          @logger.debug "Rate limiting: sleeping for #{sleep_time.round(2)}s"
          sleep(sleep_time)
        end
      end
    end

    # Custom error class for Humata API errors.
    class HumataError < StandardError; end
  end
end