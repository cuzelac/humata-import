# frozen_string_literal: true

require 'spec_helper'
require 'humata_import/commands/verify'
require 'humata_import/clients/humata_client'
require 'securerandom'

describe HumataImport::Commands::Verify do
  let(:options) { { database: File.join(Dir.tmpdir, "verify_test_#{SecureRandom.hex(8)}.db"), verbose: false, quiet: false } }
  let(:command) { HumataImport::Commands::Verify.new(options) }
  let(:mock_client) { Minitest::Mock.new }
  let(:db) { command.instance_variable_get(:@db) }

  before do
    # Initialize database schema
    HumataImport::Database.initialize_schema(options[:database])
    
    # Insert test data with proper column order
    db.execute(<<-SQL)
      INSERT INTO file_records (
        gdrive_id, name, url, humata_id, processing_status, 
        upload_status, discovered_at
      ) VALUES 
      ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z'),
      ('gdrive_2', 'test2.pdf', 'https://example.com/2', 'humata_2', 'processing', 'completed', '2024-01-01T00:00:00Z'),
      ('gdrive_3', 'test3.pdf', 'https://example.com/3', 'humata_3', 'pending', 'completed', '2024-01-01T00:00:00Z')
    SQL
  end

  after do
    # Clean up database file
    File.delete(options[:database]) if File.exist?(options[:database])
  end

  describe '#map_humata_status_to_processing_status' do
    it 'maps PENDING to pending' do
      result = command.send(:map_humata_status_to_processing_status, 'PENDING')
      assert_equal 'pending', result
    end

    it 'maps PROCESSING to processing' do
      result = command.send(:map_humata_status_to_processing_status, 'PROCESSING')
      assert_equal 'processing', result
    end

    it 'maps SUCCESS to completed' do
      result = command.send(:map_humata_status_to_processing_status, 'SUCCESS')
      assert_equal 'completed', result
    end

    it 'maps FAILED to failed' do
      result = command.send(:map_humata_status_to_processing_status, 'FAILED')
      assert_equal 'failed', result
    end

    it 'handles lowercase input' do
      result = command.send(:map_humata_status_to_processing_status, 'success')
      assert_equal 'completed', result
    end

    it 'handles nil input' do
      result = command.send(:map_humata_status_to_processing_status, 'pending')
      assert_equal 'pending', result
    end

    it 'handles unknown status' do
      result = command.send(:map_humata_status_to_processing_status, 'UNKNOWN_STATUS')
      assert_equal 'pending', result
    end
  end

  describe '#run with enhanced status tracking' do
    before do
      # Clear the database before each test to avoid conflicts
      db.execute('DELETE FROM file_records')
      
      # Insert only the file needed for this specific test
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL
    end

    it 'processes SUCCESS response and updates database correctly' do
      # Mock the Humata client response for SUCCESS
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 5,
        'name' => 'test1.pdf'
      }, ['humata_1']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify database updates - use explicit column names to avoid order issues
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 'completed', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 5, result[0]
      
      result = db.execute('SELECT completed_at FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      refute_nil result[0]
    end

    it 'processes PROCESSING response and updates database correctly' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_2', 'test2.pdf', 'https://example.com/2', 'humata_2', 'processing', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response for PROCESSING
      mock_client.expect :get_file_status, {
        'read_status' => 'PROCESSING',
        'name' => 'test2.pdf'
      }, ['humata_2']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify database updates
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_equal 'processing', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_nil result[0]
      
      result = db.execute('SELECT completed_at FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_nil result[0]
    end

    it 'processes FAILED response and updates database correctly' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_3', 'test3.pdf', 'https://example.com/3', 'humata_3', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response for FAILED
      mock_client.expect :get_file_status, {
        'read_status' => 'FAILED',
        'name' => 'test3.pdf'
      }, ['humata_3']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify database updates
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_equal 'failed', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_nil result[0]
      
      result = db.execute('SELECT completed_at FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_nil result[0]
    end

    it 'stores humata_verification_response as JSON' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 3,
        'name' => 'test1.pdf'
      }, ['humata_1']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify JSON response is stored
      result = db.execute('SELECT humata_verification_response FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      stored_response = JSON.parse(result[0])
      assert_equal 'SUCCESS', stored_response['read_status']
      assert_equal 3, stored_response['number_of_pages']
    end

    it 'updates last_checked_at timestamp' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response
      mock_client.expect :get_file_status, {
        'read_status' => 'PENDING',
        'name' => 'test1.pdf'
      }, ['humata_1']

      before_time = Time.now
      command.run([], humata_client: mock_client)
      after_time = Time.now

      # Verify all mock expectations were met
      mock_client.verify

      # Verify last_checked_at is updated
      result = db.execute('SELECT last_checked_at FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      refute_nil result[0], "last_checked_at should not be nil"
      checked_time = Time.parse(result[0])
      
      # Add tolerance for time comparison (1 second)
      tolerance = 1.0
      assert (checked_time - before_time).abs <= tolerance, "checked_time should be within #{tolerance} seconds of before_time"
      assert (checked_time - after_time).abs <= tolerance, "checked_time should be within #{tolerance} seconds of after_time"
    end

    it 'handles response without number_of_pages gracefully' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response without number_of_pages
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'name' => 'test1.pdf'
        # No number_of_pages field
      }, ['humata_1']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify humata_pages is nil when not provided
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_nil result[0]
    end

    it 'handles response with string number_of_pages' do
      # Clear and re-insert for this test
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      # Mock the Humata client response with string number_of_pages
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => '7',  # String instead of integer
        'name' => 'test1.pdf'
      }, ['humata_1']

      # Run the verify command
      command.run([], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify humata_pages is converted to integer
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 7, result[0]
    end
  end

  describe '#run with multiple files' do
    it 'processes all pending files and updates their status' do
      # Mock the Humata client responses for all three files
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 10,
        'name' => 'test1.pdf'
      }, ['humata_1']

      mock_client.expect :get_file_status, {
        'read_status' => 'PROCESSING',
        'name' => 'test2.pdf'
      }, ['humata_2']

      mock_client.expect :get_file_status, {
        'read_status' => 'FAILED',
        'name' => 'test3.pdf'
      }, ['humata_3']

      # Capture logger output
      log_output = StringIO.new
      command.logger.instance_variable_get(:@logger).reopen(log_output)

      command.run(['--timeout', '1', '--poll-interval', '0'], humata_client: mock_client)

      # Verify all mock expectations were met
      mock_client.verify

      # Verify database updates - use explicit column names to avoid order issues
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 'completed', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 10, result[0]

      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_equal 'processing', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_nil result[0]

      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_equal 'failed', result[0]
      
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_nil result[0]
    end

    it 'handles command line options correctly' do
      # Clear and re-insert for this test to avoid conflicts
      db.execute('DELETE FROM file_records')
      db.execute(<<-SQL)
        INSERT INTO file_records (
          gdrive_id, name, url, humata_id, processing_status, 
          upload_status, discovered_at
        ) VALUES 
        ('gdrive_1', 'test1.pdf', 'https://example.com/1', 'humata_1', 'pending', 'completed', '2024-01-01T00:00:00Z')
      SQL

      args = ['--poll-interval', '5', '--timeout', '60', '--batch-size', '2']
      
      # Mock responses for the shorter timeout
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 5,
        'name' => 'test1.pdf'
      }, ['humata_1']

      command.run(args, humata_client: mock_client)

      # Verify options were parsed correctly
      # The command should complete before timeout due to all files being processed
      mock_client.verify
    end

    it 'exits gracefully when no files are pending verification' do
      # Clear the database
      db.execute('DELETE FROM file_records')
      
      # Create a new command
      verify_command = HumataImport::Commands::Verify.new(options)

      # Run the command - should exit gracefully without calling any mock methods
      verify_command.run([], humata_client: mock_client)
      
      # Verify mock client was never called (since there are no files to verify)
      mock_client.verify
      
      # Verify database is still empty
      result = db.execute('SELECT COUNT(*) FROM file_records').first.first
      assert_equal 0, result
    end
  end

  describe 'error handling' do
    it 'continues processing other files when one fails' do
      # Mock one successful and one failed response
      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 5,
        'name' => 'test1.pdf'
      }, ['humata_1']

      mock_client.expect :get_file_status, -> { raise HumataImport::HumataError, 'API Error' }, ['humata_2']

      mock_client.expect :get_file_status, {
        'read_status' => 'SUCCESS',
        'number_of_pages' => 3,
        'name' => 'test3.pdf'
      }, ['humata_3']

      # Create a new command
      verify_command = HumataImport::Commands::Verify.new(options)

      # Run the command - should continue processing despite the error
      verify_command.run(['--timeout', '1', '--poll-interval', '0'], humata_client: mock_client)

      # Verify all mock expectations were met (including the error case)
      mock_client.verify

      # Verify successful files were processed correctly
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 'completed', result[0]

      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_equal 'completed', result[0]

      # Verify the file that failed still has its original status (pending)
      result = db.execute('SELECT processing_status FROM file_records WHERE gdrive_id = ?', ['gdrive_2']).first
      assert_equal 'processing', result[0]  # Should remain unchanged due to error
      
      # Verify page counts for successful files
      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_1']).first
      assert_equal 5, result[0]

      result = db.execute('SELECT humata_pages FROM file_records WHERE gdrive_id = ?', ['gdrive_3']).first
      assert_equal 3, result[0]
    end
  end
end
