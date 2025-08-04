# frozen_string_literal: true

require 'optparse'
require_relative 'base'
require_relative '../clients/humata_client'
require_relative '../models/file_record'
require 'logger'

module HumataImport
  module Commands
    # Command for uploading discovered files to Humata.ai.
    # Handles batch processing, rate limiting, and response storage.
    class Upload < Base
      def logger
        @logger ||= Logger.new($stdout).tap do |log|
          log.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO
        end
      end

      # Runs the upload command.
      # @param args [Array<String>] Command-line arguments
      # @return [void]
      # @raise [ArgumentError] If required options are missing
      def run(args)
        options = {
          batch_size: 10,
          max_retries: 3,
          retry_delay: 5
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import upload --folder-id FOLDER_ID [options]"
          opts.on('--folder-id ID', String, 'Humata folder ID (required)') { |v| options[:folder_id] = v }
          opts.on('--batch-size N', Integer, 'Number of files to process in parallel (default: 10)') { |v| options[:batch_size] = v }
          opts.on('--max-retries N', Integer, 'Maximum retry attempts per file (default: 3)') { |v| options[:max_retries] = v }
          opts.on('--retry-delay N', Integer, 'Seconds to wait between retries (default: 5)') { |v| options[:retry_delay] = v }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)

        unless options[:folder_id]
          puts parser
          exit 1
        end

        api_key = ENV['HUMATA_API_KEY']
        unless api_key
          logger.error "HUMATA_API_KEY environment variable not set"
          exit 1
        end

        client = HumataImport::Clients::HumataClient.new(
          api_key: api_key,
          logger: logger
        )

        # Get pending files from database
        pending_files = @db.execute(<<-SQL)
          SELECT * FROM file_records 
          WHERE humata_id IS NULL 
          AND processing_status IS NULL
        SQL

        if pending_files.empty?
          logger.info "No pending files found for upload."
          return
        end

        logger.info "Found #{pending_files.size} files pending upload."
        uploaded = 0
        failed = 0

        # Process files in batches
        pending_files.each_slice(options[:batch_size]) do |batch|
          batch.each do |file|
            begin
              retries = 0
              begin
                # Convert array result to hash using column names
                if file.is_a?(Hash)
                  file_data = file
                else
                  columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
                  file_data = columns.zip(file).to_h
                end
                logger.debug "Uploading: #{file_data['name']} (#{file_data['gdrive_id']})"
                response = client.upload_file(file_data['url'], options[:folder_id])
                
                # Store response and update status
                @db.execute(<<-SQL, [response['id'], 'pending', response.to_json, file_data['gdrive_id']])
                  UPDATE file_records 
                  SET humata_id = ?,
                      processing_status = ?,
                      humata_import_response = ?
                  WHERE gdrive_id = ?
                SQL

                uploaded += 1
                logger.debug "Success: #{file_data['name']} (Humata ID: #{response['id']})"
              rescue HumataImport::Clients::HumataError => e
                retries += 1
                if retries <= options[:max_retries]
                  logger.warn "Upload failed for #{file_data['name']}, attempt #{retries}/#{options[:max_retries]}: #{e.message}"
                  sleep options[:retry_delay]
                  retry
                else
                  failed += 1
                  logger.error "Upload failed for #{file_data['name']} after #{options[:max_retries]} attempts: #{e.message}"
                  
                  # Record the failure
                  @db.execute(<<-SQL, ['failed', { error: e.message, attempts: retries }.to_json, file_data['gdrive_id']])
                    UPDATE file_records 
                    SET processing_status = ?,
                        humata_import_response = ?
                    WHERE gdrive_id = ?
                  SQL
                end
              end
            rescue StandardError => e
              failed += 1
              file_name = file.is_a?(Hash) ? file['name'] : file.to_s
              logger.error "Unexpected error processing #{file_name}: #{e.message}"
            end
          end
        end

        logger.info "\nSummary:"
        logger.info "  Uploaded: #{uploaded} files"
        logger.info "  Failed:   #{failed} files"
        logger.info "  Total:    #{uploaded + failed} files processed"
      end
    end
  end
end