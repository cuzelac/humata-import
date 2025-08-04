# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/minitest'

describe 'Full Workflow Integration' do
  let(:gdrive_url) { 'https://drive.google.com/drive/folders/abc123' }
  let(:folder_id) { 'folder123' }
  let(:api_key) { 'test_api_key' }

  before do
    WebMock.enable!
    ENV['HUMATA_API_KEY'] = api_key
    
    # Set up a clean database
    @db_path = File.expand_path('../../tmp/integration_test.db', __dir__)
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

  it 'processes a complete Google Drive folder import' do
    # Mock Google Drive API responses
    gdrive_files = [
      { id: 'file1', name: 'test1.pdf', mime_type: 'application/pdf' },
      { id: 'file2', name: 'test2.doc', mime_type: 'application/msword' },
      { id: 'file3', name: 'test3.txt', mime_type: 'text/plain' }
    ]

    # Create a mock service that returns our test data
    service_mock = OpenStruct.new
    service_mock.define_singleton_method(:list_files) do |**kwargs|
      # Create the response directly
      OpenStruct.new(
        files: gdrive_files.map do |f|
          OpenStruct.new(
            id: f[:id] || SecureRandom.hex(16),
            name: f[:name] || "file_#{SecureRandom.hex(4)}.pdf",
            mime_type: f[:mime_type] || 'application/pdf',
            web_content_link: f[:url] || "https://drive.google.com/uc?id=#{SecureRandom.hex(16)}",
            size: f[:size] || 1024
          )
        end,
        next_page_token: nil
      )
    end

    Google::Apis::DriveV3::DriveService.stub :new, service_mock do
      Google::Auth.stub :get_application_default, OpenStruct.new do
        # Phase 1: Discover
        discover = HumataImport::Commands::Discover.new(database: @db_path)
        discover.run([gdrive_url])

        # Verify discover results
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 3
        _(files.map { |f| f['gdrive_id'] }).must_equal %w[file1 file2 file3]
      end
    end

    # Mock HumataClient for upload
    client_mock = Minitest::Mock.new
    gdrive_files.each do |file|
      client_mock.expect :upload_file, mock_humata_upload_response(success: true), [String, folder_id]
    end

    # Phase 2: Upload
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    HumataImport::Clients::HumataClient.stub :new, client_mock do
      upload.run(['--folder-id', folder_id])
    end

    # Verify upload results
    files = @db.execute('SELECT * FROM file_records')
    _(files.all? { |f| f['humata_id'] }).must_equal true
    _(files.all? { |f| f['processing_status'] == 'pending' }).must_equal true

    # Mock HumataClient for status checks
    status_client_mock = Minitest::Mock.new
    files.each do |file|
      status_client_mock.expect :get_file_status, mock_humata_status_response(status: 'completed'), [String]
    end

    # Phase 3: Verify
    verify = HumataImport::Commands::Verify.new(database: @db_path)
    HumataImport::Clients::HumataClient.stub :new, status_client_mock do
      verify.run(['--timeout', '5'])
    end

    # Verify final results
    files = @db.execute('SELECT * FROM file_records')
    _(files.all? { |f| f['processing_status'] == 'completed' }).must_equal true
    _(files.all? { |f| f['humata_verification_response'] }).must_equal true
  end

  it 'handles errors gracefully' do
    # Mock Google Drive API error
    service_mock = OpenStruct.new
    service_mock.define_singleton_method(:list_files) do |**kwargs|
      raise Google::Apis::Error, 'API error'
    end

    Google::Apis::DriveV3::DriveService.stub :new, service_mock do
      Google::Auth.stub :get_application_default, OpenStruct.new do
        discover = HumataImport::Commands::Discover.new(database: @db_path)
        discover.run([gdrive_url])

        # Should handle error gracefully
        files = @db.execute('SELECT * FROM file_records')
        _(files).must_be_empty
      end
    end

    # Create a test file for upload error handling
    create_test_file(@db)

    # Mock HumataClient upload error
    error_client_mock = Minitest::Mock.new
    # Mock 4 calls (1 initial + 3 retries) to match the default max_retries setting
    4.times do
      error_client_mock.expect :upload_file, ->(*args) { raise HumataImport::Clients::HumataError, 'Invalid request' }, [String, folder_id]
    end

    # Upload should handle error
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    HumataImport::Clients::HumataClient.stub :new, error_client_mock do
      upload.run(['--folder-id', folder_id])
    end

    files = @db.execute('SELECT * FROM file_records')
    _(files.first['processing_status']).must_equal 'failed'
  end

  it 'supports resuming interrupted operations' do
    # Create some test files in various states
    create_test_file(@db, processing_status: 'completed', humata_id: 'done1')
    create_test_file(@db, processing_status: 'failed', humata_id: 'fail1')
    create_test_file(@db, processing_status: 'pending', humata_id: 'pending1')
    create_test_file(@db)  # Not yet uploaded

    # Mock successful API responses
    resume_client_mock = Minitest::Mock.new
    resume_client_mock.expect :upload_file, mock_humata_upload_response(success: true), [String, folder_id]

    # Upload should only process unstarted files
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    HumataImport::Clients::HumataClient.stub :new, resume_client_mock do
      upload.run(['--folder-id', folder_id])
    end

    files = @db.execute('SELECT * FROM file_records')
    _(files.count { |f| f['humata_id'] }).must_equal 4  # All should have IDs now

    # Mock status checks for verify
    status_client_mock = Minitest::Mock.new
    files.each do |file|
      if file['processing_status'] == 'pending'
        status_client_mock.expect :get_file_status, mock_humata_status_response(status: 'completed'), [String]
      end
    end

    # Verify should only process pending files
    verify = HumataImport::Commands::Verify.new(database: @db_path)
    HumataImport::Clients::HumataClient.stub :new, status_client_mock do
      verify.run(['--timeout', '5'])
    end

    files = @db.execute('SELECT * FROM file_records')
    _(files.count { |f| f['processing_status'] == 'completed' }).must_equal 3  # Previously completed + newly processed
    _(files.count { |f| f['processing_status'] == 'failed' }).must_equal 1    # Previously failed
  end
end