# frozen_string_literal: true

# Data model for tracking individual files in the import process.
#
# This file provides the FileRecord class for managing file records in the
# SQLite database, including creation, status updates, and queries.
#
# Dependencies:
#   - sqlite3 (gem)
#
# Configuration:
#   - Accepts database connection as argument
#
# Side Effects:
#   - Modifies the file_records table in the database
#
# @author Humata Import Team
# @since 0.1.0
require 'sqlite3'

module HumataImport
  # Model class for managing file records in the database.
  # Handles CRUD operations for file tracking during the import process.
  class FileRecord
    TABLE = 'file_records'

    # Creates a new file record in the database.
    #
    # @param db [SQLite3::Database] Database connection
    # @param gdrive_id [String] Google Drive file ID
    # @param name [String] File name
    # @param url [String] File URL
    # @param attrs [Hash] Optional attributes (size, mime_type, humata_folder_id, upload_status)
    # @return [void]
    def self.create(db, gdrive_id:, name:, url:, **attrs)
      db.execute("INSERT OR IGNORE INTO #{TABLE} (gdrive_id, name, url, size, mime_type, humata_folder_id, upload_status, discovered_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))",
        [gdrive_id, name, url, attrs[:size], attrs[:mime_type], attrs[:humata_folder_id], attrs[:upload_status] || 'pending'])
    end

    # Finds all files with pending upload status.
    #
    # @param db [SQLite3::Database] Database connection
    # @return [Array<Array>] Array of file records
    def self.find_pending(db)
      db.execute("SELECT * FROM #{TABLE} WHERE upload_status = 'pending'")
    end

    # Updates the upload status of a file record.
    #
    # @param db [SQLite3::Database] Database connection
    # @param gdrive_id [String] Google Drive file ID
    # @param status [String] New upload status
    # @return [void]
    def self.update_status(db, gdrive_id, status)
      db.execute("UPDATE #{TABLE} SET upload_status = ?, last_checked_at = datetime('now') WHERE gdrive_id = ?", [status, gdrive_id])
    end

    # Retrieves all file records from the database.
    #
    # @param db [SQLite3::Database] Database connection
    # @return [Array<Array>] Array of all file records
    def self.all(db)
      db.execute("SELECT * FROM #{TABLE}")
    end

    # Checks if a file record exists by gdrive_id.
    #
    # @param db [SQLite3::Database] Database connection
    # @param gdrive_id [String] Google Drive file ID
    # @return [Boolean] True if the record exists, false otherwise
    def self.exists?(db, gdrive_id)
      result = db.get_first_value("SELECT 1 FROM #{TABLE} WHERE gdrive_id = ? LIMIT 1", [gdrive_id])
      !result.nil?
    end
  end
end