# frozen_string_literal: true

require 'optparse'
require_relative 'base'
require_relative '../clients/humata_client'
require_relative '../models/file_record'
require_relative '../utils/url_converter'
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
      # @param humata_client [HumataImport::Clients::HumataClient, nil] Optional Humata client for dependency injection
      # @return [void]
      # @raise [ArgumentError] If required options are missing
      def run(args, humata_client: nil)
        options = {
          batch_size: 10,
          max_retries: 3,
          retry_delay: 5,
          skip_retries: false,
          verbose: @options[:verbose]  # Start with global verbose setting
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import upload --folder-id FOLDER_ID [options]"
          opts.on('--folder-id ID', String, 'Humata folder ID (required)') { |v| options[:folder_id] = v }
          opts.on('--batch-size N', Integer, 'Number of files to process in parallel (default: 10)') { |v| options[:batch_size] = v }
          opts.on('--max-retries N', Integer, 'Maximum retry attempts per file (default: 3)') { |v| options[:max_retries] = v }
          opts.on('--retry-delay N', Integer, 'Seconds to wait between retries (default: 5)') { |v| options[:retry_delay] = v }
          opts.on('--skip-retries', 'Skip retrying failed uploads') { options[:skip_retries] = true }
          opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)

        # Update logger level based on verbose setting
        @options[:verbose] = options[:verbose]

        unless options[:folder_id]
          puts parser
          exit 1
        end

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

        # Get pending files from database (including failed uploads to retry)
        sql = if options[:skip_retries]
          "SELECT * FROM file_records WHERE humata_id IS NULL AND upload_status = 'pending' AND processing_status IS NULL"
        else
          "SELECT * FROM file_records WHERE humata_id IS NULL AND (upload_status = 'pending' OR processing_status = 'failed')"
        end
        pending_files = @db.execute(sql)

        if pending_files.empty?
          logger.info "No pending files found for upload."
          return
        end

        # Count retries vs new uploads
        if options[:skip_retries]
          logger.info "Found #{pending_files.size} new files pending upload (retries skipped)."
        else
          retry_count = pending_files.count { |file| file.is_a?(Hash) ? file['processing_status'] == 'failed' : file[8] == 'failed' }
          new_count = pending_files.size - retry_count
          
          logger.info "Found #{pending_files.size} files pending upload."
          logger.info "  New uploads: #{new_count}"
          logger.info "  Retries: #{retry_count}"
        end
        
        uploaded = 0
        failed = 0

        # Process files in batches
        pending_files.each_slice(options[:batch_size]) do |batch|
          batch.each do |file|
            begin
              # Convert array result to hash using column names
              if file.is_a?(Hash)
                file_data = file
              else
                columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
                file_data = columns.zip(file).to_h
              end
              
              # Check if this is a retry of a failed upload
              is_retry = file_data['processing_status'] == 'failed'
              if is_retry
                logger.info "Retrying failed upload: #{file_data['name']} (#{file_data['gdrive_id']})"
                # Reset status to indicate we're retrying
                @db.execute(<<-SQL, ['retrying', 'pending', file_data['gdrive_id']])
                  UPDATE file_records 
                  SET processing_status = ?,
                      upload_status = ?
                  WHERE gdrive_id = ?
                SQL
              else
                logger.debug "Uploading: #{file_data['name']} (#{file_data['gdrive_id']})"
              end
              
              retries = 0
              begin
                # Optimize URL to reduce 500 errors
                optimized_url = HumataImport::Utils::UrlConverter.optimize_for_humata(file_data['url'])
                logger.debug "Original URL: #{file_data['url']}"
                logger.debug "Optimized URL: #{optimized_url}" if optimized_url != file_data['url']
                
                response = client.upload_file(optimized_url, options[:folder_id])
                
                # Store response and update status
                @db.execute(<<-SQL, [response['id'], 'pending', 'completed', response.to_json, file_data['gdrive_id']])
                  UPDATE file_records 
                  SET humata_id = ?,
                      processing_status = ?,
                      upload_status = ?,
                      humata_import_response = ?
                  WHERE gdrive_id = ?
                SQL

                uploaded += 1
                if is_retry
                  logger.info "Retry successful: #{file_data['name']} (Humata ID: #{response['id']})"
                else
                  logger.debug "Success: #{file_data['name']} (Humata ID: #{response['id']})"
                end
              rescue HumataImport::Clients::HumataError => e
                retries += 1
                if retries <= options[:max_retries]
                  logger.warn "Upload failed for #{file_data['name']}, attempt #{retries}/#{options[:max_retries]}: #{e.message}"
                  sleep options[:retry_delay]
                  retry
                else
                  failed += 1
                  logger.error "Upload failed for #{file_data['name']} after #{options[:max_retries]} attempts: #{e.message}"
                  
                  # Record the failure with retry count
                  @db.execute(<<-SQL, ['failed', 'failed', { error: e.message, attempts: retries, last_attempt: Time.now.iso8601 }.to_json, file_data['gdrive_id']])
                    UPDATE file_records 
                    SET processing_status = ?,
                        upload_status = ?,
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