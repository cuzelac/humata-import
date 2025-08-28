#!/usr/bin/env ruby
# frozen_string_literal: true

# Duplicate Relationship Population Script
#
# This script identifies existing duplicate files in the database and establishes
# the duplicate_of_gdrive_id relationships for the duplicate detection system.
#
# Usage:
#   ruby scripts/populate_duplicate_relationships.rb [database_path]
#   ruby scripts/populate_duplicate_relationships.rb ./import_session.db
#
# If no database path is provided, it will use ./import_session.db
#
# This script should be run AFTER populate_file_hashes.rb to ensure all files
# have file_hash values for duplicate detection.

require 'sqlite3'
require_relative '../lib/humata_import/models/file_record'

class DuplicateRelationshipPopulator
  def initialize(db_path = './import_session.db')
    @db_path = db_path
    @db = nil
  end

  def run
    puts "🔗 Duplicate Relationship Population Script"
    puts "Database: #{@db_path}"
    
    unless File.exist?(@db_path)
      puts "❌ Database file not found: #{@db_path}"
      puts "   Create it first by running a discovery command."
      exit 1
    end

    begin
      @db = SQLite3::Database.new(@db_path)
      
      # Check if required columns exist
      unless column_exists?('file_hash')
        puts "❌ file_hash column does not exist in database"
        puts "   Run 'ruby scripts/update_schema.rb' first to add the column"
        exit 1
      end
      
      unless column_exists?('duplicate_of_gdrive_id')
        puts "❌ duplicate_of_gdrive_id column does not exist in database"
        puts "   Run 'ruby scripts/update_schema.rb' first to add the column"
        exit 1
      end
      
      # Check if file hashes are populated
      records_without_hash = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE file_hash IS NULL")
      if records_without_hash > 0
        puts "❌ Found #{records_without_hash} records without file_hash values"
        puts "   Run 'ruby scripts/populate_file_hashes.rb' first to populate file hashes"
        exit 1
      end
      
      # Count records that need duplicate relationships
      records_needing_relationships = count_records_needing_relationships
      puts "📊 Found #{records_needing_relationships} records that need duplicate relationships established"
      
      if records_needing_relationships == 0
        puts "✅ All records already have proper duplicate relationships"
        return
      end
      
      # Populate duplicate relationships
      populate_duplicate_relationships
      
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

  def count_records_needing_relationships
    result = @db.get_first_value(<<-SQL)
      SELECT COUNT(*) FROM file_records 
      WHERE file_hash IS NOT NULL 
      AND duplicate_of_gdrive_id IS NULL
    SQL
    result || 0
  end

  def populate_duplicate_relationships
    puts "\n🔄 Starting duplicate relationship population..."
    
    # Find all duplicate groups
    duplicate_groups = find_duplicate_groups
    
    if duplicate_groups.empty?
      puts "ℹ️  No duplicate groups found - all files are unique"
      return
    end
    
    puts "📋 Found #{duplicate_groups.size} duplicate groups to process"
    
    updated = 0
    skipped = 0
    
    duplicate_groups.each_with_index do |group, group_index|
      puts "   Processing group #{group_index + 1}/#{duplicate_groups.size}: #{group[:count]} files"
      
      # Sort files by discovered_at to establish the "original" file
      files_in_group = get_files_in_group(group[:file_hash])
      files_in_group.sort_by! { |f| f[:discovered_at] || '1970-01-01' }
      
      # First file is the "original", others are duplicates
      original_file = files_in_group.first
      duplicate_files = files_in_group[1..-1]
      
      puts "      Original: #{original_file[:name]} (discovered: #{original_file[:discovered_at]})"
      puts "      Duplicates: #{duplicate_files.size} files"
      
      # Update duplicate files to point to the original
      duplicate_files.each do |duplicate_file|
        begin
          @db.execute(
            "UPDATE file_records SET duplicate_of_gdrive_id = ? WHERE gdrive_id = ?",
            [original_file[:gdrive_id], duplicate_file[:gdrive_id]]
          )
          updated += 1
          
          if updated % 100 == 0
            puts "      📊 Progress: #{updated} relationships established"
          end
        rescue => e
          puts "      ❌ Error updating #{duplicate_file[:name]}: #{e.message}"
          skipped += 1
        end
      end
    end
    
    # Final summary
    puts "\n🎯 Population Summary:"
    puts "   Duplicate groups processed: #{duplicate_groups.size}"
    puts "   Relationships established: #{updated}"
    puts "   Failed updates: #{skipped}"
    
    if updated > 0
      puts "\n✅ Duplicate relationship population completed successfully!"
      puts "   All existing duplicate files are now properly linked."
    end
    
    if skipped > 0
      puts "\n⚠️  Some relationships could not be established."
      puts "   Check the logs above for details."
    end
  end

  def find_duplicate_groups
    query = <<-SQL
      SELECT file_hash, COUNT(*) as count
      FROM file_records 
      WHERE file_hash IS NOT NULL 
      GROUP BY file_hash 
      HAVING COUNT(*) > 1
      ORDER BY count DESC, file_hash
    SQL
    
    @db.execute(query).map do |row|
      {
        file_hash: row[0],
        count: row[1]
      }
    end
  end

  def get_files_in_group(file_hash)
    query = <<-SQL
      SELECT gdrive_id, name, discovered_at
      FROM file_records 
      WHERE file_hash = ?
      ORDER BY discovered_at ASC
    SQL
    
    @db.execute(query, [file_hash]).map do |row|
      {
        gdrive_id: row[0],
        name: row[1],
        discovered_at: row[2]
      }
    end
  end
end

# Main execution
if __FILE__ == $0
  db_path = ARGV[0] || './import_session.db'
  populator = DuplicateRelationshipPopulator.new(db_path)
  populator.run
end
