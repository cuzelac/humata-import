# frozen_string_literal: true

require 'spec_helper'

describe HumataImport::FileRecord do
  let(:db) { SQLite3::Database.new(':memory:') }
  let(:db_path) { 'file_record_test.db' }

  before do
    # Initialize schema in memory database
    HumataImport::Database.initialize_schema(db_path)
    @db = HumataImport::Database.connect(db_path)
  end

  after do
    @db.close
    File.delete(db_path) if File.exist?(db_path)
  end

  describe '.create' do
    it 'creates a new file record with required attributes' do
      result = HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'test_id_123',
        name: 'test_file.pdf',
        url: 'https://drive.google.com/file/d/test_id_123/view'
      )

      records = @db.execute("SELECT * FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['test_id_123'])
      assert_equal 1, records.size

      record = records.first
      assert_equal 'test_id_123', record[1] # gdrive_id
      assert_equal 'test_file.pdf', record[2] # name
      assert_equal 'https://drive.google.com/file/d/test_id_123/view', record[3] # url
      assert_equal 'pending', record[8] # upload_status
    end

    it 'creates a file record with optional attributes' do
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'test_id_456',
        name: 'test_file.docx',
        url: 'https://drive.google.com/file/d/test_id_456/view',
        size: 1024,
        mime_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        humata_folder_id: 'humata_folder_123',
        upload_status: 'completed'
      )

      records = @db.execute("SELECT * FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['test_id_456'])
      record = records.first

      assert_equal 1024, record[4] # size
      assert_equal 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', record[5] # mime_type
      assert_equal 'humata_folder_123', record[6] # humata_folder_id
      assert_equal 'completed', record[8] # upload_status
    end

    it 'ignores duplicate gdrive_id due to UNIQUE constraint' do
      # Create first record
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'duplicate_id',
        name: 'first_file.pdf',
        url: 'https://drive.google.com/file/d/duplicate_id/view'
      )

      # Try to create duplicate
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'duplicate_id',
        name: 'second_file.pdf',
        url: 'https://drive.google.com/file/d/duplicate_id/view'
      )

      records = @db.execute("SELECT * FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['duplicate_id'])
      assert_equal 1, records.size
      assert_equal 'first_file.pdf', records.first[2] # Should keep original name
    end

    it 'sets default upload_status to pending' do
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'test_id_default',
        name: 'test_file.pdf',
        url: 'https://drive.google.com/file/d/test_id_default/view'
      )

      records = @db.execute("SELECT upload_status FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['test_id_default'])
      assert_equal 'pending', records.first[0]
    end

    it 'sets discovered_at timestamp' do
      before_create = Time.now.getutc
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'test_id_timestamp',
        name: 'test_file.pdf',
        url: 'https://drive.google.com/file/d/test_id_timestamp/view'
      )
      after_create = Time.now.getutc

      records = @db.execute("SELECT discovered_at FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['test_id_timestamp'])
      discovered_at = Time.parse(records.first[0] + ' UTC')

      assert_operator discovered_at.to_i, :>=, before_create.to_i
      assert_operator discovered_at.to_i, :<=, after_create.to_i
    end
  end

  describe '.find_pending' do
    it 'returns only pending files' do
      # Create pending files
      HumataImport::FileRecord.create(@db, gdrive_id: 'pending_1', name: 'pending1.pdf', url: 'url1')
      HumataImport::FileRecord.create(@db, gdrive_id: 'pending_2', name: 'pending2.pdf', url: 'url2')

      # Create non-pending files
      HumataImport::FileRecord.create(@db, gdrive_id: 'completed_1', name: 'completed1.pdf', url: 'url3', upload_status: 'completed')
      HumataImport::FileRecord.create(@db, gdrive_id: 'failed_1', name: 'failed1.pdf', url: 'url4', upload_status: 'failed')

      pending_files = HumataImport::FileRecord.find_pending(@db)

      assert_equal 2, pending_files.size
      gdrive_ids = pending_files.map { |f| f[1] } # gdrive_id column
      assert_includes gdrive_ids, 'pending_1'
      assert_includes gdrive_ids, 'pending_2'
      refute_includes gdrive_ids, 'completed_1'
      refute_includes gdrive_ids, 'failed_1'
    end

    it 'returns empty array when no pending files exist' do
      HumataImport::FileRecord.create(@db, gdrive_id: 'completed_1', name: 'completed1.pdf', url: 'url1', upload_status: 'completed')

      pending_files = HumataImport::FileRecord.find_pending(@db)
      assert_empty pending_files
    end
  end

  describe '.update_status' do
    it 'updates upload status for existing file' do
      HumataImport::FileRecord.create(@db, gdrive_id: 'update_test', name: 'test.pdf', url: 'url1')

      HumataImport::FileRecord.update_status(@db, 'update_test', 'completed')

      records = @db.execute("SELECT upload_status FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['update_test'])
      assert_equal 'completed', records.first[0]
    end

    it 'updates last_checked_at timestamp' do
      HumataImport::FileRecord.create(@db, gdrive_id: 'timestamp_test', name: 'test.pdf', url: 'url1')

      before_update = Time.now.getutc
      HumataImport::FileRecord.update_status(@db, 'timestamp_test', 'processing')
      after_update = Time.now.getutc

      records = @db.execute("SELECT last_checked_at FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['timestamp_test'])
      last_checked_at = Time.parse(records.first[0] + ' UTC')

      assert_operator last_checked_at.to_i, :>=, before_update.to_i
      assert_operator last_checked_at.to_i, :<=, after_update.to_i
    end

    it 'does not affect other files when updating status' do
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_1', name: 'file1.pdf', url: 'url1')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_2', name: 'file2.pdf', url: 'url2')

      HumataImport::FileRecord.update_status(@db, 'file_1', 'completed')

      # Check file_1 was updated
      records = @db.execute("SELECT upload_status FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['file_1'])
      assert_equal 'completed', records.first[0]

      # Check file_2 was not affected
      records = @db.execute("SELECT upload_status FROM #{HumataImport::FileRecord::TABLE} WHERE gdrive_id = ?", ['file_2'])
      assert_equal 'pending', records.first[0]
    end
  end

  describe '.all' do
    it 'returns all file records' do
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_1', name: 'file1.pdf', url: 'url1')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_2', name: 'file2.pdf', url: 'url2')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_3', name: 'file3.pdf', url: 'url3')

      all_files = HumataImport::FileRecord.all(@db)
      assert_equal 3, all_files.size

      gdrive_ids = all_files.map { |f| f[1] } # gdrive_id column
      assert_includes gdrive_ids, 'file_1'
      assert_includes gdrive_ids, 'file_2'
      assert_includes gdrive_ids, 'file_3'
    end

    it 'returns empty array when no files exist' do
      all_files = HumataImport::FileRecord.all(@db)
      assert_empty all_files
    end
  end
end 