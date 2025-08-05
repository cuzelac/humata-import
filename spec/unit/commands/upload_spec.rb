# frozen_string_literal: true

require 'spec_helper'

module HumataImport
  module Commands
    describe Upload do
      def setup
        @db_path = File.join(Dir.tmpdir, "test_upload_#{SecureRandom.hex(8)}.sqlite3")
        @db = SQLite3::Database.new(@db_path)
        @db.execute(<<-SQL)
          CREATE TABLE file_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            gdrive_id TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            size INTEGER,
            mime_type TEXT,
            humata_folder_id TEXT,
            humata_id TEXT,
            upload_status TEXT DEFAULT 'pending',
            processing_status TEXT,
            last_error TEXT,
            humata_verification_response TEXT,
            humata_import_response TEXT,
            discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            uploaded_at DATETIME,
            completed_at DATETIME,
            last_checked_at DATETIME
          )
        SQL

        @folder_id = 'test-folder-123'
        @api_key = 'test-api-key'
        ENV['HUMATA_API_KEY'] = @api_key
      end

      def teardown
        File.delete(@db_path) if File.exist?(@db_path)
        ENV.delete('HUMATA_API_KEY')
      end

      private

      # Helper method to get file record by gdrive_id
      def get_file_record(gdrive_id)
        result = @db.execute('SELECT * FROM file_records WHERE gdrive_id = ?', [gdrive_id]).first
        return nil unless result
        
        # Get column names for indexing
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        
        # Convert to hash
        columns.zip(result).to_h
      end

      it 'has basic setup' do
        _(true).must_equal true
      end

      it 'handles upload with no pending files' do
        upload = Upload.new(database: @db_path)
        
        # Mock the logger to capture output
        logger_mock = Minitest::Mock.new
        logger_mock.expect :info, nil, ["No pending files found for upload."]
        upload.stub :logger, logger_mock do
          upload.run(['--folder-id', @folder_id])
        end
        
        logger_mock.verify
      end

      it 'uploads successful files' do
        # Create test files
        create_test_file(@db, { gdrive_id: 'file1', name: 'test1.pdf', url: 'https://example.com/file1.pdf' })
        create_test_file(@db, { gdrive_id: 'file2', name: 'test2.pdf', url: 'https://example.com/file2.pdf' })

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'id' => 'humata-1', 'status' => 'pending' }, [String, @folder_id]
        client_mock.expect :upload_file, { 'id' => 'humata-2', 'status' => 'pending' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify database updates
        files = @db.execute('SELECT * FROM file_records ORDER BY gdrive_id')
        _(files.size).must_equal 2
        
        file1 = get_file_record('file1')
        file2 = get_file_record('file2')
        
        _(file1['humata_id']).must_equal 'humata-1'
        _(file2['humata_id']).must_equal 'humata-2'
        _(file1['processing_status']).must_equal 'pending'
        _(file2['processing_status']).must_equal 'pending'
        
        client_mock.verify
      end

      it 'handles upload with retries on failure' do
        # Create test file
        create_test_file(@db, { gdrive_id: 'file1', name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock HumataClient to fail twice then succeed
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, ->(*args) { raise HumataImport::Clients::HumataError, 'Rate limit exceeded' }, [String, @folder_id]
        client_mock.expect :upload_file, ->(*args) { raise HumataImport::Clients::HumataError, 'Rate limit exceeded' }, [String, @folder_id]
        client_mock.expect :upload_file, { 'id' => 'humata-1', 'status' => 'pending' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id, '--max-retries', '3', '--retry-delay', '0'], humata_client: client_mock)

        # Verify successful upload
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        file1 = get_file_record('file1')
        _(file1['humata_id']).must_equal 'humata-1'
        _(file1['processing_status']).must_equal 'pending'
        
        client_mock.verify
      end

      it 'fails upload after max retries' do
        # Create test file
        create_test_file(@db, { gdrive_id: 'file1', name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock HumataClient to always fail
        client_mock = Minitest::Mock.new
        4.times do  # 1 initial + 3 retries
          client_mock.expect :upload_file, ->(*args) { raise HumataImport::Clients::HumataError, 'API error' }, [String, @folder_id]
        end

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id, '--max-retries', '3', '--retry-delay', '0'], humata_client: client_mock)

        # Verify failure is recorded
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        file1 = get_file_record('file1')
        _(file1['processing_status']).must_equal 'failed'
        _(file1['humata_import_response']).must_include 'API error'
        
        client_mock.verify
      end

      it 'skips already processed files' do
        # Create files in different states
        create_test_file(@db, { gdrive_id: 'file1', name: 'test1.pdf', url: 'https://example.com/file1.pdf', processing_status: 'completed', humata_id: 'done1' })
        create_test_file(@db, { gdrive_id: 'file2', name: 'test2.pdf', url: 'https://example.com/file2.pdf', processing_status: 'failed', humata_id: 'fail1' })
        create_test_file(@db, { gdrive_id: 'file3', name: 'test3.pdf', url: 'https://example.com/file3.pdf' }) # Not processed

        # Create mock HumataClient - should only be called for unprocessed file
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'id' => 'humata-3', 'status' => 'pending' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify only unprocessed file was uploaded
        files = @db.execute('SELECT * FROM file_records ORDER BY gdrive_id')
        _(files.size).must_equal 3
        
        file1 = get_file_record('file1')
        file2 = get_file_record('file2')
        file3 = get_file_record('file3')
        
        _(file1['humata_id']).must_equal 'done1' # Already completed
        _(file2['humata_id']).must_equal 'fail1' # Already failed
        _(file3['humata_id']).must_equal 'humata-3' # Newly uploaded
        
        client_mock.verify
      end

      it 'handles batch processing' do
        # Create multiple test files
        create_test_files(@db, 5)

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        5.times do |i|
          client_mock.expect :upload_file, { 'id' => "humata-#{i}", 'status' => 'pending' }, [String, @folder_id]
        end

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id, '--batch-size', '2'], humata_client: client_mock)

        # Verify all files were uploaded
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 5
        _(files.all? { |f| 
          record = get_file_record(f[1]) # f[1] is gdrive_id
          record['humata_id'] && record['processing_status'] == 'pending'
        }).must_equal true
        
        client_mock.verify
      end

      it 'handles missing API key' do
        ENV.delete('HUMATA_API_KEY')
        
        upload = Upload.new(database: @db_path)
        
        # Mock logger to capture error
        logger_mock = Minitest::Mock.new
        logger_mock.expect :error, nil, ["HUMATA_API_KEY environment variable not set"]
        upload.stub :logger, logger_mock do
                  _(-> { upload.run(['--folder-id', @folder_id]) }).must_raise(SystemExit)
        end
        
        logger_mock.verify
      end

      it 'handles missing folder ID' do
        upload = Upload.new(database: @db_path)
        
        _(-> { upload.run([]) }).must_raise(SystemExit)
      end

      def test_upload_handles_unexpected_errors
        # Create test file
        create_test_file(@db, { gdrive_id: 'file1', name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Mock HumataClient to raise unexpected error
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, ->(*args) { raise StandardError, 'Unexpected error' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify error is handled gracefully
        files = @db.execute('SELECT * FROM file_records')
        assert_equal 1, files.size
        # File should remain unprocessed since it wasn't a HumataError
        
        client_mock.verify
      end

      it 'retries failed uploads on subsequent runs' do
        # Create a file that previously failed
        create_test_file(@db, { 
          gdrive_id: 'failed-file', 
          name: 'failed.pdf', 
          url: 'https://example.com/failed.pdf',
          processing_status: 'failed',
          humata_import_response: { error: 'API error', attempts: 3, last_attempt: Time.now.iso8601 }.to_json
        })

        # Create mock HumataClient that succeeds on retry
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'id' => 'humata-retry-success', 'status' => 'pending' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify the failed file was retried and succeeded
        file = get_file_record('failed-file')
        _(file['humata_id']).must_equal 'humata-retry-success'
        _(file['processing_status']).must_equal 'pending'
        
        client_mock.verify
      end

      it 'skips retries when --skip-retries is used' do
        # Create a file that previously failed
        create_test_file(@db, { 
          gdrive_id: 'failed-file', 
          name: 'failed.pdf', 
          url: 'https://example.com/failed.pdf',
          processing_status: 'failed',
          humata_import_response: { error: 'API error', attempts: 3 }.to_json
        })

        # Create mock HumataClient - should not be called
        client_mock = Minitest::Mock.new
        # No expectations set - should not be called

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id, '--skip-retries'], humata_client: client_mock)

        # Verify the failed file was not retried
        file = get_file_record('failed-file')
        _(file['humata_id']).must_be_nil
        _(file['processing_status']).must_equal 'failed'
        
        client_mock.verify
      end

      it 'distinguishes between new uploads and retries' do
        # Create both new and failed files
        create_test_file(@db, { gdrive_id: 'new-file', name: 'new.pdf', url: 'https://example.com/new.pdf' })
        create_test_file(@db, { 
          gdrive_id: 'failed-file', 
          name: 'failed.pdf', 
          url: 'https://example.com/failed.pdf',
          processing_status: 'failed',
          humata_import_response: { error: 'API error', attempts: 3 }.to_json
        })

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'id' => 'humata-new', 'status' => 'pending' }, [String, @folder_id]
        client_mock.expect :upload_file, { 'id' => 'humata-retry', 'status' => 'pending' }, [String, @folder_id]

        upload = Upload.new(database: @db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify both files were processed
        new_file = get_file_record('new-file')
        failed_file = get_file_record('failed-file')
        
        _(new_file['humata_id']).must_equal 'humata-new'
        _(failed_file['humata_id']).must_equal 'humata-retry'
        _(new_file['processing_status']).must_equal 'pending'
        _(failed_file['processing_status']).must_equal 'pending'
        
        client_mock.verify
      end
    end
  end
end 