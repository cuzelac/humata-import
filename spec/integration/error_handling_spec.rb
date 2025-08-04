# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/minitest'

describe 'Error Handling Integration' do
  let(:gdrive_url) { 'https://drive.google.com/drive/folders/abc123' }
  let(:folder_id) { 'folder123' }
  let(:api_key) { 'test_api_key' }

  before do
    WebMock.enable!
    ENV['HUMATA_API_KEY'] = api_key
    
    @db_path = File.expand_path('../../tmp/error_test.db', __dir__)
    FileUtils.mkdir_p(File.dirname(@db_path))
    FileUtils.rm_f(@db_path)
    HumataImport::Database.initialize_schema(@db_path)
    @db = SQLite3::Database.new(@db_path)
    @db.results_as_hash = true
  end

  after do
    WebMock.disable!
    ENV.delete('HUMATA_API_KEY')
    FileUtils.rm_f(@db_path)
  end

  describe 'Google Drive errors' do
    it 'handles authentication failures' do
      # Create a mock service that raises authentication errors
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        raise Google::Apis::AuthorizationError, 'Not authorized'
      end

      Google::Apis::DriveV3::DriveService.stub :new, service_mock do
        Google::Auth.stub :get_application_default, -> { raise Google::Auth::AuthorizationError, 'Invalid credentials' } do
          discover = HumataImport::Commands::Discover.new(database: @db_path)
          discover.run([gdrive_url])

          files = @db.execute('SELECT * FROM file_records')
          _(files).must_be_empty
        end
      end
    end

    it 'handles rate limiting' do
      # Create a mock service that raises rate limit errors
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        raise Google::Apis::RateLimitError, 'Rate limit exceeded'
      end

      Google::Apis::DriveV3::DriveService.stub :new, service_mock do
        Google::Auth.stub :get_application_default, OpenStruct.new do
          discover = HumataImport::Commands::Discover.new(database: @db_path)
          discover.run([gdrive_url])

          files = @db.execute('SELECT * FROM file_records')
          _(files).must_be_empty
        end
      end
    end

    it 'handles invalid folder URLs' do
      discover = HumataImport::Commands::Discover.new(database: @db_path)
      invalid_urls = [
        'https://drive.google.com/drive/',
        'https://example.com',
        ''
      ]

      invalid_urls.each do |url|
        _(-> { discover.run([url]) }).must_raise ArgumentError
        files = @db.execute('SELECT * FROM file_records')
        _(files).must_be_empty
      end
    end
  end

  describe 'Humata API errors' do
    before do
      # Create some test files
      @files = create_test_files(@db, 3)
    end

    it 'handles API key errors' do
      # Create a real HumataClient instance but stub its upload_file method
      real_client = HumataImport::Clients::HumataClient.new(api_key: 'test', logger: Logger.new(nil))
      
      # Mock the upload_file method to raise an error
      real_client.define_singleton_method(:upload_file) do |url, folder_id|
        raise HumataImport::Clients::HumataError, 'Invalid API key'
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      HumataImport::Clients::HumataClient.stub :new, real_client do
        upload.run(['--folder-id', folder_id])
      end

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
    end

    it 'handles rate limiting with retries' do
      # Create a real HumataClient instance but stub its upload_file method
      real_client = HumataImport::Clients::HumataClient.new(api_key: 'test', logger: Logger.new(nil))
      
      call_count = 0
      real_client.define_singleton_method(:upload_file) do |url, folder_id|
        call_count += 1
        if call_count == 1
          raise HumataImport::Clients::HumataError, 'Rate limit exceeded'
        else
          {
            'id' => SecureRandom.uuid,
            'status' => 'pending',
            'message' => 'File queued for processing'
          }
        end
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      HumataImport::Clients::HumataClient.stub :new, real_client do
        upload.run(['--folder-id', folder_id, '--max-retries', '3', '--retry-delay', '0'])
      end

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['humata_id'] }).must_equal true
    end

    it 'handles network timeouts' do
      # Create a real HumataClient instance but stub its upload_file method
      real_client = HumataImport::Clients::HumataClient.new(api_key: 'test', logger: Logger.new(nil))
      
      real_client.define_singleton_method(:upload_file) do |url, folder_id|
        raise HumataImport::Clients::HumataError, 'HTTP request failed: timeout'
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      HumataImport::Clients::HumataClient.stub :new, real_client do
        upload.run(['--folder-id', folder_id, '--max-retries', '2', '--retry-delay', '0'])
      end

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
    end

    it 'handles invalid file errors' do
      # Create a real HumataClient instance but stub its upload_file method
      real_client = HumataImport::Clients::HumataClient.new(api_key: 'test', logger: Logger.new(nil))
      
      real_client.define_singleton_method(:upload_file) do |url, folder_id|
        raise HumataImport::Clients::HumataError, 'Invalid file format'
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      HumataImport::Clients::HumataClient.stub :new, real_client do
        upload.run(['--folder-id', folder_id])
      end

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
      _(files.all? { |f| JSON.parse(f['humata_import_response'])['error'] == 'Invalid file format' }).must_equal true
    end
  end

  describe 'Database errors' do
    it 'handles database connection errors' do
      invalid_db = '/nonexistent/path/db.sqlite3'
      discover = HumataImport::Commands::Discover.new(database: invalid_db)
      
      _(-> { discover.run([gdrive_url]) }).must_raise SQLite3::CantOpenException
    end

    it 'handles database write errors' do
      # Create a read-only database
      FileUtils.chmod(0444, @db_path)

      # Mock Google Drive service to prevent real HTTP requests
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        OpenStruct.new(
          files: [],
          next_page_token: nil
        )
      end

      Google::Apis::DriveV3::DriveService.stub :new, service_mock do
        Google::Auth.stub :get_application_default, OpenStruct.new do
          discover = HumataImport::Commands::Discover.new(database: @db_path)
          _(-> { discover.run([gdrive_url]) }).must_raise SQLite3::ReadOnlyException
        end
      end

      FileUtils.chmod(0644, @db_path)
    end
  end

  describe 'Concurrent operations' do
    before do
      # Create test files with humata_id so they will be processed by verify
      @files = create_test_files(@db, 5, { humata_id: 'humata123', processing_status: 'pending' })
    end

    it 'handles parallel status checks safely' do
      # Create a real HumataClient instance but stub its get_file_status method
      real_client = HumataImport::Clients::HumataClient.new(api_key: 'test', logger: Logger.new(nil))
      
      real_client.define_singleton_method(:get_file_status) do |humata_id|
        {
          'id' => SecureRandom.uuid,
          'status' => 'completed',
          'message' => 'File processed successfully'
        }
      end

      verify = HumataImport::Commands::Verify.new(database: @db_path)
      HumataImport::Clients::HumataClient.stub :new, real_client do
        verify.run(['--batch-size', '3', '--timeout', '5'])
      end

      # No database errors should occur
      files = @db.execute('SELECT * FROM file_records')
      _(files).wont_be_empty
    end
  end
end