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
require 'digest'

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
    # @param attrs [Hash] Optional attributes (size, mime_type, humata_folder_id, upload_status, created_time, modified_time)
    # @return [void]
    def self.create(db, gdrive_id:, name:, url:, **attrs)
      # Generate file hash for duplicate detection
      file_hash = generate_file_hash(attrs[:size], name, attrs[:mime_type])
      
      # Check for duplicates
      duplicate_info = find_duplicate(db, file_hash, gdrive_id)
      
      db.execute("INSERT OR IGNORE INTO #{TABLE} (gdrive_id, name, url, size, mime_type, humata_folder_id, upload_status, created_time, modified_time, duplicate_of_gdrive_id, file_hash, discovered_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
        [gdrive_id, name, url, attrs[:size], attrs[:mime_type], attrs[:humata_folder_id], attrs[:upload_status] || 'pending', attrs[:created_time], attrs[:modified_time], duplicate_info[:duplicate_of_gdrive_id], file_hash])
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

    # Deletes a file record by gdrive_id.
    #
    # @param db [SQLite3::Database] Database connection
    # @param gdrive_id [String] Google Drive file ID
    # @return [void]
    def self.delete(db, gdrive_id)
      db.execute("DELETE FROM #{TABLE} WHERE gdrive_id = ?", [gdrive_id])
    end

    # Finds duplicate files based on file hash.
    #
    # @param db [SQLite3::Database] Database connection
    # @param file_hash [String] The file hash to search for
    # @param exclude_gdrive_id [String] Google Drive ID to exclude from search
    # @return [Hash] Hash with duplicate information
    def self.find_duplicate(db, file_hash, exclude_gdrive_id = nil)
      return { duplicate_found: false, duplicate_of_gdrive_id: nil } if file_hash.nil?
      
      query = "SELECT gdrive_id, name, size, mime_type FROM #{TABLE} WHERE file_hash = ?"
      params = [file_hash]
      
      if exclude_gdrive_id
        query += " AND gdrive_id != ?"
        params << exclude_gdrive_id
      end
      
      query += " ORDER BY discovered_at ASC LIMIT 1"
      
      result = db.get_first_row(query, params)
      
      if result
        {
          duplicate_found: true,
          duplicate_of_gdrive_id: result[0],
          duplicate_name: result[1],
          duplicate_size: result[2],
          duplicate_mime_type: result[3]
        }
      else
        { duplicate_found: false, duplicate_of_gdrive_id: nil }
      end
    end

    # Generates a file hash for duplicate detection.
    #
    # @param size [Integer, nil] File size in bytes
    # @param name [String] File name
    # @param mime_type [String, nil] MIME type
    # @return [String] File hash for duplicate detection
    def self.generate_file_hash(size, name, mime_type)
      return nil if size.nil? || name.nil?
      
      # Create a hash combining size, name, and mime_type for reliable duplicate detection
      hash_input = "#{size}:#{name.downcase.strip}:#{mime_type || 'unknown'}"
      Digest::MD5.hexdigest(hash_input)
    end

    # Finds all duplicate files in the database.
    #
    # @param db [SQLite3::Database] Database connection
    # @return [Array<Hash>] Array of duplicate groups
    def self.find_all_duplicates(db)
      query = <<-SQL
        SELECT file_hash, COUNT(*) as count, 
               GROUP_CONCAT(gdrive_id) as gdrive_ids,
               GROUP_CONCAT(name) as names,
               GROUP_CONCAT(size) as sizes,
               GROUP_CONCAT(mime_type) as mime_types,
               GROUP_CONCAT(discovered_at) as discovered_dates
        FROM #{TABLE} 
        WHERE file_hash IS NOT NULL 
        GROUP BY file_hash 
        HAVING COUNT(*) > 1
        ORDER BY count DESC, file_hash
      SQL
      
      db.execute(query).map do |row|
        {
          file_hash: row[0],
          count: row[1],
          gdrive_ids: row[2].split(','),
          names: row[3].split(','),
          sizes: row[4].split(','),
          mime_types: row[5].split(','),
          discovered_dates: row[6].split(',')
        }
      end
    end
  end
end