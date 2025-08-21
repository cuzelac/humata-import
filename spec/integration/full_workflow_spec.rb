# frozen_string_literal: true

require_relative '../spec_helper'
require 'securerandom'

describe 'Full Workflow Integration' do
  def setup
    @db_path = File.join(Dir.tmpdir, "test_workflow_#{SecureRandom.hex(8)}.sqlite3")
    @db = SQLite3::Database.new(@db_path)
    HumataImport::Database.initialize_schema(@db_path)
    
    # Set up test environment
    ENV['HUMATA_API_KEY'] = 'test-key'
    ENV['TEST_ENV'] = 'true'
  end

  def teardown
    File.delete(@db_path) if File.exist?(@db_path)
    ENV.delete('HUMATA_API_KEY')
    ENV.delete('TEST_ENV')
  end

  def gdrive_url
    'https://drive.google.com/drive/folders/abc123'
  end

  def folder_id
    'test-folder-123'
  end

  def create_test_file(db, attrs = {})
    default_attrs = {
      gdrive_id: SecureRandom.hex(8),
      name: 'test.pdf',
      url: 'https://example.com/test.pdf',
      size: 1024,
      mime_type: 'application/pdf'
    }
    
    attrs = default_attrs.merge(attrs)
    
    sql = "INSERT INTO file_records (
      gdrive_id, name, url, size, mime_type, humata_folder_id, humata_id,
      upload_status, processing_status, last_error, humata_verification_response,
      humata_import_response, discovered_at, uploaded_at, completed_at, last_checked_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    
    db.execute(sql, [
      attrs[:gdrive_id],
      attrs[:name],
      attrs[:url],
      attrs[:size],
      attrs[:mime_type],
      attrs[:humata_folder_id],
      attrs[:humata_id],
      attrs[:upload_status] || 'pending',
      attrs[:processing_status],
      attrs[:last_error],
      attrs[:humata_verification_response],
      attrs[:humata_import_response],
      attrs[:discovered_at] || Time.now.iso8601,
      attrs[:uploaded_at],
      attrs[:completed_at],
      attrs[:last_checked_at]
    ])
  end

  def get_file_record(db, gdrive_id)
    result = db.execute('SELECT * FROM file_records WHERE gdrive_id = ?', [gdrive_id]).first
    return nil unless result
    
    # Get column names for indexing
    columns = db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
    
    # Convert to hash
    columns.zip(result).to_h
  end

  def get_all_files(db)
    results = db.execute('SELECT * FROM file_records')
    return [] if results.empty?
    
    # Get column names for indexing
    columns = db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
    
    # Convert all results to hashes
    results.map { |result| columns.zip(result).to_h }
  end

  it 'processes a complete Google Drive folder import' do
    # Mock Google Drive API responses
    service_mock = Class.new do
      def list_files(**kwargs)
        OpenStruct.new(
          files: [
            OpenStruct.new(
              id: 'file1',
              name: 'test1.pdf',
              mime_type: 'application/pdf',
              web_content_link: 'https://example.com/file1.pdf',
              size: 1024
            ),
            OpenStruct.new(
              id: 'file2',
              name: 'test2.pdf',
              mime_type: 'application/pdf',
              web_content_link: 'https://example.com/file2.pdf',
              size: 2048
            ),
            OpenStruct.new(
              id: 'file3',
              name: 'test3.pdf',
              mime_type: 'application/pdf',
              web_content_link: 'https://example.com/file3.pdf',
              size: 3072
            )
          ],
          next_page_token: nil
        )
      end
    end.new

    Google::Apis::DriveV3::DriveService.stub :new, service_mock do
      Google::Auth.stub :get_application_default, OpenStruct.new do
        # Phase 1: Discover
        discover = HumataImport::Commands::Discover.new(database: @db_path)
        discover.run([gdrive_url])

        # Verify discovery results
        files = get_all_files(@db)
        _(files.size).must_equal 3
        _(files.map { |f| f['gdrive_id'] }).must_equal %w[file1 file2 file3]
      end
    end

    # Mock HumataClient for upload
    upload_client = Class.new do
      def initialize
        @call_count = 0
      end
      
      def upload_file(url, folder_id)
        @call_count += 1
        {
          'data' => {
            'pdf' => {
              'id' => "humata-#{@call_count}"
            }
          }
        }
      end
      
      def verify
        # Mock verification - no-op for this test
      end
    end.new

    # Phase 2: Upload
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    upload.run(['--folder-id', folder_id], humata_client: upload_client)

    # Verify upload results
    files = get_all_files(@db)
    _(files.all? { |f| f['humata_id'] }).must_equal true
    _(files.all? { |f| f['processing_status'] == 'pending' }).must_equal true

    # Mock HumataClient for verification
    verify_client = Class.new do
      def get_file_status(humata_id)
        {
          'id' => humata_id,
          'status' => 'completed',
          'message' => 'File processed successfully'
        }
      end
      
      def verify
        # Mock verification - no-op for this test
      end
    end.new

    # Phase 3: Verify (reduce runtime by avoiding real sleeps)
    verify = HumataImport::Commands::Verify.new(database: @db_path)
    verify.run(['--timeout', '10', '--poll-interval', '0'], humata_client: verify_client)

    # Verify final results
    files = get_all_files(@db)
    _(files.all? { |f| f['processing_status'] == 'completed' }).must_equal true
    _(files.all? { |f| f['humata_verification_response'] }).must_equal true
  end

  it 'handles errors gracefully' do
    # Mock Google Drive API error
    service_mock = Class.new do
      def list_files(**kwargs)
        raise Google::Apis::Error, 'API error'
      end
    end.new

    Google::Apis::DriveV3::DriveService.stub :new, service_mock do
      Google::Auth.stub :get_application_default, OpenStruct.new do
        discover = HumataImport::Commands::Discover.new(database: @db_path)
        
        # Should raise the error instead of handling gracefully
        _(-> { discover.run([gdrive_url]) }).must_raise HumataImport::GoogleDriveError
        
        # No files should be added due to the error
        files = get_all_files(@db)
        _(files).must_be_empty
      end
    end

    # Create a test file for upload error handling
    create_test_file(@db)

    # Mock HumataClient upload error
    error_client = Class.new do
      def upload_file(url, folder_id)
        raise HumataImport::HumataError, 'Invalid request'
      end
      
      def verify
        # Mock verification - no-op for this test
      end
    end.new

    # Upload should handle error
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    upload.run(['--folder-id', folder_id, '--retry-delay', '0'], humata_client: error_client)

    files = get_all_files(@db)
    _(files.first['processing_status']).must_equal 'failed'
  end

  it 'supports resuming interrupted operations' do
    # Create some test files in various states
    create_test_file(@db, processing_status: 'completed', humata_id: 'done1')
    create_test_file(@db, processing_status: 'failed', humata_id: 'fail1')
    create_test_file(@db, processing_status: 'pending', humata_id: 'pending1')
    create_test_file(@db)  # Not yet uploaded

    # Mock successful API responses
    resume_client = Class.new do
      def initialize
        @call_count = 0
      end
      
      def upload_file(url, folder_id)
        @call_count += 1
        {
          'data' => {
            'pdf' => {
              'id' => "resume-#{@call_count}"
            }
          }
        }
      end
      
      def verify
        # Mock verification - no-op for this test
      end
    end.new

    # Upload should only process unstarted files
    upload = HumataImport::Commands::Upload.new(database: @db_path)
    upload.run(['--folder-id', folder_id], humata_client: resume_client)

    # Verify only the unstarted file was processed
    files = get_all_files(@db)
    _(files.size).must_equal 4
    
    # Check that only the unstarted file got a humata_id
    unstarted_files = files.select { |f| f['humata_id'] && f['humata_id'] != 'done1' && f['humata_id'] != 'fail1' && f['humata_id'] != 'pending1' }
    _(unstarted_files.size).must_equal 1
  end

  it 'handles verification with mixed statuses' do
    # Create test files with different statuses
    create_test_file(@db, processing_status: 'pending', humata_id: 'pending1')
    create_test_file(@db, processing_status: 'pending', humata_id: 'pending2')
    create_test_file(@db, processing_status: 'pending', humata_id: 'pending3')

    # Mock HumataClient with mixed responses
    verify_client = Class.new do
      def get_file_status(humata_id)
        case humata_id
        when 'pending1'
          { 'id' => humata_id, 'status' => 'completed' }
        when 'pending2'
          { 'id' => humata_id, 'status' => 'failed' }
        when 'pending3'
          { 'id' => humata_id, 'status' => 'processing' }
        end
      end
      
      def verify
        # Mock verification - no-op for this test
      end
    end.new

    # Run verification (avoid real sleep to keep test fast)
    verify = HumataImport::Commands::Verify.new(database: @db_path)
    verify.run(['--timeout', '1', '--poll-interval', '0'], humata_client: verify_client)

    # Verify results
    files = get_all_files(@db)
    _(files.size).must_equal 3
    
    completed = files.find { |f| f['humata_id'] == 'pending1' }
    failed = files.find { |f| f['humata_id'] == 'pending2' }
    processing = files.find { |f| f['humata_id'] == 'pending3' }
    
    _(completed['processing_status']).must_equal 'completed'
    _(failed['processing_status']).must_equal 'failed'
    _(processing['processing_status']).must_equal 'processing'
  end
end