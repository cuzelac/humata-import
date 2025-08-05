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

      def before_each
        super
        # Reset the database before each test
        @db.execute('DELETE FROM file_records')
        # Ensure results are returned as hashes
        @db.results_as_hash = true
      end

      it 'has basic setup' do
        _(true).must_equal true
      end

      it 'handles upload with no pending files' do
        upload = Upload.new(database: @temp_db_path)
        
        # Mock the logger to capture output
        logger_mock = Minitest::Mock.new
        logger_mock.expect :configure, nil, [Hash]
        logger_mock.expect :info, nil, [String] # Allow any info message
        upload.stub :logger, logger_mock do
          upload.run(['--folder-id', @folder_id])
        end
        
        logger_mock.verify
      end

      it 'uploads a single file successfully' do
        # Create test file with unique ID
        file_data = create_test_file(@db, { name: 'test1.pdf', url: 'https://example.com/file1.pdf' })

        # Create mock HumataClient
        client_mock = Minitest::Mock.new
        client_mock.expect :upload_file, { 'data' => { 'pdf' => { 'id' => 'humata-1' } } }, [String, @folder_id]

        upload = Upload.new(database: @temp_db_path)
        upload.run(['--folder-id', @folder_id], humata_client: client_mock)

        # Verify database updates
        files = @db.execute('SELECT * FROM file_records')
        _(files.size).must_equal 1
        
        file = files.first
        _(file['humata_id']).must_equal 'humata-1'
        _(file['processing_status']).must_equal 'pending'
        _(file['uploaded_at']).wont_be_nil
        
        client_mock.verify
      end
    end
  end
end 