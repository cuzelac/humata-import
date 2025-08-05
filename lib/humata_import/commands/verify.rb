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
    class Verify < Base
      def logger
        @logger ||= Logger.new($stdout).tap do |log|
          if @options[:quiet]
            log.level = Logger::ERROR
          elsif @options[:verbose]
            log.level = Logger::DEBUG
          else
            log.level = Logger::INFO
          end
        end
      end

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

        # Use injected client or create default one
        client = humata_client
        unless client
          api_key = ENV['HUMATA_API_KEY']
          unless api_key
            logger.error "HUMATA_API_KEY environment variable not set"
            exit 1
          end
          client = HumataImport::Clients::HumataClient.new(
            api_key: api_key,
            logger: logger
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
        still_pending = pending_files.size

        while still_pending > 0 && (Time.now - start_time) < options[:timeout]
          pending_files.each_slice(options[:batch_size]) do |batch|
            batch.each do |file|
              # Convert array result to hash using column names
              if file.is_a?(Hash)
                file_data = file
              else
                columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
                file_data = columns.zip(file).to_h
              end
              
              next unless ['pending', 'processing'].include?(file_data['processing_status'])

              begin
                logger.debug "Checking status: #{file_data['name']} (#{file_data['humata_id']})"
                response = client.get_file_status(file_data['humata_id'])
                
                # Update status in database
                status = response['status']
                @db.execute(<<-SQL, [status, response.to_json, file_data['gdrive_id']])
                  UPDATE file_records 
                  SET processing_status = ?,
                      humata_verification_response = ?
                  WHERE gdrive_id = ?
                SQL

                case status
                when 'completed'
                  completed += 1
                  still_pending -= 1
                  logger.debug "✓ Completed: #{file_data['name']}"
                when 'failed'
                  failed += 1
                  still_pending -= 1
                  logger.error "✗ Failed: #{file_data['name']}"
                else
                  logger.debug "... Processing: #{file_data['name']} (status: #{status})"
                end
              rescue HumataImport::Clients::HumataError => e
                logger.warn "Status check failed for #{file_data['name']}: #{e.message}"
              end
            end
          end

          if still_pending > 0
            logger.info "\nProgress: #{completed} completed, #{failed} failed, #{still_pending} pending"
            sleep options[:poll_interval]
          end
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
    end
  end
end