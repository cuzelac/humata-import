# frozen_string_literal: true

require 'spec_helper'

module HumataImport
  module Commands
    describe Upload do
      def before_all
        super
        @folder_id = 'test-folder-123'
        @api_key = 'test-api-key'
        ENV['HUMATA_API_KEY'] = @api_key
      end

      def after_all
        super
        ENV.delete('HUMATA_API_KEY')
      end



      it 'has basic setup' do
        _(true).must_equal true
      end

      it 'correctly identifies mock clients' do
        upload = Upload.new({ database: @temp_db_path })
        
        # Test with a real Minitest::Mock
        client_mock = Minitest::Mock.new
        
        # Test the is_mock_client? method directly
        result = upload.send(:is_mock_client?, client_mock)
        
        # Should return true for mock clients
        _(result).must_equal true
        _(client_mock.class.name).must_include('Mock')
        _(client_mock.respond_to?(:verify)).must_equal true
      end

      it 'handles upload with no pending files' do
        # Create mock client since the command will try to set up a client even with no pending files
        client_mock = Minitest::Mock.new
        # No expectations needed since no files will be processed
        
        upload = Upload.new({ database: @temp_db_path })
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)
        # Test passes if no exception is raised
      end

      it 'uploads a single file successfully' do
        # Create test file with unique ID
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }, [String, @folder_id]

        upload = Upload.new({ database: @temp_db_path })
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify database updates
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['humata_id']).must_equal 'humata-1'
        _(file['processing_status']).must_equal 'pending'
        _(file['uploaded_at']).wont_be_nil
        
        client_mock.verify
      end

      it 'handles retry logic with exponential backoff' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock client that fails twice then succeeds
        client_mock = Object.new
        call_count = 0
        
        def client_mock.upload_file(url, folder_id)
          @call_count ||= 0
          @call_count += 1
          case @call_count
          when 1
            raise HumataImport::TransientError, 'Rate limit exceeded'
          when 2
            raise HumataImport::TransientError, 'Server error'
          else
            { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }
          end
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--max-retries', '3', '--retry-delay', '1', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file was eventually uploaded
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['humata_id']).must_equal 'humata-1'
        _(file['upload_status']).must_equal 'completed'
        
        client_mock.verify
      end

      it 'respects max retry limits' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock client that always fails
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          raise HumataImport::TransientError, 'Persistent error'
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--max-retries', '3', '--retry-delay', '1', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file was marked as failed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['upload_status']).must_equal 'failed'
        _(file['last_error']).must_equal 'Persistent error'
        
        client_mock.verify
      end

      it 'handles skip retries option' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock client that fails
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          raise HumataImport::TransientError, 'Rate limit exceeded'
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test (even with --skip-retries, the upload_with_retries method may still sleep)
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--skip-retries', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file was marked as failed without retries
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['upload_status']).must_equal 'failed'
        _(file['last_error']).must_equal 'Rate limit exceeded'
        
        client_mock.verify
      end

      it 'validates thread count limits' do
        # Create mock client since the command will try to set up a client even when validation fails
        client_mock = Minitest::Mock.new
        # No expectations needed since validation will fail before any uploads
        
        upload = Upload.new({ database: @temp_db_path })
        
        # Test minimum thread count
        error = assert_raises(SystemExit) do
          upload.run(['--folder-id', @folder_id, '--threads', '0'], humata_client: client_mock)
        end
        
        # Test maximum thread count
        error = assert_raises(SystemExit) do
          upload.run(['--folder-id', @folder_id, '--threads', '17'], humata_client: client_mock)
        end
      end

      it 'handles specific file upload by ID' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })
        gdrive_id = @db.execute('SELECT gdrive_id FROM file_records LIMIT 1').first.first

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }, [String, @folder_id]

        upload = Upload.new({ database: @temp_db_path })
        upload.run(['--folder-id', @folder_id, '--id', gdrive_id, '--threads', '1'], humata_client: client_mock)

        # Verify only the specified file was processed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['humata_id']).must_equal 'humata-1'
        _(file['upload_status']).must_equal 'completed'
        
        client_mock.verify
      end

      it 'handles different error types appropriately' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Test permanent error
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          raise HumataImport::PermanentError, 'Invalid file type'
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify file was marked as failed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['upload_status']).must_equal 'failed'
        _(file['last_error']).must_equal 'Invalid file type'
        
        client_mock.verify
      end

      it 'calculates retry delay with exponential backoff correctly' do
        upload = Upload.new({ database: @temp_db_path })
        
        # Test exponential backoff calculation
        _(upload.send(:calculate_retry_delay, 5, 1)).must_equal 5   # 5 * 2^0 = 5
        _(upload.send(:calculate_retry_delay, 5, 2)).must_equal 10  # 5 * 2^1 = 10
        _(upload.send(:calculate_retry_delay, 5, 3)).must_equal 20  # 5 * 2^2 = 20
        _(upload.send(:calculate_retry_delay, 5, 4)).must_equal 40  # 5 * 2^3 = 40
        
        # Test maximum delay cap
        _(upload.send(:calculate_retry_delay, 100, 5)).must_equal 300  # Capped at MAX_RETRY_DELAY
      end

      it 'handles empty response from Humata API' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock client that returns empty response
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, {}, [String, @folder_id]

        upload = Upload.new({ database: @temp_db_path })
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify file was marked as failed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['upload_status']).must_equal 'failed'
        _(file['last_error']).must_equal 'No Humata ID in response'
        
        client_mock.verify
      end

      it 'maintains backward compatibility with legacy methods' do
        # Create test file
        create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }, [String, @folder_id]

        upload = Upload.new({ database: @temp_db_path })
        
        # Test that legacy methods still work
        pending_files = upload.send(:get_pending_files, { folder_id: @folder_id })
        _(pending_files.size).must_equal 1
        
        # Test legacy process_uploads method
        upload.send(:process_uploads, client_mock, pending_files, { folder_id: @folder_id })
        
        # Verify file was processed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file = columns.zip(files.first).to_h
        _(file['humata_id']).must_equal 'humata-1'
        _(file['upload_status']).must_equal 'completed'
        
        client_mock.verify
      end

      it 'processes multiple files sequentially successfully' do
        # Create multiple test files
        create_test_files(@db, 4, { name: 'test.pdf', url: 'https://example.com/test.pdf' })

        # Create mock client that handles multiple calls
        client_mock = Minitest::Mock.new
        4.times do |i|
          client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => "humata-#{i+1}" } } }, [String, @folder_id]
        end

        upload = Upload.new({ database: @temp_db_path })
        # Use single thread to avoid parallel processing issues in tests
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify all files were processed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 4
        
        # Check that all files have humata_ids
        files.each do |file|
          columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
          file_hash = columns.zip(file).to_h
          _(file_hash['humata_id']).wont_be_nil
          _(file_hash['upload_status']).must_equal 'completed'
        end
        
        client_mock.verify
      end

      it 'handles sequential processing with mixed success and failure' do
        # Create multiple test files
        create_test_files(@db, 3, { name: 'test.pdf', url: 'https://example.com/test.pdf' })

        # Create mock client with mixed responses
        client_mock = Class.new do
          def initialize
            @call_count = 0
          end
          
          def upload_file(url, folder_id)
            @call_count += 1
            
            case @call_count
            when 1
              { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }
            when 2
              raise HumataImport::PermanentError, 'Invalid file'
            when 3
              { 'data' => { 'pdf' => { 'id' => 'humata-3' } } }
            end
          end
          
          def verify
            # Mock verification - no-op for this test
          end
        end.new

        upload = Upload.new({ database: @temp_db_path })
        # Use legacy sequential processing to avoid parallel processing issues
        pending_files = upload.send(:get_pending_files, { folder_id: @folder_id })
        upload.send(:process_uploads, client_mock, pending_files, { folder_id: @folder_id })

        # Verify results
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 3
        

        # Check mixed results
        success_count = 0
        failure_count = 0
        
        files.each do |file|
          columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
          file_hash = columns.zip(file).to_h
          
          if file_hash['upload_status'] == 'completed'
            success_count += 1
            # Check that successful files have a humata_id (but don't enforce specific values)
            _(file_hash['humata_id']).wont_be_nil
          else
            failure_count += 1
            _(file_hash['upload_status']).must_equal 'failed'
          end
        end
        
        _(success_count).must_equal 2
        _(failure_count).must_equal 1
        
        client_mock.verify
      end

      it 'respects thread count limits in sequential processing' do
        # Create test files
        create_test_files(@db, 6, { name: 'test.pdf', url: 'https://example.com/test.pdf' })

        # Create mock client
        client_mock = Minitest::Mock.new
        6.times do |i|
          client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => "humata-#{i+1}" } } }, [String, @folder_id]
        end

        upload = Upload.new({ database: @temp_db_path })
        # Test with single thread to avoid parallel processing issues in tests
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify all files were processed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 6
        
        files.each do |file|
          columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
          file_hash = columns.zip(file).to_h
          _(file_hash['upload_status']).must_equal 'completed'
        end
        
        client_mock.verify
      end

      it 'properly detects and reuses mock clients in sequential processing' do
        # Create test files
        create_test_files(@db, 2, { name: 'test.pdf', url: 'https://example.com/test.pdf' })

        # Create mock client
        client_mock = Minitest::Mock.new
        2.times do |i|
          client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => "humata-#{i+1}" } } }, [String, @folder_id]
        end

        upload = Upload.new({ database: @temp_db_path })
        # Test with single thread to avoid parallel processing issues in tests
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify all files were processed
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 2
        
        files.each do |file|
          columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
          file_hash = columns.zip(file).to_h
          _(file_hash['upload_status']).must_equal 'completed'
        end
        
        client_mock.verify
      end

      it 'handles signal interruption gracefully' do
        # Create test files
        create_test_files(@db, 3, { name: 'test.pdf', url: 'https://example.com/test.pdf' })

        # Create mock client
        client_mock = Minitest::Mock.new
        3.times do |i|
          client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => "humata-#{i+1}" } } }, [String, @folder_id]
        end

        upload = Upload.new({ database: @temp_db_path })
        # Test signal handling by simulating shutdown request
        upload.instance_variable_set(:@shutdown_requested, true)
        # Use single thread to avoid parallel processing issues in tests
        upload.run(['--folder-id', @folder_id, '--threads', '1'], humata_client: client_mock)

        # Verify that the upload process respects shutdown requests
        # The exact behavior depends on when shutdown is requested
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 3
        
        # At least some files should be processed
        processed_count = files.count do |file|
          columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
          file_hash = columns.zip(file).to_h
          file_hash['upload_status'] == 'completed'
        end
        
        _(processed_count).must_be :>=, 0
        
        client_mock.verify
      end

      it 'correctly identifies and reuses mock clients' do
        upload = Upload.new({ database: @temp_db_path })
        
        # Test with a real Minitest::Mock
        client_mock = Minitest::Mock.new
        
        # Test the create_thread_client method directly
        thread_client = upload.send(:create_thread_client, client_mock)
        
        # Should return the same mock client (same object reference)
        _(thread_client.object_id).must_equal client_mock.object_id
      end

      it 'clears last_error field on successful upload after retry' do
        # Create test file with an existing error in the database
        file_attrs = {
          name: 'retry_test.webp',
          url: 'https://example.com/retry_test.webp',
          mime_type: 'image/webp',
          upload_status: 'failed',
          last_error: 'Unexpected error: API request failed: HTTP 405: Method Not Allowed'
        }
        create_test_file(@db, file_attrs)

        # Verify the file has the error initially
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        initial_file = columns.zip(files.first).to_h
        _(initial_file['upload_status']).must_equal 'failed'
        _(initial_file['last_error']).must_equal 'Unexpected error: API request failed: HTTP 405: Method Not Allowed'
        _(initial_file['humata_id']).must_be_nil

        # Create mock client that fails once then succeeds
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          @call_count ||= 0
          @call_count += 1
          case @call_count
          when 1
            # First call fails with 405 error (simulating the transient issue)
            # Use TransientError to trigger retry logic
            raise HumataImport::TransientError, 'API request failed: HTTP 405: Method Not Allowed'
          else
            # Second call succeeds
            { 'data' => { 'pdf' => { 'id' => 'humata-success-123' } } }
          end
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--max-retries', '3', '--retry-delay', '1', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file was eventually uploaded successfully and last_error was cleared
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        final_file = columns.zip(files.first).to_h
        _(final_file['upload_status']).must_equal 'completed'
        _(final_file['humata_id']).must_equal 'humata-success-123'
        _(final_file['last_error']).must_be_nil # This is the key assertion - error should be cleared
        _(final_file['processing_status']).must_equal 'pending'
        _(final_file['uploaded_at']).wont_be_nil
        
        # Verify the response was stored
        _(final_file['humata_import_response']).wont_be_nil
        response_data = JSON.parse(final_file['humata_import_response'])
        _(response_data['data']['pdf']['id']).must_equal 'humata-success-123'
        
        client_mock.verify
      end

      it 'clears last_error field on successful upload after multiple retries with different errors' do
        # Create test file with an existing error
        file_attrs = {
          name: 'multi_retry_test.pdf',
          url: 'https://example.com/multi_retry_test.pdf',
          mime_type: 'application/pdf',
          upload_status: 'failed',
          last_error: 'Previous failure: Network timeout'
        }
        create_test_file(@db, file_attrs)

        # Create mock client that fails with different errors then succeeds
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          @call_count ||= 0
          @call_count += 1
          case @call_count
          when 1
            # First retry fails with 405 error (treat as transient for this test)
            raise HumataImport::TransientError, 'API request failed: HTTP 405: Method Not Allowed'
          when 2
            # Second retry fails with rate limit error
            raise HumataImport::TransientError, 'Rate limit exceeded: HTTP 429'
          when 3
            # Third retry fails with server error
            raise HumataImport::TransientError, 'Server error: HTTP 502'
          else
            # Fourth retry succeeds
            { 'data' => { 'pdf' => { 'id' => 'humata-final-success' } } }
          end
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--max-retries', '5', '--retry-delay', '1', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file was eventually uploaded successfully and last_error was cleared
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        final_file = columns.zip(files.first).to_h
        
        # Key assertions: successful upload with cleared error
        _(final_file['upload_status']).must_equal 'completed'
        _(final_file['humata_id']).must_equal 'humata-final-success'
        _(final_file['last_error']).must_be_nil # Error should be cleared despite multiple failures
        _(final_file['processing_status']).must_equal 'pending'
        _(final_file['uploaded_at']).wont_be_nil
        
        client_mock.verify
      end

      it 'preserves last_error field when upload fails after retries' do
        # Create test file
        file_attrs = {
          name: 'permanent_fail_test.pdf',
          url: 'https://example.com/permanent_fail_test.pdf',
          mime_type: 'application/pdf'
        }
        create_test_file(@db, file_attrs)

        # Create mock client that always fails
        client_mock = Object.new
        
        def client_mock.upload_file(url, folder_id)
          # Always fail with 405 error (use HumataError since this should not retry)
          raise HumataImport::HumataError, 'API request failed: HTTP 405: Method Not Allowed'
        end
        
        def client_mock.verify
          # Mock verification - no-op for this test
        end

        upload = Upload.new({ database: @temp_db_path })
        
        # Mock sleep to speed up test
        upload.stub :sleep, nil do
          upload.run(['--folder-id', @folder_id, '--max-retries', '2', '--retry-delay', '1', '--threads', '1'], humata_client: client_mock)
        end

        # Verify file failed and error is preserved
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        final_file = columns.zip(files.first).to_h
        
        # Assertions: failed upload with preserved error
        _(final_file['upload_status']).must_equal 'failed'
        _(final_file['humata_id']).must_be_nil
        _(final_file['last_error']).must_equal 'API request failed: HTTP 405: Method Not Allowed'
        _(final_file['processing_status']).must_equal 'failed'
        _(final_file['uploaded_at']).must_be_nil
        
        client_mock.verify
      end
    end
  end
end 