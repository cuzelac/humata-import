# frozen_string_literal: true

# Database management class for SQLite operations.
#
# This file provides the Database class for managing SQLite connections,
# schema initialization, and transaction management for the import tool.
#
# Dependencies:
#   - sqlite3 (gem)
#
# Configuration:
#   - Accepts database file path as argument
#
# Side Effects:
#   - Creates or modifies the SQLite database file
#   - Alters schema if needed
#
# @author Humata Import Team
# @since 0.1.0
require 'sqlite3'

module HumataImport
  # Database management class for SQLite operations.
  # Provides connection management and schema initialization for the import tool.
  class Database
    # Creates a new SQLite database connection.
    #
    # @param db_path [String] Path to the database file
    # @return [SQLite3::Database] Database connection instance
    def self.connect(db_path)
      SQLite3::Database.new(db_path)
    end

    # Initializes the database schema with required tables and indexes.
    #
    # @param db_path [String] Path to the database file
    # @return [void]
    def self.initialize_schema(db_path)
      db = connect(db_path)
      db.execute_batch <<-SQL
        CREATE TABLE IF NOT EXISTS file_records (
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
        );
        CREATE INDEX IF NOT EXISTS idx_files_status ON file_records(upload_status);
        CREATE INDEX IF NOT EXISTS idx_files_gdrive_id ON file_records(gdrive_id);
        CREATE INDEX IF NOT EXISTS idx_files_humata_id ON file_records(humata_id);
      SQL
      db.close
    end
  end
end