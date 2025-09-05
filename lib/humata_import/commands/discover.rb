# frozen_string_literal: true

# Command for discovering files in a Google Drive folder.
#
# This file provides the Discover command, which crawls a Google Drive folder
# (optionally recursively), extracts file metadata, and stores discovered files
# in the database. Handles duplicate detection, file type filtering, and limits.
#
# Dependencies:
#   - HumataImport::Clients::GdriveClient
#   - HumataImport::FileRecord
#   - OptionParser (for option parsing)
#
# Configuration:
#   - Accepts options for recursion, max files, timeout, verbosity
#
# Side Effects:
#   - Modifies the file_records table in the database
#   - Prints to stdout
#
# @author Humata Import Team
# @since 0.1.0
require_relative 'base'
require_relative '../clients/gdrive_client'
require_relative '../models/file_record'
require 'optparse'

module HumataImport
  module Commands
    # Command for discovering files in a Google Drive folder.
    class Discover < Base
      DEFAULT_TIMEOUT = 300

      # Runs the discover command, parsing options and crawling the folder.
      #
      # @param args [Array<String>] Command-line arguments
      # @param gdrive_client [HumataImport::Clients::GdriveClient, nil] Optional injected client
      # @return [void]
      def run(args, gdrive_client: nil)
        options = {
          recursive: true,
          max_files: nil,
          timeout: DEFAULT_TIMEOUT,
          duplicate_strategy: 'skip',
          show_duplicates: false,
          max_retries: 3,
          retry_delay: 5
        }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import discover <gdrive-url> [options]"
          opts.on('--recursive', 'Crawl subfolders (default: true)') { options[:recursive] = true }
          opts.on('--no-recursive', 'Do not crawl subfolders') { options[:recursive] = false }
          opts.on('--max-files N', Integer, 'Limit number of files to discover') { |v| options[:max_files] = v }
          opts.on('--timeout SECONDS', Integer, 'Discovery timeout (default: 300s)') { |v| options[:timeout] = v }
          opts.on('--duplicate-strategy STRATEGY', %w[skip upload replace track-duplicates], 'How to handle duplicates: skip, upload, replace, or track-duplicates (default: skip)') { |v| options[:duplicate_strategy] = v }
          opts.on('--show-duplicates', 'Show detailed duplicate information') { options[:show_duplicates] = true }
          opts.on('--max-retries N', Integer, 'Maximum retry attempts for API calls (default: 3)') { |v| options[:max_retries] = v }
          opts.on('--retry-delay N', Integer, 'Base delay in seconds between retries (default: 5)') { |v| options[:retry_delay] = v }
          opts.on('-v', '--verbose', 'Enable verbose output') { @options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { @options[:quiet] = true }
        end
        parser.order!(args)
        gdrive_url = args.shift
        raise ArgumentError, 'Missing Google Drive folder URL' unless gdrive_url
        
        # Provide timeout and retry guidance
        unless @options[:quiet]
          if options[:timeout] < 60
            puts "⚠️  Short timeout (#{options[:timeout]}s) - may not complete for large folders"
          elsif options[:timeout] > 1800
            puts "ℹ️  Extended timeout (#{options[:timeout]}s) - suitable for very large folders"
          end
          
          if options[:max_retries] > 5
            puts "ℹ️  High retry count (#{options[:max_retries]}) - suitable for unstable networks"
          elsif options[:max_retries] < 2
            puts "⚠️  Low retry count (#{options[:max_retries]}) - may fail on transient errors"
          end
        end
        
        client = gdrive_client || HumataImport::Clients::GdriveClient.new(timeout: options[:timeout])
        files = client.list_files(gdrive_url, options[:recursive], options[:max_files], options[:max_retries], options[:retry_delay])
        
        # Initialize counters for progress reporting
        total_files = files.size
        skipped_files = 0
        added_files = 0
        duplicate_files = 0
        new_duplicate_files = 0  # Duplicates among newly added files
        
        puts "🔍 Discovering files in Google Drive folder..." unless @options[:quiet]
        puts "📁 Found #{total_files} files to process" if @options[:verbose] && !@options[:quiet]
        
        # Provide guidance for large folders
        if total_files > 1000 && !@options[:quiet]
          puts "⚠️  Large folder detected (#{total_files} files)"
          puts "   Consider using --max-files to limit discovery if needed"
          puts "   Current timeout: #{options[:timeout]} seconds"
        end
        
        files.each_with_index do |file, index|
          # Check for existing file by gdrive_id first
          if HumataImport::FileRecord.exists?(db, file[:id])
            skipped_files += 1
            puts "⏭️  Skipping existing file: #{file[:name]}" if @options[:verbose] && !@options[:quiet]
            next
          end
          
          # Check if this is a duplicate of an existing file BEFORE creating the record
          file_hash = HumataImport::FileRecord.generate_file_hash(file[:size], file[:name], file[:mimeType])
          duplicate_info = HumataImport::FileRecord.find_duplicate(db, file_hash, file[:id])
          
          # Ensure timestamps are properly formatted strings
          created_time = file[:createdTime]&.to_s
          modified_time = file[:modifiedTime]&.to_s
          
          if duplicate_info[:duplicate_found]
            duplicate_files += 1
            puts "🔄 Duplicate detected: #{file[:name]} (same as: #{duplicate_info[:duplicate_name]})" if @options[:verbose] && !@options[:quiet]
            
            # Handle duplicate based on strategy
            case options[:duplicate_strategy]
            when 'skip'
              puts "⏭️  Skipping duplicate file: #{file[:name]}" if @options[:verbose] && !@options[:quiet]
              next
            when 'track-duplicates'
              # For track-duplicates strategy, create the file but mark it as duplicate
              HumataImport::FileRecord.create(
                db,
                gdrive_id: file[:id],
                name: file[:name],
                url: file[:webContentLink],
                size: file[:size],
                mime_type: file[:mimeType],
                created_time: created_time,
                modified_time: modified_time
              )
              
              # Update the duplicate_of_gdrive_id for the new file
              db.execute("UPDATE file_records SET duplicate_of_gdrive_id = ? WHERE gdrive_id = ?", [duplicate_info[:duplicate_of_gdrive_id], file[:id]])
              
              added_files += 1
              new_duplicate_files += 1
            when 'replace'
              # For replace strategy, create the file but mark it as duplicate
              puts "🔄 Replacing existing file: #{duplicate_info[:duplicate_name]}" if @options[:verbose] && !@options[:quiet]
              
              # Create the new file record
              HumataImport::FileRecord.create(
                db,
                gdrive_id: file[:id],
                name: file[:name],
                url: file[:webContentLink],
                size: file[:size],
                mime_type: file[:mimeType],
                created_time: created_time,
                modified_time: modified_time
              )
              
              # Update the duplicate_of_gdrive_id for the new file
              db.execute("UPDATE file_records SET duplicate_of_gdrive_id = ? WHERE gdrive_id = ?", [duplicate_info[:duplicate_of_gdrive_id], file[:id]])
              
              added_files += 1
              new_duplicate_files += 1
            when 'upload'
              # For upload strategy, create the file but mark it as duplicate
              HumataImport::FileRecord.create(
                db,
                gdrive_id: file[:id],
                name: file[:name],
                url: file[:webContentLink],
                size: file[:size],
                mime_type: file[:mimeType],
                created_time: created_time,
                modified_time: modified_time
              )
              
              # Update the duplicate_of_gdrive_id for the new file
              db.execute("UPDATE file_records SET duplicate_of_gdrive_id = ? WHERE gdrive_id = ?", [duplicate_info[:duplicate_of_gdrive_id], file[:id]])
              
              added_files += 1
              new_duplicate_files += 1
            end
          else
            # No duplicate found, create the file record normally
            HumataImport::FileRecord.create(
              db,
              gdrive_id: file[:id],
              name: file[:name],
              url: file[:webContentLink],
              size: file[:size],
              mime_type: file[:mimeType],
              created_time: created_time,
              modified_time: modified_time
            )
            
            added_files += 1
          end
          
          # Progress reporting
          if @options[:verbose] && !@options[:quiet]
            puts "✅ Added file #{index + 1}/#{total_files}: #{file[:name]}"
          elsif !@options[:quiet] && (index + 1) % 10 == 0
            puts "📊 Processed #{index + 1}/#{total_files} files..."
          end
        end
        
        # Final summary
        unless @options[:quiet]
          puts "\n🎯 Discovery Summary:"
          puts "   Total files found: #{total_files}"
          puts "   New files added: #{added_files}"
          puts "   Existing files skipped: #{skipped_files}"
          puts "   Duplicate files detected: #{duplicate_files}"
          puts "   New files that were duplicates: #{new_duplicate_files}"
          puts "   Database now contains: #{HumataImport::FileRecord.all(db).size} total files"
          
          # Show duplicate details if requested
          if options[:show_duplicates] && duplicate_files > 0
            puts "\n🔄 Duplicate Files Details:"
            duplicates = HumataImport::FileRecord.find_all_duplicates(db)
            duplicates.each do |duplicate_group|
              puts "   📁 Group (#{duplicate_group[:count]} files):"
              duplicate_group[:gdrive_ids].each_with_index do |gdrive_id, index|
                puts "      - #{duplicate_group[:names][index]} (#{duplicate_group[:sizes][index]} bytes, #{duplicate_group[:mime_types][index]})"
              end
              puts "      Hash: #{duplicate_group[:file_hash]}"
            end
          end
        end
      end
    end
  end
end