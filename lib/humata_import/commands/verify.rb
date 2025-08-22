# frozen_string_literal: true

require 'optparse'
require_relative 'base'
require_relative '../clients/humata_client'
require_relative '../models/file_record'
require 'logger'

module HumataImport
  module Commands
    # Command for verifying the processing status of uploaded files.
    # Handles status polling, timeout handling, and status updates.
    # 
    # Enhanced implementation includes:
    # - Proper status mapping between Humata API read_status and internal processing_status
    # - Page count storage when processing completes successfully
    # - Enhanced metadata storage for debugging and analysis
    # - Timestamp updates for completed files
    class Verify < Base
      # Runs the verify command.
      # @param args [Array<String>] Command-line arguments
      # @param humata_client [HumataImport::Clients::HumataClient, nil] Optional Humata client for dependency injection
      # @return [void]
      def run(args, humata_client: nil)
        options = {
          poll_interval: 10,  # seconds
          timeout: 1800,      # 30 minutes
          batch_size: 10,
          verbose: @options[:verbose],  # Start with global verbose setting
          quiet: @options[:quiet]
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import verify [options]"
          opts.on('--poll-interval N', Integer, 'Seconds between status checks (default: 10)') { |v| options[:poll_interval] = v }
          opts.on('--timeout N', Integer, 'Total timeout in seconds (default: 1800)') { |v| options[:timeout] = v }
          opts.on('--batch-size N', Integer, 'Number of files to check in parallel (default: 10)') { |v| options[:batch_size] = v }
          opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { options[:quiet] = true }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)

        # Update logger level based on verbose setting
        @options[:verbose] = options[:verbose]
        @options[:quiet] = options[:quiet]
        logger.configure(@options)

        # Use injected client or create default one
        client = humata_client
        unless client
          api_key = ENV['HUMATA_API_KEY']
          unless api_key
            logger.error "HUMATA_API_KEY environment variable not set"
            exit 1
          end
          client = HumataImport::Clients::HumataClient.new(
            api_key: api_key
          )
        end

        # Get files pending verification
        pending_files = @db.execute(<<-SQL)
          SELECT * FROM file_records 
          WHERE humata_id IS NOT NULL 
          AND processing_status IN ('pending', 'processing')
        SQL

        if pending_files.empty?
          logger.info "No files pending verification."
          return
        end

        logger.info "Found #{pending_files.size} files to verify."
        start_time = Time.now
        completed = 0
        failed = 0
        iteration_count = 0
        max_iterations = 10  # Safety limit to prevent infinite loops

        # Process files until all are completed, failed, or timeout reached
        while (Time.now - start_time) < options[:timeout] && iteration_count < max_iterations
          iteration_count += 1
          logger.debug "Starting iteration #{iteration_count}"
          
          # Get current list of files that need processing
          current_pending_files = @db.execute(<<-SQL)
            SELECT * FROM file_records 
            WHERE processing_status IN ('pending', 'processing') 
            AND humata_id IS NOT NULL
            ORDER BY discovered_at ASC
          SQL
          
          logger.debug "Found #{current_pending_files.size} files to process in iteration #{iteration_count}"
          
          # If no files need processing, we're done
          if current_pending_files.empty?
            logger.info "No files pending verification, breaking loop"
            break
          end
          
          logger.info "Processing #{current_pending_files.size} files this iteration"
          
          # Track which files had status changes in this iteration
          files_with_status_changes = 0
          
          # Process each file
          current_pending_files.each do |file|
            # Convert array result to hash using column names
            columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
            file_data = columns.zip(file).to_h

            begin
              logger.debug "Checking status: #{file_data['name']} (#{file_data['humata_id']})"
              response = client.get_file_status(file_data['humata_id'])
              
              logger.debug "Raw response: #{response.inspect}"
              
              # Enhanced status processing with proper mapping and metadata storage
              process_humata_response(file_data, response)
              
              # Update counters based on new status
              new_status = map_humata_status_to_processing_status(response['read_status'])
              logger.debug "Mapped status: #{response['read_status']} -> #{new_status}"
              
              # Check if status actually changed
              if new_status != file_data['processing_status']
                files_with_status_changes += 1
                logger.debug "Status changed from '#{file_data['processing_status']}' to '#{new_status}' for #{file_data['name']}"
              else
                logger.debug "Status unchanged for #{file_data['name']}: #{new_status}"
              end
              
              case new_status
              when 'completed'
                completed += 1
                logger.debug "✓ Completed: #{file_data['name']}"
              when 'failed'
                failed += 1
                logger.error "✗ Failed: #{file_data['name']}"
              else
                # Status is still pending or processing
                logger.debug "... Processing: #{file_data['name']} (status: #{new_status})"
              end
            rescue HumataImport::HumataError => e
              logger.warn "Status check failed for #{file_data['name']}: #{e.message}"
            rescue => e
              logger.error "Unexpected error processing #{file_data['name']}: #{e.class}: #{e.message}"
              logger.error e.backtrace.join("\n")
            end
          end
          
          logger.debug "Finished processing files in iteration #{iteration_count}. Files with status changes: #{files_with_status_changes}"
          
          # If no files had status changes, we're in a loop - break
          if files_with_status_changes == 0
            logger.warn "No files had status changes in iteration #{iteration_count}, breaking loop to prevent infinite loop"
            break
          end
          
          # Get updated counts for progress reporting
          still_pending = @db.execute('SELECT COUNT(*) FROM file_records WHERE processing_status IN (?, ?)', ['pending', 'processing']).first.first
          
          logger.debug "After iteration #{iteration_count}: #{completed} completed, #{failed} failed, #{still_pending} pending"
          
          if still_pending > 0
            logger.info "\nProgress: #{completed} completed, #{failed} failed, #{still_pending} pending"
            # Don't sleep in test mode to prevent hanging
            unless ENV['TEST_ENV']
              sleep options[:poll_interval]
            end
          else
            logger.info "All files processed, breaking loop"
            break
          end
        end
        
        if iteration_count >= max_iterations
          logger.warn "Reached maximum iteration limit (#{max_iterations}), breaking loop to prevent infinite loop"
        end

        if (Time.now - start_time) >= options[:timeout]
          logger.warn "\nTimeout reached after #{options[:timeout]} seconds"
        end

        logger.info "\nFinal Summary:"
        logger.info "  Completed: #{completed} files"
        logger.info "  Failed:    #{failed} files"
        logger.info "  Pending:   #{still_pending} files"
        logger.info "  Duration:  #{(Time.now - start_time).round(1)} seconds"
      end

      private

      # Maps Humata API read_status values to internal processing_status values
      # according to Section 3.4.4 of the functional specification
      # @param read_status [String] The read_status from Humata API response
      # @return [String] The corresponding internal processing_status
      def map_humata_status_to_processing_status(read_status)
        logger.debug "Mapping status: #{read_status.inspect}"
        case read_status&.upcase
        when 'PENDING'
          'pending'
        when 'PROCESSING'
          'processing'
        when 'SUCCESS'
          'completed'
        when 'FAILED'
          'failed'
        else
          # Default to pending for unknown statuses
          logger.debug "Unknown status '#{read_status}', defaulting to 'pending'"
          'pending'
        end
      end

      # Processes the Humata API response and updates the database with enhanced information
      # @param file_data [Hash] The file record data from the database
      # @param response [Hash] The Humata API response
      def process_humata_response(file_data, response)
        logger.debug "Processing response for #{file_data['name']}: #{response.inspect}"
        
        # Map the Humata read_status to internal processing_status
        processing_status = map_humata_status_to_processing_status(response['read_status'])
        logger.debug "Mapped to processing_status: #{processing_status}"
        
        # Extract page count when processing is successful
        humata_pages = nil
        if response['read_status']&.upcase == 'SUCCESS' && response['number_of_pages']
          humata_pages = response['number_of_pages'].to_i
          logger.debug "Extracted page count: #{humata_pages}"
        end
        
        # Prepare update parameters
        update_params = [
          processing_status,                    # processing_status
          response.to_json,                    # humata_verification_response
          humata_pages,                        # humata_pages
          Time.now.iso8601,                   # last_checked_at
          file_data['gdrive_id']              # WHERE clause
        ]
        
        # Add completed_at timestamp when processing completes
        if processing_status == 'completed'
          update_params.insert(3, Time.now.iso8601)  # completed_at
          sql = <<-SQL
            UPDATE file_records 
            SET processing_status = ?,
                humata_verification_response = ?,
                humata_pages = ?,
                completed_at = ?,
                last_checked_at = ?
            WHERE gdrive_id = ?
          SQL
          logger.debug "Using SQL with completed_at: #{sql.strip}"
        else
          # For non-completed statuses, use the simpler SQL without completed_at
          sql = <<-SQL
            UPDATE file_records 
            SET processing_status = ?,
                humata_verification_response = ?,
                humata_pages = ?,
                last_checked_at = ?
            WHERE gdrive_id = ?
          SQL
          logger.debug "Using SQL without completed_at: #{sql.strip}"
        end
        
        logger.debug "Update params: #{update_params.inspect}"
        
        # Execute the update
        @db.execute(sql, update_params)
        
        # Log enhanced information
        if humata_pages
          logger.debug "  → Pages: #{humata_pages}"
        end
        logger.debug "  → Status: #{response['read_status']} → #{processing_status}"
      end
    end
  end
end