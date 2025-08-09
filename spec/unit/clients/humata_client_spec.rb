# frozen_string_literal: true

require_relative '../../spec_helper'
require 'webmock/minitest'

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
  let(:file_url) { 'https://drive.google.com/uc?id=123' }
  let(:folder_id) { 'folder123' }
  let(:humata_id) { 'humata123' }

  # WebMock is configured in spec_helper; no per-test enable/disable needed

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
      
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .with(
          body: { url: file_url, folder_id: folder_id }.to_json,
          headers: {
            'Authorization' => "Bearer #{api_key}",
            'Content-Type' => 'application/json'
          }
        )
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = client.upload_file(file_url, folder_id)
      _(response).must_equal response_body
    end

    it 'handles API errors' do
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .to_return(
          status: 400,
          body: { error: 'Invalid request', message: 'Bad URL format' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      _(-> { client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::HumataError
    end

    it 'handles network errors' do
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .to_timeout

      _(-> { client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::NetworkError
    end

    it 'enforces rate limiting without real sleep' do
      response_body = mock_humata_upload_response
      
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # Make two quick requests; fake time captures sleep request
      client.upload_file(file_url, folder_id)
      client.upload_file(file_url, folder_id)
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(fake_time.sleep_calls.last).must_be :>=, 0
      _(fake_time.sleep_calls.last).must_be :<=, min_interval
    end
  end

  describe '#get_file_status' do
    it 'successfully gets file status' do
      response_body = mock_humata_status_response
      
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .with(
          headers: { 'Authorization' => "Bearer #{api_key}" }
        )
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = client.get_file_status(humata_id)
      _(response).must_equal response_body
    end

    it 'handles API errors' do
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .to_return(
          status: 404,
          body: { error: 'Not found', message: 'File not found' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      _(-> { client.get_file_status(humata_id) })
        .must_raise HumataImport::HumataError
    end

    it 'handles network errors' do
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .to_timeout

      _(-> { client.get_file_status(humata_id) })
        .must_raise HumataImport::NetworkError
    end

    it 'enforces rate limiting without real sleep' do
      response_body = mock_humata_status_response
      
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # Make two quick requests; fake time captures sleep request
      client.get_file_status(humata_id)
      client.get_file_status(humata_id)
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(fake_time.sleep_calls.last).must_be :>=, 0
      _(fake_time.sleep_calls.last).must_be :<=, min_interval
    end
  end
end