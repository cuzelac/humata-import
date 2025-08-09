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
  end
end 