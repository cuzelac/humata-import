# frozen_string_literal: true

require 'spec_helper'

describe HumataImport::Commands::Discover do
  let(:options) { { database: 'discover_test.db', verbose: false } }
  let(:command) { HumataImport::Commands::Discover.new(options) }
  let(:db_path) { 'discover_test.db' }

  before do
    HumataImport::Database.initialize_schema(db_path)
  end

  after do
    File.delete(db_path) if File.exist?(db_path)
  end

  describe '#run' do
    it 'discovers files and stores them in database' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          mimeType: 'application/pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024
        },
        {
          id: 'file2',
          name: 'test2.docx',
          mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          webContentLink: 'https://drive.google.com/file/d/file2/view',
          size: 2048
        }
      ]
      
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
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
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: false, max_files: nil }]
      
      args = ['--no-recursive', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles max files limit' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: 5 }]
      
      args = ['--max-files', '5', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles timeout option' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      args = ['--timeout', '60', 'https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      gdrive_client.verify
    end

    it 'handles verbose output' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      verbose_options = { database: 'discover_test.db', verbose: true }
      verbose_command = HumataImport::Commands::Discover.new(verbose_options)
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      verbose_command.run(args, gdrive_client: gdrive_client)

      # Should still work with verbose logging
      records = verbose_command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles quiet output' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      quiet_options = { database: 'discover_test.db', quiet: true }
      quiet_command = HumataImport::Commands::Discover.new(quiet_options)
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      quiet_command.run(args, gdrive_client: gdrive_client)

      # Should still work with quiet logging
      records = quiet_command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles empty file list' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, [], ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 0, records.first[0]
      
      gdrive_client.verify
    end

    it 'handles files without optional attributes' do
      gdrive_client = Minitest::Mock.new
      minimal_files = [
        {
          id: 'minimal_file',
          name: 'minimal.pdf',
          mimeType: 'application/pdf',
          webContentLink: 'https://drive.google.com/file/d/minimal_file/view'
          # No size attribute
        }
      ]
      gdrive_client.expect :list_files, minimal_files, ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)

      records = command.db.execute("SELECT * FROM file_records WHERE gdrive_id = ?", ['minimal_file'])
      assert_equal 1, records.size
      
      file = records.first
      assert_equal 'minimal_file', file[1] # gdrive_id
      assert_equal 'minimal.pdf', file[2] # name
      assert_equal 'https://drive.google.com/file/d/minimal_file/view', file[3] # url
      assert_nil file[4] # size should be nil
      assert_equal 'application/pdf', file[5] # mime_type
      
      gdrive_client.verify
    end

    it 'ignores duplicate files due to database constraint' do
      gdrive_client = Minitest::Mock.new
      mock_files = [
        {
          id: 'file1',
          name: 'test1.pdf',
          mimeType: 'application/pdf',
          webContentLink: 'https://drive.google.com/file/d/file1/view',
          size: 1024
        }
      ]
      
      # Run discovery twice with same files
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      gdrive_client.expect :list_files, mock_files, ['https://drive.google.com/drive/folders/test_folder', { recursive: true, max_files: nil }]
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      command.run(args, gdrive_client: gdrive_client)
      command.run(args, gdrive_client: gdrive_client)

      # Should only have one copy of each file
      records = command.db.execute("SELECT COUNT(*) FROM file_records")
      assert_equal 1, records.first[0]
      
      gdrive_client.verify
    end
  end

  describe 'error handling' do
    it 'handles gdrive client errors gracefully' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, nil do
        raise StandardError, 'API Error'
      end
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      assert_raises(StandardError, 'API Error') do
        command.run(args, gdrive_client: gdrive_client)
      end
      
      gdrive_client.verify
    end

    it 'handles invalid URL format' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, nil do
        raise ArgumentError, 'Invalid URL'
      end
      
      args = ['invalid-url']
      
      assert_raises(ArgumentError, 'Invalid URL') do
        command.run(args, gdrive_client: gdrive_client)
      end
      
      gdrive_client.verify
    end

    it 'handles timeout errors' do
      gdrive_client = Minitest::Mock.new
      gdrive_client.expect :list_files, nil do
        raise Timeout::Error, 'Request timeout'
      end
      
      args = ['https://drive.google.com/drive/folders/test_folder']
      
      assert_raises(Timeout::Error, 'Request timeout') do
        command.run(args, gdrive_client: gdrive_client)
      end
      
      gdrive_client.verify
    end
  end
end 