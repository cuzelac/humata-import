#!/usr/bin/env ruby
# frozen_string_literal: true

# Production Validation Script for Duplicate Detection System
#
# This script validates that the duplicate detection system is ready for production
# by testing all core functionality with real data from the database.
#
# Usage:
#   ruby scripts/production_validation.rb [database_path]
#   ruby scripts/production_validation.rb ./import_session.db

require 'sqlite3'
require_relative '../lib/humata_import/models/file_record'

class ProductionValidator
  def initialize(db_path = './import_session.db')
    @db_path = db_path
    @db = nil
    @validation_results = []
  end

  def run
    puts "🏭 Production Validation for Duplicate Detection System"
    puts "Database: #{@db_path}"
    puts "=" * 60
    
    unless File.exist?(@db_path)
      puts "❌ Database file not found: #{@db_path}"
      exit 1
    end

    begin
      @db = SQLite3::Database.new(@db_path)
      
      # Core System Validation
      validate_core_system
      
      # Performance Validation
      validate_performance
      
      # Data Integrity Validation
      validate_data_integrity
      
      # Error Handling Validation
      validate_error_handling
      
      # Production Readiness Assessment
      assess_production_readiness
      
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

  def validate_core_system
    puts "\n🔧 Core System Validation"
    puts "-" * 30
    
    # Test 1: File hash population
    total_files = @db.get_first_value("SELECT COUNT(*) FROM file_records")
    files_with_hash = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE file_hash IS NOT NULL")
    
    if total_files == files_with_hash
      puts "✅ File hash population: COMPLETE (#{total_files} files)"
      @validation_results << { component: 'File Hash Population', status: 'PASS', details: "#{total_files} files processed" }
    else
      puts "❌ File hash population: INCOMPLETE (#{files_with_hash}/#{total_files} files)"
      @validation_results << { component: 'File Hash Population', status: 'FAIL', details: "Missing hashes for #{total_files - files_with_hash} files" }
    end
    
    # Test 2: Duplicate detection functionality
    duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
    if duplicates.any?
      puts "✅ Duplicate detection: WORKING (#{duplicates.size} groups found)"
      @validation_results << { component: 'Duplicate Detection', status: 'PASS', details: "#{duplicates.size} duplicate groups identified" }
    else
      puts "⚠️  Duplicate detection: NO DUPLICATES FOUND"
      @validation_results << { component: 'Duplicate Detection', status: 'WARNING', details: 'No duplicate files in database' }
    end
    
    # Test 3: Database schema
    expected_columns = ['file_hash', 'duplicate_of_gdrive_id', 'created_time', 'modified_time']
    missing_columns = []
    
    expected_columns.each do |column|
      unless column_exists?(column)
        missing_columns << column
      end
    end
    
    if missing_columns.empty?
      puts "✅ Database schema: COMPLETE (all required columns present)"
      @validation_results << { component: 'Database Schema', status: 'PASS', details: 'All required columns present' }
    else
      puts "❌ Database schema: INCOMPLETE (missing: #{missing_columns.join(', ')})"
      @validation_results << { component: 'Database Schema', status: 'FAIL', details: "Missing columns: #{missing_columns.join(', ')}" }
    end
  end

  def validate_performance
    puts "\n⚡ Performance Validation"
    puts "-" * 30
    
    # Test 1: Duplicate detection performance
    start_time = Time.now
    duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
    end_time = Time.now
    detection_time = end_time - start_time
    
    if detection_time < 0.1
      puts "✅ Duplicate detection: EXCELLENT (#{detection_time.round(3)}s)"
      @validation_results << { component: 'Detection Performance', status: 'PASS', details: "#{detection_time.round(3)}s for #{duplicates.size} groups" }
    elsif detection_time < 1.0
      puts "✅ Duplicate detection: GOOD (#{detection_time.round(3)}s)"
      @validation_results << { component: 'Detection Performance', status: 'PASS', details: "#{detection_time.round(3)}s for #{duplicates.size} groups" }
    else
      puts "⚠️  Duplicate detection: SLOW (#{detection_time.round(3)}s)"
      @validation_results << { component: 'Detection Performance', status: 'WARNING', details: "#{detection_time.round(3)}s for #{duplicates.size} groups" }
    end
    
    # Test 2: Individual lookup performance
    start_time = Time.now
    sample_hash = @db.get_first_value("SELECT file_hash FROM file_records WHERE file_hash IS NOT NULL LIMIT 1")
    if sample_hash
      100.times do
        HumataImport::FileRecord.find_duplicate(@db, sample_hash, 'test_file')
      end
    end
    end_time = Time.now
    lookup_time = end_time - start_time
    avg_lookup = (lookup_time / 100 * 1000).round(1)
    
    if avg_lookup < 1.0
      puts "✅ Individual lookups: EXCELLENT (#{avg_lookup}ms average)"
      @validation_results << { component: 'Lookup Performance', status: 'PASS', details: "#{avg_lookup}ms average per lookup" }
    elsif avg_lookup < 10.0
      puts "✅ Individual lookups: GOOD (#{avg_lookup}ms average)"
      @validation_results << { component: 'Lookup Performance', status: 'PASS', details: "#{avg_lookup}ms average per lookup" }
    else
      puts "⚠️  Individual lookups: SLOW (#{avg_lookup}ms average)"
      @validation_results << { component: 'Lookup Performance', status: 'WARNING', details: "#{avg_lookup}ms average per lookup" }
    end
  end

  def validate_data_integrity
    puts "\n🔍 Data Integrity Validation"
    puts "-" * 30
    
    # Test 1: File hash validity
    invalid_hashes = @db.get_first_value(<<-SQL)
      SELECT COUNT(*) FROM file_records 
      WHERE file_hash IS NOT NULL 
      AND length(file_hash) != 32
    SQL
    
    if invalid_hashes == 0
      puts "✅ File hash validity: ALL VALID (32-character MD5 hashes)"
      @validation_results << { component: 'File Hash Validity', status: 'PASS', details: 'All hashes are valid MD5 format' }
    else
      puts "❌ File hash validity: #{invalid_hashes} INVALID HASHES"
      @validation_results << { component: 'File Hash Validity', status: 'FAIL', details: "#{invalid_hashes} invalid hashes found" }
    end
    
    # Test 2: Duplicate consistency
    duplicates = HumataImport::FileRecord.find_all_duplicates(@db)
    inconsistent_duplicates = 0
    
    duplicates.each do |group|
      hash = group[:file_hash]
      count = group[:count]
      
      # Verify the count matches actual database records
      actual_count = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE file_hash = ?", [hash])
      if actual_count != count
        inconsistent_duplicates += 1
      end
    end
    
    if inconsistent_duplicates == 0
      puts "✅ Duplicate consistency: PERFECT (all counts accurate)"
      @validation_results << { component: 'Duplicate Consistency', status: 'PASS', details: 'All duplicate counts are accurate' }
    else
      puts "❌ Duplicate consistency: #{inconsistent_duplicates} INCONSISTENCIES"
      @validation_results << { component: 'Duplicate Consistency', status: 'FAIL', details: "#{inconsistent_duplicates} count inconsistencies found" }
    end
    
    # Test 3: Required metadata presence
    files_without_size = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE size IS NULL")
    files_without_name = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE name IS NULL")
    
    if files_without_size == 0 && files_without_name == 0
      puts "✅ Required metadata: COMPLETE (all files have size and name)"
      @validation_results << { component: 'Required Metadata', status: 'PASS', details: 'All files have size and name' }
    else
      puts "⚠️  Required metadata: INCOMPLETE (#{files_without_size} without size, #{files_without_name} without name)"
      @validation_results << { component: 'Required Metadata', status: 'WARNING', details: "#{files_without_size} without size, #{files_without_name} without name" }
    end
  end

  def validate_error_handling
    puts "\n🚨 Error Handling Validation"
    puts "-" * 30
    
    # Test 1: Nil file hash handling
    begin
      result = HumataImport::FileRecord.find_duplicate(@db, nil, 'test_file')
      if !result[:duplicate_found]
        puts "✅ Nil hash handling: WORKING (properly handles nil values)"
        @validation_results << { component: 'Nil Hash Handling', status: 'PASS', details: 'Properly handles nil file hashes' }
      else
        puts "❌ Nil hash handling: BROKEN (returns false positive)"
        @validation_results << { component: 'Nil Hash Handling', status: 'FAIL', details: 'Returns false positive for nil hash' }
      end
    rescue => e
      puts "❌ Nil hash handling: ERROR (#{e.message})"
      @validation_results << { component: 'Nil Hash Handling', status: 'ERROR', details: e.message }
    end
    
    # Test 2: Empty string handling
    begin
      result = HumataImport::FileRecord.find_duplicate(@db, '', 'test_file')
      if !result[:duplicate_found]
        puts "✅ Empty string handling: WORKING (properly handles empty strings)"
        @validation_results << { component: 'Empty String Handling', status: 'PASS', details: 'Properly handles empty string hashes' }
      else
        puts "❌ Empty string handling: BROKEN (returns false positive)"
        @validation_results << { component: 'Empty String Handling', status: 'FAIL', details: 'Returns false positive for empty string' }
      end
    rescue => e
      puts "❌ Empty string handling: ERROR (#{e.message})"
      @validation_results << { component: 'Empty String Handling', status: 'ERROR', details: e.message }
    end
  end

  def assess_production_readiness
    puts "\n🎯 Production Readiness Assessment"
    puts "=" * 60
    
    passed = @validation_results.count { |r| r[:status] == 'PASS' }
    warnings = @validation_results.count { |r| r[:status] == 'WARNING' }
    failed = @validation_results.count { |r| r[:status] == 'FAIL' }
    errors = @validation_results.count { |r| r[:status] == 'ERROR' }
    
    puts "   Validation Results:"
    puts "   ✅ Passed: #{passed}"
    puts "   ⚠️  Warnings: #{warnings}"
    puts "   ❌ Failed: #{failed}"
    puts "   🚨 Errors: #{errors}"
    
    puts "\n   Detailed Results:"
    @validation_results.each do |result|
      status_icon = case result[:status]
                    when 'PASS' then '✅'
                    when 'WARNING' then '⚠️'
                    when 'FAIL' then '❌'
                    when 'ERROR' then '🚨'
                    else '❓'
                    end
      
      puts "   #{status_icon} #{result[:component]}: #{result[:details]}"
    end
    
    puts "\n   Production Readiness:"
    if failed == 0 && errors == 0
      if warnings == 0
        puts "   🎉 READY FOR PRODUCTION - All validations passed"
        puts "   💡 The duplicate detection system is fully functional and ready for production use."
      else
        puts "   ✅ READY FOR PRODUCTION - All critical validations passed"
        puts "   ⚠️  Some warnings exist but do not affect core functionality."
      end
    elsif failed == 0
      puts "   ⚠️  CONDITIONALLY READY - All critical validations passed"
      puts "   🚨 Some errors exist that should be investigated before production use."
    else
      puts "   ❌ NOT READY FOR PRODUCTION - Critical validations failed"
      puts "   🔧 Fix the failed validations before deploying to production."
    end
    
    # System statistics
    total_files = @db.get_first_value("SELECT COUNT(*) FROM file_records")
    duplicate_groups = HumataImport::FileRecord.find_all_duplicates(@db)
    total_duplicates = duplicate_groups.sum { |d| d[:count] - 1 }
    
    puts "\n   System Statistics:"
    puts "   📊 Total files: #{total_files}"
    puts "   🔍 Duplicate groups: #{duplicate_groups.size}"
    puts "   📋 Total duplicate files: #{total_duplicates}"
    puts "   ✨ Unique files: #{total_files - total_duplicates}"
    
    if total_duplicates > 0
      duplicate_percentage = (total_duplicates.to_f / total_files * 100).round(1)
      puts "   📈 Duplicate rate: #{duplicate_percentage}%"
    end
  end

  def column_exists?(column_name)
    @db.execute('PRAGMA table_info(file_records)').any? { |col| col[1] == column_name }
  end
end

# Main execution
if __FILE__ == $0
  db_path = ARGV[0] || './import_session.db'
  validator = ProductionValidator.new(db_path)
  validator.run
end
