#!/usr/bin/env ruby
# frozen_string_literal: true

# File Hash Population Script
#
# This script populates the file_hash column for existing database records
# that were created before the duplicate detection feature was implemented.
#
# Usage:
#   ruby scripts/populate_file_hashes.rb [database_path]
#   ruby scripts/populate_file_hashes.rb ./import_session.db
#
# If no database path is provided, it will use ./import_session.db

require 'sqlite3'
require 'digest'
require_relative '../lib/humata_import/models/file_record'

class FileHashPopulator
  def initialize(db_path = './import_session.db')
    @db_path = db_path
    @db = nil
  end

  def run
    puts "🔍 File Hash Population Script"
    puts "Database: #{@db_path}"
    
    unless File.exist?(@db_path)
      puts "❌ Database file not found: #{@db_path}"
      puts "   Create it first by running a discovery command."
      exit 1
    end

    begin
      @db = SQLite3::Database.new(@db_path)
      
      # Check if file_hash column exists
      unless column_exists?('file_hash')
        puts "❌ file_hash column does not exist in database"
        puts "   Run 'ruby scripts/update_schema.rb' first to add the column"
        exit 1
      end
      
      # Count records without file_hash
      records_without_hash = count_records_without_hash
      puts "📊 Found #{records_without_hash} records without file_hash"
      
      if records_without_hash == 0
        puts "✅ All records already have file_hash values"
        return
      end
      
      # Populate file hashes
      populate_file_hashes
      
    rescue SQLite3::Exception => e
      puts "❌ Database error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}"
      exit 1
    ensure
      @db&.close
    end
  end

  private

  def column_exists?(column_name)
    @db.execute('PRAGMA table_info(file_records)').any? { |col| col[1] == column_name }
  end

  def count_records_without_hash
    result = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE file_hash IS NULL")
    result || 0
  end

  def populate_file_hashes
    puts "\n🔄 Starting file hash population..."
    
    # Get all records without file_hash
    records = @db.execute("SELECT gdrive_id, name, size, mime_type FROM file_records WHERE file_hash IS NULL")
    
    updated = 0
    failed = 0
    
    records.each_with_index do |record, index|
      gdrive_id, name, size, mime_type = record
      
      begin
        # Generate file hash using the same logic as the FileRecord model
        file_hash = generate_file_hash(size, name, mime_type)
        
        if file_hash
          @db.execute("UPDATE file_records SET file_hash = ? WHERE gdrive_id = ?", [file_hash, gdrive_id])
          updated += 1
          
          # Progress reporting every 100 records
          if updated % 100 == 0
            puts "📊 Progress: #{updated}/#{records.size} records updated"
          end
        else
          failed += 1
          puts "⚠️  Could not generate hash for #{name} (gdrive_id: #{gdrive_id})"
        end
      rescue => e
        failed += 1
        puts "❌ Error updating #{name} (gdrive_id: #{gdrive_id}): #{e.message}"
      end
    end
    
    # Final summary
    puts "\n🎯 Population Summary:"
    puts "   Total records processed: #{records.size}"
    puts "   Successfully updated: #{updated}"
    puts "   Failed updates: #{failed}"
    
    if updated > 0
      puts "\n✅ File hash population completed successfully!"
      puts "   Duplicate detection is now fully functional for all records."
    end
    
    if failed > 0
      puts "\n⚠️  Some records could not be updated."
      puts "   Check the logs above for details."
    end
  end

  def generate_file_hash(size, name, mime_type)
    return nil if size.nil? || name.nil?
    
    # Create a hash combining size, name, and mime_type for reliable duplicate detection
    hash_input = "#{size}:#{name.downcase.strip}:#{mime_type || 'unknown'}"
    Digest::MD5.hexdigest(hash_input)
  end
end

# Main execution
if __FILE__ == $0
  db_path = ARGV[0] || './import_session.db'
  populator = FileHashPopulator.new(db_path)
  populator.run
end
