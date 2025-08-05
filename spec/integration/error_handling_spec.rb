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
      # Set credentials path to force authentication attempt
      ENV['GOOGLE_APPLICATION_CREDENTIALS'] = '/nonexistent/credentials.json'
      
      # Mock the authentication to fail
      Google::Auth.stub :get_application_default, ->(scopes) { raise RuntimeError, 'Invalid credentials' } do
        # The authentication error should be raised during client initialization
        discover = HumataImport::Commands::Discover.new(database: @db_path)
        _(-> { discover.run([gdrive_url]) }).must_raise RuntimeError

        files = @db.execute('SELECT * FROM file_records')
        _(files).must_be_empty
      end
    ensure
      # Clean up environment variable
      ENV.delete('GOOGLE_APPLICATION_CREDENTIALS')
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
      # Mock authentication to avoid RuntimeError from auth failure
      Google::Auth.stub :get_application_default, OpenStruct.new do
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
  end

  describe 'Humata API errors' do
    before do
      # Create some test files
      @files = create_test_files(@db, 3)
    end

    it 'handles API key errors' do
      # Create a simple mock client that doesn't make HTTP requests
      mock_client = Object.new
      
      def mock_client.upload_file(url, folder_id)
        call_count = (@call_count || 0) + 1
        @call_count = call_count
        raise HumataImport::Clients::HumataError, 'Invalid API key'
      end
      
      def mock_client.call_count
        @call_count || 0
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      upload.run(['--folder-id', folder_id, '--retry-delay', '0'], humata_client: mock_client)

      # Verify error handling
      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
      _(files.all? { |f| JSON.parse(f['humata_import_response'])['error'] == 'Invalid API key' }).must_equal true
      _(mock_client.call_count).must_equal 12  # 3 files × 4 attempts each
    end

    it 'handles rate limiting with retries' do
      # Create a simple mock client
      mock_client = Object.new
      
      def mock_client.upload_file(url, folder_id)
        call_count = (@call_count || 0) + 1
        @call_count = call_count
        
        if call_count <= 9  # First 9 calls fail (3 files × 3 attempts each)
          raise HumataImport::Clients::HumataError, 'Rate limit exceeded'
        else
          {
            'id' => SecureRandom.uuid,
            'status' => 'pending',
            'message' => 'File queued for processing'
          }
        end
      end
      
      def mock_client.call_count
        @call_count || 0
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      upload.run(['--folder-id', folder_id, '--max-retries', '3', '--retry-delay', '0'], humata_client: mock_client)

      # Verify retry behavior
      files = @db.execute('SELECT * FROM file_records')
      failed_count = files.count { |f| f['processing_status'] == 'failed' }
      pending_count = files.count { |f| f['processing_status'] == 'pending' }
      _(failed_count).must_equal 2  # First 2 files failed after all retries
      _(pending_count).must_equal 1  # Last file succeeded
      _(mock_client.call_count).must_equal 10  # 2 files × 4 attempts + 1 file × 2 attempts (succeeds on 3rd)
    end

    it 'handles network timeouts' do
      # Create a simple mock client
      mock_client = Object.new
      
      def mock_client.upload_file(url, folder_id)
        call_count = (@call_count || 0) + 1
        @call_count = call_count
        raise HumataImport::Clients::HumataError, 'HTTP request failed: timeout'
      end
      
      def mock_client.call_count
        @call_count || 0
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      upload.run(['--folder-id', folder_id, '--max-retries', '2', '--retry-delay', '0'], humata_client: mock_client)

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
      _(mock_client.call_count).must_equal 9  # 3 files × 3 attempts each (1 initial + 2 retries)
    end

    it 'handles invalid file errors' do
      # Create a simple mock client
      mock_client = Object.new
      
      def mock_client.upload_file(url, folder_id)
        call_count = (@call_count || 0) + 1
        @call_count = call_count
        raise HumataImport::Clients::HumataError, 'Invalid file format'
      end
      
      def mock_client.call_count
        @call_count || 0
      end

      upload = HumataImport::Commands::Upload.new(database: @db_path)
      upload.run(['--folder-id', folder_id, '--retry-delay', '0'], humata_client: mock_client)

      files = @db.execute('SELECT * FROM file_records')
      _(files.all? { |f| f['processing_status'] == 'failed' }).must_equal true
      _(files.all? { |f| JSON.parse(f['humata_import_response'])['error'] == 'Invalid file format' }).must_equal true
      _(mock_client.call_count).must_equal 12  # 3 files × 4 attempts each
    end
  end

  describe 'Database errors' do
    it 'handles database connection errors' do
      # Try to use a database path that can't be created
      invalid_db = '/nonexistent/path/db.sqlite3'
      
      # The error should occur during command instantiation, not during run
      _(-> { 
        HumataImport::Commands::Discover.new(database: invalid_db)
      }).must_raise SQLite3::CantOpenException
    end

    it 'handles database write errors' do
      # Create a database in a read-only location to simulate write errors
      read_only_db = '/tmp/readonly_test.db'
      
      # Create the database file first
      FileUtils.mkdir_p(File.dirname(read_only_db))
      FileUtils.touch(read_only_db)
      FileUtils.chmod(0444, read_only_db)  # Make it read-only
      
      begin
        # The error should occur when trying to initialize schema (which requires write access)
        _(-> { 
          HumataImport::Database.initialize_schema(read_only_db)
        }).must_raise SQLite3::ReadOnlyException
      ensure
        # Clean up
        FileUtils.chmod(0644, read_only_db) if File.exist?(read_only_db)
        FileUtils.rm_f(read_only_db)
      end
    end
  end

  describe 'Concurrent operations' do
    before do
      # Create test files with humata_id so they will be processed by verify
      @files = create_test_files(@db, 5, { humata_id: 'humata123', processing_status: 'pending' })
    end

    it 'handles parallel status checks safely' do
      # Create a simple mock client
      mock_client = Object.new
      
      def mock_client.get_file_status(humata_id)
        call_count = (@call_count || 0) + 1
        @call_count = call_count
        {
          'id' => SecureRandom.uuid,
          'status' => 'completed',
          'message' => 'File processed successfully'
        }
      end
      
      def mock_client.call_count
        @call_count || 0
      end

      verify = HumataImport::Commands::Verify.new(database: @db_path)
      verify.run(['--batch-size', '3', '--timeout', '5'], humata_client: mock_client)

      # No database errors should occur
      files = @db.execute('SELECT * FROM file_records')
      _(files.size).must_equal 5
      _(files.all? { |f| f['processing_status'] == 'completed' }).must_equal true
      _(mock_client.call_count).must_equal 5  # 5 files checked
    end
  end
end