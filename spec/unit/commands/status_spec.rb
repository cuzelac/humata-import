# frozen_string_literal: true

require 'spec_helper'

module HumataImport
  module Commands
    describe Status do
      def setup
        @db_path = File.join(Dir.tmpdir, "test_status_#{SecureRandom.hex(8)}.sqlite3")
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
      end

      def teardown
        File.delete(@db_path) if File.exist?(@db_path)
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

      it 'shows failed uploads with --failed-only option' do
        # Create test files in different states
        @db.execute(<<-SQL, ['success-file', 'success.pdf', 'https://example.com/success.pdf', 'completed', 'humata-1'])
          INSERT INTO file_records (gdrive_id, name, url, processing_status, humata_id) VALUES (?, ?, ?, ?, ?)
        SQL
        
        @db.execute(<<-SQL, ['failed-file', 'failed.pdf', 'https://example.com/failed.pdf', 'failed', nil, { error: 'API error', attempts: 3, last_attempt: '2023-01-01T12:00:00Z' }.to_json])
          INSERT INTO file_records (gdrive_id, name, url, processing_status, humata_id, humata_import_response) VALUES (?, ?, ?, ?, ?, ?)
        SQL

        status = Status.new(database: @db_path)
        
        # Capture output
        output = StringIO.new
        status.stub :puts, ->(msg) { output.puts(msg) } do
          status.run(['--failed-only'])
        end
        
        output_text = output.string
        
        # Should only show failed files
        _(output_text).must_include 'Failed Uploads Summary:'
        _(output_text).must_include 'Failed uploads: 1 files ready for retry'
        _(output_text).must_include 'failed.pdf'
        _(output_text).must_include 'API error'
        _(output_text).must_include 'Attempts: 3'
        _(output_text).must_include 'Last Attempt: 2023-01-01T12:00:00Z'
        
        # Should not show successful files
        _(output_text).wont_include 'success.pdf'
      end

      it 'shows overall status without --failed-only option' do
        # Create test files in different states
        @db.execute(<<-SQL, ['success-file', 'success.pdf', 'https://example.com/success.pdf', 'completed', 'humata-1'])
          INSERT INTO file_records (gdrive_id, name, url, processing_status, humata_id) VALUES (?, ?, ?, ?, ?)
        SQL
        
        @db.execute(<<-SQL, ['failed-file', 'failed.pdf', 'https://example.com/failed.pdf', 'failed', nil])
          INSERT INTO file_records (gdrive_id, name, url, processing_status, humata_id) VALUES (?, ?, ?, ?, ?)
        SQL

        status = Status.new(database: @db_path)
        
        # Capture output
        output = StringIO.new
        status.stub :puts, ->(msg) { output.puts(msg) } do
          status.run([])
        end
        
        output_text = output.string
        
        # Should show overall progress
        _(output_text).must_include 'Overall Progress:'
        _(output_text).must_include 'completed: 1 files'
        _(output_text).must_include 'failed: 1 files'
        
        # Should show both files in detailed status
        _(output_text).must_include 'success.pdf'
        _(output_text).must_include 'failed.pdf'
      end
    end
  end
end 