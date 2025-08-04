# frozen_string_literal: true

module TestHelpers
  # Creates a test file record in the database
  # @param db [SQLite3::Database] The database connection
  # @param attrs [Hash] Attributes for the file record
  # @return [Hash] The created file record
  def create_test_file(db, attrs = {})
    defaults = {
      gdrive_id: SecureRandom.hex(16),
      name: "test_file_#{SecureRandom.hex(4)}.pdf",
      url: "https://drive.google.com/uc?id=#{SecureRandom.hex(16)}",
      size: 1024,
      mime_type: 'application/pdf',
      processing_status: nil,
      humata_id: nil,
      humata_import_response: nil,
      humata_verification_response: nil
    }

    attrs = defaults.merge(attrs)
    columns = attrs.keys.join(', ')
    placeholders = (['?'] * attrs.keys.size).join(', ')
    
    db.execute(<<-SQL, attrs.values)
      INSERT INTO file_records (#{columns})
      VALUES (#{placeholders})
    SQL

    attrs
  end

  # Creates multiple test file records
  # @param db [SQLite3::Database] The database connection
  # @param count [Integer] Number of records to create
  # @param attrs [Hash] Base attributes for the records
  # @return [Array<Hash>] The created file records
  def create_test_files(db, count, attrs = {})
    Array.new(count) { create_test_file(db, attrs) }
  end

  # Simulates a Google Drive API response
  # @return [Google::Apis::DriveV3::ListFilesResponse]
  def mock_gdrive_response(files)
    OpenStruct.new(
      files: files.map do |f|
        OpenStruct.new(
          id: f[:id] || SecureRandom.hex(16),
          name: f[:name] || "file_#{SecureRandom.hex(4)}.pdf",
          mime_type: f[:mime_type] || 'application/pdf',
          web_content_link: f[:url] || "https://drive.google.com/uc?id=#{SecureRandom.hex(16)}",
          size: f[:size] || 1024
        )
      end,
      next_page_token: nil
    )
  end

  # Simulates a Humata API response for file upload
  # @return [Hash] The mock response
  def mock_humata_upload_response(success: true)
    if success
      {
        'id' => SecureRandom.uuid,
        'status' => 'pending',
        'message' => 'File queued for processing'
      }
    else
      {
        'error' => 'Failed to import file',
        'message' => 'Invalid file format'
      }
    end
  end

  # Simulates a Humata API response for file status
  # @return [Hash] The mock response
  def mock_humata_status_response(status: 'completed')
    {
      'id' => SecureRandom.uuid,
      'status' => status,
      'message' => status == 'completed' ? 'File processed successfully' : 'Processing in progress'
    }
  end

  # Stubs Google Drive API list_files request
  # @param folder_id [String] The folder ID to mock
  # @param files [Array<Hash>] The files to return
  # @param error [Exception, nil] Optional error to raise
  def stub_gdrive_list_files(folder_id:, files: [], error: nil)
    params = {
      q: "'#{folder_id}' in parents",
      fields: 'nextPageToken, files(id, name, mimeType, webContentLink, size)',
      page_token: nil,
      supports_all_drives: true,
      include_items_from_all_drives: true
    }

    if error
      -> { raise error }
    else
      mock_gdrive_response(files)
    end
  end
end

class Minitest::Test
  include TestHelpers
end