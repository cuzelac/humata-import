# frozen_string_literal: true

require_relative '../../spec_helper'
require 'webmock/minitest'

describe HumataImport::Clients::HumataClient do
  let(:api_key) { 'test_api_key' }
  let(:client) { HumataImport::Clients::HumataClient.new(api_key: api_key) }
  let(:file_url) { 'https://drive.google.com/uc?id=123' }
  let(:folder_id) { 'folder123' }
  let(:humata_id) { 'humata123' }

  before do
    WebMock.enable!
    @start_time = Time.now
  end

  after do
    WebMock.disable!
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
        .must_raise HumataImport::Clients::HumataError
    end

    it 'handles network errors' do
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .to_timeout

      _(-> { client.upload_file(file_url, folder_id) })
        .must_raise HumataImport::Clients::HumataError
    end

    it 'enforces rate limiting' do
      response_body = mock_humata_upload_response
      
      stub_request(:post, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v2/import-url")
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # Make two quick requests
      client.upload_file(file_url, folder_id)
      start_time = Time.now
      client.upload_file(file_url, folder_id)
      elapsed = Time.now - start_time

      # Should have waited at least the minimum interval
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(elapsed).must_be :>=, min_interval
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
        .must_raise HumataImport::Clients::HumataError
    end

    it 'handles network errors' do
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .to_timeout

      _(-> { client.get_file_status(humata_id) })
        .must_raise HumataImport::Clients::HumataError
    end

    it 'enforces rate limiting' do
      response_body = mock_humata_status_response
      
      stub_request(:get, "#{HumataImport::Clients::HumataClient::API_BASE_URL}/api/v1/pdf/#{humata_id}")
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      # Make two quick requests
      client.get_file_status(humata_id)
      start_time = Time.now
      client.get_file_status(humata_id)
      elapsed = Time.now - start_time

      # Should have waited at least the minimum interval
      min_interval = 60.0 / HumataImport::Clients::HumataClient::RATE_LIMIT
      _(elapsed).must_be :>=, min_interval
    end
  end
end