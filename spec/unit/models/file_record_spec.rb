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

  describe '.generate_file_hash' do
    it 'generates hash from size, name, and mime_type' do
      hash1 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'application/pdf')
      hash2 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'application/pdf')
      
      assert_equal hash1, hash2
      assert_equal 32, hash1.length # MD5 hash length
    end

    it 'generates different hashes for different files' do
      hash1 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'application/pdf')
      hash2 = HumataImport::FileRecord.generate_file_hash(2048, 'test.pdf', 'application/pdf')
      hash3 = HumataImport::FileRecord.generate_file_hash(1024, 'different.pdf', 'application/pdf')
      
      refute_equal hash1, hash2
      refute_equal hash1, hash3
      refute_equal hash2, hash3
    end

    it 'handles nil mime_type' do
      hash1 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', nil)
      hash2 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'unknown')
      
      assert_equal hash1, hash2
    end

    it 'returns nil for nil size or name' do
      assert_nil HumataImport::FileRecord.generate_file_hash(nil, 'test.pdf', 'application/pdf')
      assert_nil HumataImport::FileRecord.generate_file_hash(1024, nil, 'application/pdf')
      assert_nil HumataImport::FileRecord.generate_file_hash(nil, nil, 'application/pdf')
    end

    it 'normalizes file names for consistent hashing' do
      hash1 = HumataImport::FileRecord.generate_file_hash(1024, 'Test.PDF', 'application/pdf')
      hash2 = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'application/pdf')
      hash3 = HumataImport::FileRecord.generate_file_hash(1024, '  test.pdf  ', 'application/pdf')
      
      assert_equal hash1, hash2
      assert_equal hash1, hash3
    end
  end

  describe '.find_duplicate' do
    before do
      # Create a base file for duplicate detection
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'original_123',
        name: 'document.pdf',
        url: 'url1',
        size: 1024,
        mime_type: 'application/pdf'
      )
    end

    it 'finds duplicate files based on file hash' do
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, 'test_hash', 'new_file_456')
      
      # Since we're using a real hash, we need to generate it from the original file
      file_hash = HumataImport::FileRecord.generate_file_hash(1024, 'document.pdf', 'application/pdf')
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, file_hash, 'new_file_456')
      
      assert duplicate_info[:duplicate_found]
      assert_equal 'original_123', duplicate_info[:duplicate_of_gdrive_id]
      assert_equal 'document.pdf', duplicate_info[:duplicate_name]
      assert_equal 1024, duplicate_info[:duplicate_size]
      assert_equal 'application/pdf', duplicate_info[:duplicate_mime_type]
    end

    it 'excludes the specified gdrive_id from search' do
      file_hash = HumataImport::FileRecord.generate_file_hash(1024, 'document.pdf', 'application/pdf')
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, file_hash, 'original_123')
      
      refute duplicate_info[:duplicate_found]
      assert_nil duplicate_info[:duplicate_of_gdrive_id]
    end

    it 'returns no duplicate when file hash is nil' do
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, nil, 'new_file_456')
      
      refute duplicate_info[:duplicate_found]
      assert_nil duplicate_info[:duplicate_of_gdrive_id]
    end

    it 'returns no duplicate when no matching files exist' do
      file_hash = HumataImport::FileRecord.generate_file_hash(9999, 'nonexistent.pdf', 'application/pdf')
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, file_hash, 'new_file_456')
      
      refute duplicate_info[:duplicate_found]
      assert_nil duplicate_info[:duplicate_of_gdrive_id]
    end

    it 'returns earliest discovered file when multiple duplicates exist' do
      # Create another file with same hash but different gdrive_id
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'duplicate_456',
        name: 'document.pdf',
        url: 'url2',
        size: 1024,
        mime_type: 'application/pdf'
      )
      
      file_hash = HumataImport::FileRecord.generate_file_hash(1024, 'document.pdf', 'application/pdf')
      duplicate_info = HumataImport::FileRecord.find_duplicate(@db, file_hash, 'new_file_789')
      
      assert duplicate_info[:duplicate_found]
      # Should return the earliest discovered file (original_123)
      assert_equal 'original_123', duplicate_info[:duplicate_of_gdrive_id]
    end
  end

  describe '.find_all_duplicates' do
    before do
      # Create files with some duplicates
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_1', name: 'doc1.pdf', url: 'url1', size: 1024, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_2', name: 'doc1.pdf', url: 'url2', size: 1024, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_3', name: 'doc2.pdf', url: 'url3', size: 2048, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_4', name: 'doc2.pdf', url: 'url4', size: 2048, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_5', name: 'doc2.pdf', url: 'url5', size: 2048, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'file_6', name: 'unique.pdf', url: 'url6', size: 512, mime_type: 'application/pdf')
    end

    it 'finds all duplicate groups' do
      duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
      
      assert_equal 2, duplicates.size
      
      # Group 1: 2 files with same hash (doc1.pdf)
      group1 = duplicates.find { |d| d[:count] == 2 }
      assert_equal 2, group1[:count]
      assert_equal 2, group1[:gdrive_ids].size
      assert_equal 2, group1[:names].size
      assert_equal 2, group1[:sizes].size
      assert_equal 2, group1[:mime_types].size
      
      # Group 2: 3 files with same hash (doc2.pdf)
      group2 = duplicates.find { |d| d[:count] == 3 }
      assert_equal 3, group2[:count]
      assert_equal 3, group2[:gdrive_ids].size
      assert_equal 3, group2[:names].size
      assert_equal 3, group2[:sizes].size
      assert_equal 3, group2[:mime_types].size
    end

    it 'orders duplicates by count descending' do
      duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
      
      assert_equal 3, duplicates.first[:count]  # doc2.pdf group
      assert_equal 2, duplicates.last[:count]   # doc1.pdf group
    end

    it 'includes file hash in results' do
      duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
      
      duplicates.each do |duplicate|
        assert duplicate[:file_hash]
        assert_equal 32, duplicate[:file_hash].length # MD5 hash length
      end
    end

    it 'returns empty array when no duplicates exist' do
      # Clear database and create only unique files
      @db.execute('DELETE FROM file_records')
      
      HumataImport::FileRecord.create(@db, gdrive_id: 'unique_1', name: 'file1.pdf', url: 'url1', size: 1024, mime_type: 'application/pdf')
      HumataImport::FileRecord.create(@db, gdrive_id: 'unique_2', name: 'file2.pdf', url: 'url2', size: 2048, mime_type: 'application/pdf')
      
      duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
      assert_empty duplicates
    end
  end

  describe 'duplicate detection in create method' do
    it 'sets duplicate_of_gdrive_id when duplicate is found' do
      # Create original file
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'original_123',
        name: 'document.pdf',
        url: 'url1',
        size: 1024,
        mime_type: 'application/pdf'
      )
      
      # Create duplicate file
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'duplicate_456',
        name: 'document.pdf',
        url: 'url2',
        size: 1024,
        mime_type: 'application/pdf'
      )
      
      # Check that duplicate file has duplicate_of_gdrive_id set
      records = @db.execute("SELECT duplicate_of_gdrive_id FROM file_records WHERE gdrive_id = ?", ['duplicate_456'])
      assert_equal 'original_123', records.first[0]
    end

    it 'sets file_hash for all created records' do
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'test_123',
        name: 'test.pdf',
        url: 'url1',
        size: 1024,
        mime_type: 'application/pdf'
      )
      
      records = @db.execute("SELECT file_hash FROM file_records WHERE gdrive_id = ?", ['test_123'])
      file_hash = records.first[0]
      
      assert file_hash
      assert_equal 32, file_hash.length # MD5 hash length
      
      # Verify hash matches expected value
      expected_hash = HumataImport::FileRecord.generate_file_hash(1024, 'test.pdf', 'application/pdf')
      assert_equal expected_hash, file_hash
    end

    it 'handles created_time and modified_time fields' do
      created_time = '2024-01-01T10:00:00Z'
      modified_time = '2024-01-01T11:00:00Z'
      
      HumataImport::FileRecord.create(
        @db,
        gdrive_id: 'time_test_123',
        name: 'time_test.pdf',
        url: 'url1',
        size: 1024,
        mime_type: 'application/pdf',
        created_time: created_time,
        modified_time: modified_time
      )
      
      records = @db.execute("SELECT created_time, modified_time FROM file_records WHERE gdrive_id = ?", ['time_test_123'])
      record = records.first
      
      assert_equal created_time, record[0]
      assert_equal modified_time, record[1]
    end
  end
end 