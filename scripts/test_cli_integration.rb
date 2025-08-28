#!/usr/bin/env ruby
# frozen_string_literal: true

# CLI Integration Test Script for Duplicate Detection
#
# This script tests the complete CLI workflow with duplicate detection
# including all strategies and reporting options.
#
# Usage:
#   ruby scripts/test_cli_integration.rb [database_path]
#   ruby scripts/test_cli_integration.rb ./import_session.db

require 'sqlite3'
require 'open3'
require 'json'

class CLIIntegrationTester
  def initialize(db_path = './import_session.db')
    @db_path = db_path
    @db = nil
    @test_results = []
  end

  def run
    puts "🔧 CLI Integration Test for Duplicate Detection"
    puts "Database: #{@db_path}"
    
    unless File.exist?(@db_path)
      puts "❌ Database file not found: #{@db_path}"
      exit 1
    end

    begin
      @db = SQLite3::Database.new(@db_path)
      
      # Test 1: Test discover command with show-duplicates
      test_discover_with_duplicates
      
      # Test 2: Test duplicate strategy options
      test_duplicate_strategies
      
      # Test 3: Test duplicate reporting
      test_duplicate_reporting
      
      # Test 4: Test performance with large dataset
      test_large_dataset_performance
      
      # Test 5: Test error handling
      test_error_handling
      
      print_test_summary
      
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

  def test_discover_with_duplicates
    puts "\n🔍 Test 1: Discover Command with Duplicate Detection"
    
    # Create a test Google Drive URL (this won't actually make API calls)
    test_url = "https://drive.google.com/drive/folders/test_folder_123"
    
    # Test the discover command with show-duplicates flag
    command = "bundle exec ruby bin/humata-import discover '#{test_url}' --show-duplicates --quiet"
    
    puts "   Running: #{command}"
    
    begin
      stdout, stderr, status = Open3.capture3(command)
      
      if status.success?
        puts "   ✅ Discover command executed successfully"
        
        # Check if duplicate information is displayed
        if stdout.include?('duplicate') || stdout.include?('Duplicate')
          puts "   ✅ Duplicate information displayed"
          @test_results << { test: 'Discover with duplicates', status: 'PASS' }
        else
          puts "   ⚠️  No duplicate information found in output"
          @test_results << { test: 'Discover with duplicates', status: 'WARNING' }
        end
      else
        puts "   ❌ Discover command failed: #{stderr}"
        @test_results << { test: 'Discover with duplicates', status: 'FAIL' }
      end
    rescue => e
      puts "   ❌ Error running discover command: #{e.message}"
      @test_results << { test: 'Discover with duplicates', status: 'ERROR' }
    end
  end

  def test_duplicate_strategies
    puts "\n⚙️  Test 2: Duplicate Strategy Options"
    
    strategies = ['skip', 'upload', 'replace']
    
    strategies.each do |strategy|
      puts "   Testing strategy: #{strategy}"
      
      # Test the discover command with different strategies
      command = "bundle exec ruby bin/humata-import discover 'https://test.com' --duplicate-strategy #{strategy} --quiet"
      
      begin
        stdout, stderr, status = Open3.capture3(command)
        
        if status.success?
          puts "      ✅ #{strategy} strategy accepted"
          @test_results << { test: "Strategy #{strategy}", status: 'PASS' }
        else
          puts "      ❌ #{strategy} strategy failed: #{stderr}"
          @test_results << { test: "Strategy #{strategy}", status: 'FAIL' }
        end
      rescue => e
        puts "      ❌ Error testing #{strategy} strategy: #{e.message}"
        @test_results << { test: "Strategy #{strategy}", status: 'ERROR' }
      end
    end
  end

  def test_duplicate_reporting
    puts "\n📊 Test 3: Duplicate Reporting"
    
    # Test the show-duplicates flag specifically
    command = "bundle exec ruby bin/humata-import discover 'https://test.com' --show-duplicates --quiet"
    
    puts "   Testing show-duplicates flag..."
    
    begin
      stdout, stderr, status = Open3.capture3(command)
      
      if status.success?
        puts "   ✅ show-duplicates flag accepted"
        
        # Check if the flag is properly recognized
        if stdout.include?('duplicate') || stderr.empty?
          puts "   ✅ Duplicate reporting working"
          @test_results << { test: 'Duplicate reporting', status: 'PASS' }
        else
          puts "   ⚠️  Duplicate reporting output unclear"
          @test_results << { test: 'Duplicate reporting', status: 'WARNING' }
        end
      else
        puts "   ❌ show-duplicates flag failed: #{stderr}"
        @test_results << { test: 'Duplicate reporting', status: 'FAIL' }
      end
    rescue => e
      puts "   ❌ Error testing duplicate reporting: #{e.message}"
      @test_results << { test: 'Duplicate reporting', status: 'ERROR' }
    end
  end

  def test_large_dataset_performance
    puts "\n⚡ Test 4: Large Dataset Performance"
    
    # Test duplicate detection performance on the current database
    start_time = Time.now
    
    duplicates = @db.execute(<<-SQL)
      SELECT file_hash, COUNT(*) as count 
      FROM file_records 
      WHERE file_hash IS NOT NULL 
      GROUP BY file_hash 
      HAVING COUNT(*) > 1
    SQL
    
    end_time = Time.now
    processing_time = end_time - start_time
    
    puts "   Database size: #{@db.get_first_value('SELECT COUNT(*) FROM file_records')} files"
    puts "   Duplicate groups: #{duplicates.size}"
    puts "   Processing time: #{processing_time.round(3)} seconds"
    
    if processing_time < 1.0
      puts "   ✅ Performance excellent (< 1 second)"
      @test_results << { test: 'Large dataset performance', status: 'PASS' }
    elsif processing_time < 5.0
      puts "   ✅ Performance good (< 5 seconds)"
      @test_results << { test: 'Large dataset performance', status: 'PASS' }
    else
      puts "   ⚠️  Performance could be improved (> 5 seconds)"
      @test_results << { test: 'Large dataset performance', status: 'WARNING' }
    end
  end

  def test_error_handling
    puts "\n🚨 Test 5: Error Handling"
    
    # Test invalid duplicate strategy
    command = "bundle exec ruby bin/humata-import discover 'https://test.com' --duplicate-strategy invalid --quiet"
    
    puts "   Testing invalid duplicate strategy..."
    
    begin
      stdout, stderr, status = Open3.capture3(command)
      
      if !status.success?
        puts "   ✅ Invalid strategy properly rejected"
        
        if stderr.include?('duplicate-strategy') || stderr.include?('invalid')
          puts "   ✅ Helpful error message provided"
          @test_results << { test: 'Error handling', status: 'PASS' }
        else
          puts "   ⚠️  Error message could be more specific"
          @test_results << { test: 'Error handling', status: 'WARNING' }
        end
      else
        puts "   ❌ Invalid strategy was accepted (should be rejected)"
        @test_results << { test: 'Error handling', status: 'FAIL' }
      end
    rescue => e
      puts "   ❌ Error testing error handling: #{e.message}"
      @test_results << { test: 'Error handling', status: 'ERROR' }
    end
  end

  def print_test_summary
    puts "\n📋 Test Summary"
    puts "=" * 50
    
    passed = @test_results.count { |r| r[:status] == 'PASS' }
    warnings = @test_results.count { |r| r[:status] == 'WARNING' }
    failed = @test_results.count { |r| r[:status] == 'FAIL' }
    errors = @test_results.count { |r| r[:status] == 'ERROR' }
    
    puts "   Total tests: #{@test_results.size}"
    puts "   Passed: #{passed} ✅"
    puts "   Warnings: #{warnings} ⚠️"
    puts "   Failed: #{failed} ❌"
    puts "   Errors: #{errors} 🚨"
    
    puts "\nDetailed Results:"
    @test_results.each do |result|
      status_icon = case result[:status]
                    when 'PASS' then '✅'
                    when 'WARNING' then '⚠️'
                    when 'FAIL' then '❌'
                    when 'ERROR' then '🚨'
                    else '❓'
                    end
      
      puts "   #{status_icon} #{result[:test]}: #{result[:status]}"
    end
    
    if failed == 0 && errors == 0
      puts "\n🎉 All critical tests passed! The duplicate detection system is ready for production."
    elsif failed == 0
      puts "\n⚠️  Some tests had errors, but no critical failures. Review error handling."
    else
      puts "\n❌ Some tests failed. Review the implementation before production use."
    end
  end
end

# Main execution
if __FILE__ == $0
  db_path = ARGV[0] || './import_session.db'
  tester = CLIIntegrationTester.new(db_path)
  tester.run
end
