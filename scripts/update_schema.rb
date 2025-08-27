#!/usr/bin/env ruby
# frozen_string_literal: true

# Database Schema Update Script
#
# This script updates existing databases to match the current expected schema.
# It can be run safely multiple times (idempotent operations).
#
# Usage:
#   ruby scripts/update_schema.rb [database_path]
#   ruby scripts/update_schema.rb ./import_session.db
#
# If no database path is provided, it will use ./import_session.db

require 'sqlite3'
require 'fileutils'

class SchemaUpdater
  def initialize(db_path = './import_session.db')
    @db_path = db_path
    @db = nil
  end

  def run
    puts "🔧 Updating database schema: #{@db_path}"
    
    unless File.exist?(@db_path)
      puts "❌ Database file not found: #{@db_path}"
      puts "   Create it first by running a discovery command."
      exit 1
    end

    begin
      @db = SQLite3::Database.new(@db_path)
      
      # Backup the database first
      create_backup
      
      # Check current schema
      current_columns = get_current_columns
      puts "📋 Current columns: #{current_columns.join(', ')}"
      
      # Apply updates
      updates_applied = 0
      updates_applied += add_missing_column('humata_pages', 'INTEGER')
      updates_applied += add_missing_column('created_time', 'DATETIME')
      updates_applied += add_missing_column('modified_time', 'DATETIME')
      updates_applied += add_missing_column('duplicate_of_gdrive_id', 'TEXT')
      updates_applied += add_missing_column('file_hash', 'TEXT')
      
      # Add new indexes for duplicate detection
      updates_applied += add_missing_index('idx_files_duplicate_detection', 'size, name, mime_type')
      updates_applied += add_missing_index('idx_files_file_hash', 'file_hash')
      updates_applied += add_missing_index('idx_files_duplicate_of', 'duplicate_of_gdrive_id')
      
      if updates_applied > 0
        puts "✅ Schema update completed! Applied #{updates_applied} updates."
      else
        puts "✅ Schema is already up to date!"
      end
      
    rescue SQLite3::Exception => e
      puts "❌ Database error: #{e.message}"
      restore_backup if backup_exists?
      exit 1
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}"
      restore_backup if backup_exists?
      exit 1
    ensure
      @db&.close
      cleanup_backup
    end
  end

  private

  def create_backup
    backup_path = "#{@db_path}.backup.#{Time.now.to_i}"
    FileUtils.cp(@db_path, backup_path)
    @backup_path = backup_path
    puts "💾 Created backup: #{backup_path}"
  end

  def backup_exists?
    @backup_path && File.exist?(@backup_path)
  end

  def restore_backup
    return unless backup_exists?
    
    puts "🔄 Restoring backup due to error..."
    FileUtils.cp(@backup_path, @db_path)
    puts "✅ Backup restored"
  end

  def cleanup_backup
    return unless backup_exists?
    
    File.delete(@backup_path)
    puts "🧹 Cleaned up backup file"
  end

  def get_current_columns
    @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
  end

  def column_exists?(column_name)
    get_current_columns.include?(column_name)
  end

  def add_missing_column(column_name, column_type)
    if column_exists?(column_name)
      puts "✓ Column '#{column_name}' already exists"
      return 0
    end

    puts "➕ Adding column '#{column_name}' (#{column_type})..."
    
    begin
      @db.execute("ALTER TABLE file_records ADD COLUMN #{column_name} #{column_type}")
      puts "✅ Successfully added column '#{column_name}'"
      return 1
    rescue SQLite3::Exception => e
      puts "❌ Failed to add column '#{column_name}': #{e.message}"
      raise
    end
  end

  def add_missing_index(index_name, columns)
    if index_exists?(index_name)
      puts "✓ Index '#{index_name}' already exists"
      return 0
    end

    puts "➕ Adding index '#{index_name}' on columns: #{columns}..."
    
    begin
      @db.execute("CREATE INDEX #{index_name} ON file_records (#{columns})")
      puts "✅ Successfully added index '#{index_name}'"
      return 1
    rescue SQLite3::Exception => e
      puts "❌ Failed to add index '#{index_name}': #{e.message}"
      raise
    end
  end

  def index_exists?(index_name)
    @db.execute("PRAGMA index_list(file_records)").any? { |row| row[1] == index_name }
  end

  def verify_schema
    puts "\n🔍 Verifying final schema..."
    
    expected_columns = [
      'id', 'gdrive_id', 'name', 'url', 'size', 'mime_type',
      'humata_folder_id', 'humata_id', 'upload_status', 'processing_status',
      'last_error', 'humata_verification_response', 'humata_import_response',
      'humata_pages', 'created_time', 'modified_time', 'duplicate_of_gdrive_id', 'file_hash',
      'discovered_at', 'uploaded_at', 'completed_at', 'last_checked_at'
    ]
    
    current_columns = get_current_columns
    
    missing_columns = expected_columns - current_columns
    extra_columns = current_columns - expected_columns
    
    if missing_columns.any?
      puts "⚠️  Missing columns: #{missing_columns.join(', ')}"
    end
    
    if extra_columns.any?
      puts "ℹ️  Extra columns: #{extra_columns.join(', ')}"
    end
    
    if missing_columns.empty? && extra_columns.empty?
      puts "✅ Schema matches expected structure perfectly!"
    end
  end
end

# Main execution
if __FILE__ == $0
  db_path = ARGV[0] || './import_session.db'
  updater = SchemaUpdater.new(db_path)
  updater.run
end
