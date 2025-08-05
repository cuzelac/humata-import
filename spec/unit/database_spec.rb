# frozen_string_literal: true

require 'spec_helper'

describe HumataImport::Database do
  let(:db_path) { 'database_test.db' }

  after do
    File.delete(db_path) if File.exist?(db_path)
  end

  describe '.connect' do
    it 'creates a new SQLite database connection' do
      db = HumataImport::Database.connect(db_path)
      assert_instance_of SQLite3::Database, db
      assert File.exist?(db_path)
      db.close
    end

    it 'creates database file if it does not exist' do
      assert !File.exist?(db_path)
      
      db = HumataImport::Database.connect(db_path)
      assert File.exist?(db_path)
      
      db.close
    end

    it 'connects to existing database file' do
      # Create database first
      db1 = HumataImport::Database.connect(db_path)
      db1.close
      
      # Connect to existing database
      db2 = HumataImport::Database.connect(db_path)
      assert_instance_of SQLite3::Database, db2
      assert File.exist?(db_path)
      
      db2.close
    end
  end

  describe '.initialize_schema' do
    it 'creates file_records table with correct schema' do
      HumataImport::Database.initialize_schema(db_path)
      db = HumataImport::Database.connect(db_path)
      
      # Check table exists
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='file_records'")
      assert_equal 1, tables.size
      
      # Check table schema
      schema = db.execute("PRAGMA table_info(file_records)")
      column_names = schema.map { |col| col[1] }
      
      expected_columns = [
        'id', 'gdrive_id', 'name', 'url', 'size', 'mime_type',
        'humata_folder_id', 'humata_id', 'upload_status', 'processing_status',
        'last_error', 'humata_verification_response', 'humata_import_response',
        'discovered_at', 'uploaded_at', 'completed_at', 'last_checked_at'
      ]
      
      assert_equal expected_columns.sort, column_names.sort
      
      db.close
    end

    it 'creates required indexes' do
      HumataImport::Database.initialize_schema(db_path)
      db = HumataImport::Database.connect(db_path)
      
      # Check indexes exist
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index'")
      index_names = indexes.map { |idx| idx[0] }
      
      expected_indexes = [
        'idx_files_status',
        'idx_files_gdrive_id', 
        'idx_files_humata_id'
      ]
      
      expected_indexes.each do |index_name|
        assert_includes index_names, index_name
      end
      
      db.close
    end

    it 'sets correct column types and constraints' do
      HumataImport::Database.initialize_schema(db_path)
      db = HumataImport::Database.connect(db_path)
      schema = db.execute("PRAGMA table_info(file_records)")
      id_column = schema.find { |col| col[1] == 'id' }
      assert_equal 1, id_column[5] # PRIMARY KEY
      assert_equal 'INTEGER', id_column[2] # Type
      gdrive_id_column = schema.find { |col| col[1] == 'gdrive_id' }
      assert_equal 1, gdrive_id_column[3] # NOT NULL
      upload_status_column = schema.find { |col| col[1] == 'upload_status' }
      # SQLite returns default as quoted string
      assert_equal 'pending', upload_status_column[4].to_s.delete("'") # DEFAULT
      discovered_at_column = schema.find { |col| col[1] == 'discovered_at' }
      assert_equal 'CURRENT_TIMESTAMP', discovered_at_column[4] # DEFAULT
      db.close
    end

    it 'does not recreate existing schema' do
      # Initialize schema twice
      HumataImport::Database.initialize_schema(db_path)
      HumataImport::Database.initialize_schema(db_path)
      
      db = HumataImport::Database.connect(db_path)
      
      # Should still have correct schema
      tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='file_records'")
      assert_equal 1, tables.size
      
      db.close
    end

    it 'closes database connection after initialization' do
      db_mock = Minitest::Mock.new
      db_mock.expect :execute_batch, nil, [String]
      db_mock.expect :close, nil
      SQLite3::Database.stub :new, db_mock do
        HumataImport::Database.initialize_schema(db_path)
      end
      db_mock.verify
    end
  end

  describe 'database operations' do
    before do
      HumataImport::Database.initialize_schema(db_path)
      @db = HumataImport::Database.connect(db_path)
    end

    after do
      @db.close
    end

    it 'supports basic CRUD operations' do
      # Create
      @db.execute(
        "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
        ['test_id', 'test_file.pdf', 'https://example.com/file']
      )
      
      # Read
      records = @db.execute("SELECT * FROM file_records WHERE gdrive_id = ?", ['test_id'])
      assert_equal 1, records.size
      assert_equal 'test_id', records.first[1] # gdrive_id
      assert_equal 'test_file.pdf', records.first[2] # name
      
      # Update
      @db.execute(
        "UPDATE file_records SET upload_status = ? WHERE gdrive_id = ?",
        ['completed', 'test_id']
      )
      
      records = @db.execute("SELECT upload_status FROM file_records WHERE gdrive_id = ?", ['test_id'])
      assert_equal 'completed', records.first[0]
      
      # Delete
      @db.execute("DELETE FROM file_records WHERE gdrive_id = ?", ['test_id'])
      records = @db.execute("SELECT * FROM file_records WHERE gdrive_id = ?", ['test_id'])
      assert_empty records
    end

    it 'enforces unique constraint on gdrive_id' do
      @db.execute(
        "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
        ['duplicate_id', 'first.pdf', 'https://example.com/first']
      )
      # Try to insert duplicate
      assert_raises(SQLite3::ConstraintException) do
        @db.execute(
          "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
          ['duplicate_id', 'second.pdf', 'https://example.com/second']
        )
      end
    end

    it 'supports transactions' do
      @db.transaction do
        @db.execute(
          "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
          ['trans_1', 'trans1.pdf', 'https://example.com/trans1']
        )
        @db.execute(
          "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
          ['trans_2', 'trans2.pdf', 'https://example.com/trans2']
        )
      end
      records = @db.execute("SELECT COUNT(*) FROM file_records WHERE gdrive_id LIKE 'trans_%'")
      assert_equal 2, records.first[0]
    end

    it 'supports rollback on transaction failure' do
      begin
        @db.transaction do
          @db.execute(
            "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
            ['rollback_1', 'rollback1.pdf', 'https://example.com/rollback1']
          )
          # This will cause a constraint violation
          @db.execute(
            "INSERT INTO file_records (gdrive_id, name, url) VALUES (?, ?, ?)",
            ['rollback_1', 'rollback2.pdf', 'https://example.com/rollback2']
          )
        end
      rescue SQLite3::ConstraintException
        # Expected
      end
      records = @db.execute("SELECT COUNT(*) FROM file_records WHERE gdrive_id LIKE 'rollback_%'")
      assert_equal 0, records.first[0]
    end
  end
end 