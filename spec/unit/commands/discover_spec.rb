# frozen_string_literal: true

require 'spec_helper'

describe HumataImport::Commands::Discover do
  let(:options) { { database: File.join(Dir.tmpdir, "discover_test_#{SecureRandom.hex(8)}.db") } }
  let(:command) { HumataImport::Commands::Discover.new(options) }

  before do
    HumataImport::Database.initialize_schema(options[:database])
  end

  after do
    File.delete(options[:database]) if File.exist?(options[:database])
  end

  describe '#run' do
    it 'discovers files and stores them in database' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'test2.docx',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 2048,
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # Verify files were stored in database
      records = command.db.execute("SELECT * FROM file_records")
      assert_equal 2, records.size
      
      # Check first file
      file1 = records.find { |r| r[1] == 'file1' }
      assert_equal 'test1.pdf', file1[2] # name
      assert_equal 'https://drive.google.com/file/d/file1/view', file1[3] # url
      assert_equal 1024, file1[4] # size
      assert_equal 'application/pdf', file1[5] # mime_type
      assert_equal 'pending', file1[8] # upload_status
      
      # Check second file
      file2 = records.find { |r| r[1] == 'file2' }
      assert_equal 'test2.docx', file2[2] # name
      assert_equal 'https://drive.google.com/file/d/file2/view', file2[3] # url
      assert_equal 2048, file2[4] # size
      assert_equal 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', file2[5] # mime_type
      
      gdrive_client.verify
    end

    it 'handles non-recursive discovery' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', false, nil]
      
      args = ['--no-recursive', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles max files limit' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', true, 5]
      
      args = ['--max-files', '5', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles timeout option' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['--timeout', '60', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles verbose output' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      verbose_db = File.join(Dir.tmpdir, "discover_verbose_#{SecureRandom.hex(8)}.db")
      HumataImport::Database.initialize_schema(verbose_db)
      verbose_options = { database: verbose_db, verbose: true }
      verbose_command = HumataImport::Commands::Discover.new(verbose_options)
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      verbose_command.run(args, gdrive_client: gdrive_client)

      # Should still work with verbose logging
      records = verbose_command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    ensure
      File.delete(verbose_db) if defined?(verbose_db) && File.exist?(verbose_db)
    end

    it 'handles quiet output' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      quiet_db = File.join(Dir.tmpdir, "discover_quiet_#{SecureRandom.hex(8)}.db")
      HumataImport::Database.initialize_schema(quiet_db)
      quiet_options = { database: quiet_db, quiet: true }
      quiet_command = HumataImport::Commands::Discover.new(quiet_options)
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      quiet_command.run(args, gdrive_client: gdrive_client)

      # Should still work with quiet logging
      records = quiet_command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    ensure
      File.delete(quiet_db) if defined?(quiet_db) && File.exist?(quiet_db)
    end

    it 'handles empty file list' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # Should handle empty list gracefully
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles files without optional attributes' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view'
          # Missing size and mimeType
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # Should handle missing attributes gracefully
      records = command.db.execute("SELECT * FROM file_records")
      assert_equal 1, records.size
      
      file1 = records.first
      assert_equal 'file1', file1[1] # gdrive_id
      assert_equal 'test1.pdf', file1[2] # name
      assert_equal 'https://drive.google.com/file/d/file1/view', file1[3] # url
      assert_nil file1[4] # size should be nil
      assert_nil file1[5] # mime_type should be nil
      
      gdrive_client.verify
    end

    it 'ignores duplicate files due to database constraint' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view'
        }
      ]
      
      # Call list_files twice with the same files
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      # First run
      command.run(['https://drive.google.com/drive/folders/test_folder'], gdrive_client: gdrive_client)
      
      # Second run with same files
      command.run(['https://drive.google.com/drive/folders/test_folder'], gdrive_client: gdrive_client)

      # Should only have one record due to UNIQUE constraint
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 1, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles errors from GdriveClient' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, nil do
        raise HumataImport::GoogleDriveError, 'API error'
      end
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      # Should raise the error
      assert_raises(HumataImport::GoogleDriveError) do
        command.run(args, gdrive_client: gdrive_client)
      end
      
      gdrive_client.verify
    end

    it 'ensures idempotency by skipping existing files' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        }
      ]
      
      # First run
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      command.run(['https://drive.google.com/drive/folders/test_folder'], gdrive_client: gdrive_client)
      
      # Second run with same files
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      command.run(['https://drive.google.com/drive/folders/test_folder'], gdrive_client: gdrive_client)

      # Should only have one record due to idempotency
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 1, records.first[0]
      
      gdrive_client.verify
    end

    it 'collects enhanced metadata including created and modified times' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf',
          createdTime: '2024-01-01T10:00:00Z',
          modifiedTime: '2024-01-01T11:00:00Z'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # Verify enhanced metadata was stored
      records = command.db.execute("SELECT created_time, modified_time FROM file_records WHERE gdrive_id = 'file1'")
      record = records.first
      
      assert_equal '2024-01-01T10:00:00Z', record[0] # created_time
      assert_equal '2024-01-01T11:00:00Z', record[1] # modified_time
      
      gdrive_client.verify
    end

    it 'detects duplicates using file size + name + mime_type combination' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf',
          createdTime: '2024-01-01T10:00:00Z',
          modifiedTime: '2024-01-01T11:00:00Z'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/pdf',
          createdTime: '2024-01-02T10:00:00Z',
          modifiedTime: '2024-01-02T11:00:00Z'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # With default skip strategy, only the first file should be added
      records = command.db.execute("SELECT gdrive_id, duplicate_of_gdrive_id, file_hash FROM file_records ORDER BY discovered_at")
      
      assert_equal 1, records.size
      
      # First file (original) should be added
      assert_equal 'file1', records[0][0] # gdrive_id
      assert_nil records[0][1] # duplicate_of_gdrive_id should be nil
      assert records[0][2] # file_hash should be set
      
      gdrive_client.verify
    end

    it 'handles duplicate strategy skip (default)' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/pdf'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['--duplicate-strategy', 'skip', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # With skip strategy, only the first file should be added
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 1, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles duplicate strategy upload' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/pdf'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['--duplicate-strategy', 'upload', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # With upload strategy, both files should be added
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 2, records.first[0]
      
      # Second file should be marked as duplicate but still added
      duplicate_record = command.db.execute("SELECT duplicate_of_gdrive_id FROM file_records WHERE gdrive_id = 'file2'")
      assert_equal 'file1', duplicate_record.first[0]
      
      gdrive_client.verify
    end

    it 'handles duplicate strategy replace' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/pdf'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['--duplicate-strategy', 'replace', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # With replace strategy, both files should be added
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 2, records.first[0]
      
      # Second file should be marked as duplicate
      duplicate_record = command.db.execute("SELECT duplicate_of_gdrive_id FROM file_records WHERE gdrive_id = 'file2'")
      assert_equal 'file1', duplicate_record.first[0]
      
      gdrive_client.verify
    end

    it 'generates file_hash for all files' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'test2.docx',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 2048,
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # Verify file_hash is generated for all files
      records = command.db.execute("SELECT gdrive_id, file_hash FROM file_records ORDER BY gdrive_id")
      
      assert_equal 2, records.size
      
      records.each do |record|
        assert record[1] # file_hash should not be nil
        assert_equal 32, record[1].length # MD5 hash length
      end
      
      # Verify hashes are different for different files
      hash1 = records.find { |r| r[0] == 'file1' }[1]
      hash2 = records.find { |r| r[0] == 'file2' }[1]
      refute_equal hash1, hash2
      
      gdrive_client.verify
    end

    it 'shows duplicate information when --show-duplicates is used' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/pdf'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      # Create command with show_duplicates option
      show_duplicates_options = { database: File.join(Dir.tmpdir, "discover_show_duplicates_#{SecureRandom.hex(8)}.db") }
      HumataImport::Database.initialize_schema(show_duplicates_options[:database])
      show_duplicates_command = HumataImport::Commands::Discover.new(show_duplicates_options)
      
      args = ['--show-duplicates', 'https://drive.google.com/drive/folders/test_folder']
      show_duplicates_command.run(args, gdrive_client: gdrive_client)

      # With default skip strategy, only the first file should be added
      records = show_duplicates_command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 1, records.first[0]
      
      gdrive_client.verify
    ensure
      if defined?(show_duplicates_options) && show_duplicates_options[:database]
        File.delete(show_duplicates_options[:database]) if File.exist?(show_duplicates_options[:database])
      end
    end

    it 'distinguishes between different file types with same name and size' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024,
          mimeType: 'application/pdf'
        },
        {
          id: 'file2',
          name: 'document.pdf',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 1024,
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', true, nil]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      # These should NOT be considered duplicates due to different MIME types
      records = command.db.execute("SELECT gdrive_id, duplicate_of_gdrive_id FROM file_records ORDER BY gdrive_id")
      
      assert_equal 2, records.size
      
      # Neither file should be marked as duplicate
      records.each do |record|
        assert_nil record[1] # duplicate_of_gdrive_id should be nil
      end
      
      gdrive_client.verify
    end
  end
end 