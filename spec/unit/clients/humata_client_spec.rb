# frozen_string_literal: true

require_relative '../../spec_helper'

describe HumataImport::Clients::HumataClient do
  let(:api_key) { 'test_api_key' }
  let(:fake_time) do
    Class.new do
      attr_reader :now_calls, :sleep_calls
      def initialize
        @t = Time.at(0)
        @now_calls = 0
        @sleep_calls = []
      end
      def now
        @now_calls += 1
        @t
      end
      def sleep(seconds)
        @sleep_calls << seconds
        @t += seconds
      end
    end.new
  end
  let(:client) { HumataImport::Clients::HumataClient.new(api_key: api_key, time_provider: fake_time) }
  
  # Mock HTTP client for testing error handling
  let(:mock_http_client) do
    Class.new do
      def initialize
        @responses = {}
        @exceptions = {}
      end
      
      def add_response(uri, response)
        @responses[uri.to_s] = response
      end
      
      def add_exception(uri, exception)
        @exceptions[uri.to_s] = exception
      end
      
      def request(request)
        uri = request.uri.to_s
        
        if @exceptions[uri]
          raise @exceptions[uri]
        elsif @responses[uri]
          @responses[uri]
        else
          raise "No response configured for #{uri}"
        end
      end
    end.new
  end
  let(:file_url) { 'https://drive.google.com/uc?id=123' }
  let(:folder_id) { 'folder123' }
  let(:humata_id) { 'humata123' }



  def mock_humata_upload_response
    {
      'data' => {
        'pdf' => {
          'id' => humata_id,
          'status' => 'pending'
        }
      }
    }
  end

  def mock_humata_status_response
    {
      'id' => humata_id,
      'status' => 'completed',
      'created_at' => '2024-01-01T00:00:00Z',
      'updated_at' => '2024-01-01T00:00:00Z'
    }
  end

  describe '#upload_file' do
    it 'successfully uploads a file' do
      response_body = mock_humata_upload_response
      
      # Create a mock response object
      mock_response = Object.new
      def mock_response.code; '200'; end
      def mock_response.message; 'OK'; end
      def mock_response.body; @body; end
      def mock_response.body=(value); @body = value; end
      mock_response.body = response_body.to_json
      
      # Configure mock HTTP client
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      response = test_client.upload_file(file_url, folder_id)
      _(response).must_equal response_body
    end

    it 'handles validation errors (400) as permanent errors' do
      # Create a mock response object that simulates a 400 error
      mock_response = Object.new
      def mock_response.code; '400'; end
      def mock_response.message; 'Bad Request'; end
      def mock_response.body; '{"error":"Invalid request","message":"Bad URL format"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::ValidationError
    end

    it 'handles authentication errors (401) as permanent errors' do
      # Create a mock response object that simulates a 401 error
      mock_response = Object.new
      def mock_response.code; '401'; end
      def mock_response.message; 'Unauthorized'; end
      def mock_response.body; '{"error":"Unauthorized","message":"Invalid API key"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::AuthenticationError
    end

    it 'handles authorization errors (403) as permanent errors' do
      # Create a mock response object that simulates a 403 error
      mock_response = Object.new
      def mock_response.code; '403'; end
      def mock_response.message; 'Forbidden'; end
      def mock_response.body; '{"error":"Forbidden","message":"Access denied"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::AuthenticationError
    end

    it 'handles not found errors (404) as permanent errors' do
      # Create a mock response object that simulates a 404 error
      mock_response = Object.new
      def mock_response.code; '404'; end
      def mock_response.message; 'Not Found'; end
      def mock_response.body; '{"error":"Not found","message":"Resource not found"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::ValidationError
    end

    it 'handles rate limit errors (429) as transient errors' do
      # Create a mock response object that simulates a 429 error
      mock_response = Object.new
      def mock_response.code; '429'; end
      def mock_response.message; 'Too Many Requests'; end
      def mock_response.body; '{"error":"Rate limit exceeded","message":"Too many requests"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::TransientError
    end

    it 'handles server errors (5xx) as transient errors' do
      # Create a mock response object that simulates a 500 error
      mock_response = Object.new
      def mock_response.code; '500'; end
      def mock_response.message; 'Internal Server Error'; end
      def mock_response.body; '{"error":"Internal server error","message":"Something went wrong"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::TransientError
    end

    it 'handles gateway timeout (504) as transient errors' do
      # Create a mock response object that simulates a 504 error
      mock_response = Object.new
      def mock_response.code; '504'; end
      def mock_response.message; 'Gateway Timeout'; end
      def mock_response.body; '{"error":"Gateway timeout","message":"Request timeout"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::TransientError
    end

    it 'handles network timeouts as network errors' do
      # Create a mock HTTP client that raises a timeout exception
      timeout_client = Object.new
      def timeout_client.request(request)
        raise Net::OpenTimeout, "Request timeout"
      end
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: timeout_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::NetworkError
    end

    it 'handles connection failures as network errors' do
      # Create a mock HTTP client that raises a connection exception
      connection_client = Object.new
      def connection_client.request(request)
        raise SocketError, "Failed to open TCP connection"
      end
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: connection_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::NetworkError
    end

    it 'enforces rate limiting without real sleep' do
      response_body = mock_humata_upload_response
      
      # Create a mock response object
      mock_response = Object.new
      def mock_response.code; '200'; end
      def mock_response.message; 'OK'; end
      def mock_response.body; @body; end
      def mock_response.body=(value); @body = value; end
      mock_response.body = response_body.to_json
      
      # Configure mock HTTP client
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      # Make two quick requests; fake time captures sleep request
      test_client.upload_file(file_url, folder_id)
      test_client.upload_file(file_url, folder_id)
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(fake_time.sleep_calls.last).must_be :>=, 0
      _(fake_time.sleep_calls.last).must_be :<=, min_interval
    end

    it 'handles JSON parsing errors gracefully' do
      # Create a mock response object with invalid JSON
      mock_response = Object.new
      def mock_response.body; 'invalid json'; end
      
      # Configure mock HTTP client to return the invalid JSON response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::HumataError
    end
  end

  describe '#get_file_status' do
    it 'successfully gets file status' do
      response_body = mock_humata_status_response
      
      # Create a mock response object
      mock_response = Object.new
      def mock_response.code; '200'; end
      def mock_response.message; 'OK'; end
      def mock_response.body; @body; end
      def mock_response.body=(value); @body = value; end
      mock_response.body = response_body.to_json
      
      # Configure mock HTTP client
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      response = test_client.get_file_status(humata_id)
      _(response).must_equal response_body
    end

    it 'handles validation errors (400) as permanent errors' do
      # Create a mock response object that simulates a 400 error
      mock_response = Object.new
      def mock_response.code; '400'; end
      def mock_response.message; 'Bad Request'; end
      def mock_response.body; '{"error":"Invalid request","message":"Bad humata_id format"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::ValidationError
    end

    it 'handles authentication errors (401) as permanent errors' do
      # Create a mock response object that simulates a 401 error
      mock_response = Object.new
      def mock_response.code; '401'; end
      def mock_response.message; 'Unauthorized'; end
      def mock_response.body; '{"error":"Unauthorized","message":"Invalid API key"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::AuthenticationError
    end

    it 'handles not found errors (404) as permanent errors' do
      # Create a mock response object that simulates a 404 error
      mock_response = Object.new
      def mock_response.code; '404'; end
      def mock_response.message; 'Not Found'; end
      def mock_response.body; '{"error":"Not found","message":"File not found"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::ValidationError
    end

    it 'handles rate limit errors (429) as transient errors' do
      # Create a mock response object that simulates a 429 error
      mock_response = Object.new
      def mock_response.code; '429'; end
      def mock_response.message; 'Too Many Requests'; end
      def mock_response.body; '{"error":"Rate limit exceeded","message":"Too many requests"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::TransientError
    end

    it 'handles server errors (5xx) as transient errors' do
      # Create a mock response object that simulates a 500 error
      mock_response = Object.new
      def mock_response.code; '500'; end
      def mock_response.message; 'Internal Server Error'; end
      def mock_response.body; '{"error":"Internal server error","message":"Something went wrong"}'; end
      
      # Configure mock HTTP client to return the error response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::TransientError
      end

    it 'handles network timeouts as network errors' do
      # Create a mock HTTP client that raises a timeout exception
      timeout_client = Object.new
      def timeout_client.request(request)
        raise Net::OpenTimeout, "Request timeout"
      end
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: timeout_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::NetworkError
    end

    it 'enforces rate limiting without real sleep' do
      response_body = mock_humata_status_response
      
      # Create a mock response object
      mock_response = Object.new
      def mock_response.code; '200'; end
      def mock_response.message; 'OK'; end
      def mock_response.body; @body; end
      def mock_response.body=(value); @body = value; end
      mock_response.body = response_body.to_json
      
      # Configure mock HTTP client
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      # Make two quick requests; fake time captures sleep request
      test_client.get_file_status(humata_id)
      test_client.get_file_status(humata_id)
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(fake_time.sleep_calls.last).must_be :>=, 0
      _(fake_time.sleep_calls.last).must_be :<=, min_interval
    end

    it 'handles JSON parsing errors gracefully' do
      # Create a mock response object with invalid JSON
      mock_response = Object.new
      def mock_response.body; 'invalid json'; end
      
      # Configure mock HTTP client to return the invalid JSON response
      mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}", mock_response)
      
      # Create client with mock HTTP client
      test_client = HumataImport::Clients::HumataClient.new(
        api_key: api_key, 
        http_client: mock_http_client,
        time_provider: fake_time
      )

      _(-> { test_client.get_file_status(humata_id) })
        .must_raise HumataImport::HumataError
    end
  end

  describe 'error categorization' do
    it 'categorizes 4xx client errors as permanent errors' do
      [400, 401, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 425, 426, 428, 429, 431, 451].each do |status|
        # Create a mock response object for this status code
        mock_response = Object.new
        def mock_response.code; @code; end
        def mock_response.code=(value); @code = value; end
        def mock_response.message; @message; end
        def mock_response.message=(value); @message = value; end
        def mock_response.body; '{}'; end
        
        mock_response.code = status.to_s
        mock_response.message = 'Client Error'
        
        # Configure mock HTTP client to return the error response
        mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
        
        # Create client with mock HTTP client
        test_client = HumataImport::Clients::HumataClient.new(
          api_key: api_key, 
          http_client: mock_http_client,
          time_provider: fake_time
        )

        begin
          test_client.upload_file(file_url, folder_id)
        rescue => e
          # 429 should be TransientError, others should be permanent
          if status == 429
            _(e).must_be_instance_of HumataImport::TransientError
          else
            # Should be one of the permanent error types
            expected_classes = [HumataImport::ValidationError, HumataImport::AuthenticationError, HumataImport::HumataError]
            _(expected_classes).must_include e.class
          end
        end
      end
    end

    it 'categorizes 5xx server errors as transient errors' do
      [500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511].each do |status|
        # Create a mock response object for this status code
        mock_response = Object.new
        def mock_response.code; @code; end
        def mock_response.code=(value); @code = value; end
        def mock_response.message; @message; end
        def mock_response.message=(value); @message = value; end
        def mock_response.body; '{}'; end
        
        mock_response.code = status.to_s
        mock_response.message = 'Server Error'
        
        # Configure mock HTTP client to return the error response
        mock_http_client.add_response("#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url", mock_response)
        
        # Create client with mock HTTP client
        test_client = HumataImport::Clients::HumataClient.new(
          api_key: api_key, 
          http_client: mock_http_client,
          time_provider: fake_time
        )

        _(-> { test_client.upload_file(file_url, folder_id) })
          .must_raise HumataImport::TransientError
      end
    end
  end
end