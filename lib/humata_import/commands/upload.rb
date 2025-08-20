# frozen_string_literal: true

# Command for uploading discovered files to Humata.ai.
#
# This file provides the Upload command for uploading files from the database
# to Humata.ai. Handles batch processing, retry logic, rate limiting, and
# response storage.
#
# Dependencies:
#   - optparse (stdlib)
#   - HumataImport::Clients::HumataClient
#   - HumataImport::FileRecord
#   - HumataImport::Utils::UrlBuilder
#
# Configuration:
#   - Requires HUMATA_API_KEY environment variable
#
# Side Effects:
#   - Updates file_records table in database
#   - Makes HTTP requests to Humata API
#   - Prints to stdout
#
# @author Humata Import Team
# @since 0.1.0
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
      # Runs the upload command.
      #
      # @param args [Array<String>] Command-line arguments
      # @param humata_client [HumataImport::Clients::HumataClient, nil] Optional Humata client for dependency injection
      # @return [void]
      # @raise [ArgumentError] If required options are missing
      def run(args, humata_client: nil)
        options = parse_options(args)
        configure_logger(options)
        validate_required_options(options)
        
        client = setup_client(humata_client)
        pending_files = get_pending_files(options)
        
        return if pending_files.empty?
        
        process_uploads(client, pending_files, options)
      end

      private

      # Parses command-line options.
      #
      # @param args [Array<String>] Command-line arguments
      # @return [Hash] Parsed options
      def parse_options(args)
        options = {
          batch_size: 10,
          max_retries: 3,
          retry_delay: 5,
          skip_retries: false,
          verbose: @options[:verbose],
          quiet: @options[:quiet]
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import upload --folder-id FOLDER_ID [options]"
          opts.on('--folder-id ID', String, 'Humata folder ID (required)') { |v| options[:folder_id] = v }
          opts.on('--id ID', String, 'Upload only the file with this specific gdrive_id') { |v| options[:file_id] = v }
          opts.on('--batch-size N', Integer, 'Number of files to process in parallel (default: 10)') { |v| options[:batch_size] = v }
          opts.on('--max-retries N', Integer, 'Maximum retry attempts per file (default: 3)') { |v| options[:max_retries] = v }
          opts.on('--retry-delay N', Integer, 'Seconds to wait between retries (default: 5)') { |v| options[:retry_delay] = v }
          opts.on('--skip-retries', 'Skip retrying failed uploads') { options[:skip_retries] = true }
          opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { options[:quiet] = true }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)
        options
      end

      # Configures the logger based on options.
      #
      # @param options [Hash] Parsed options
      # @return [void]
      def configure_logger(options)
        @options[:verbose] = options[:verbose]
        @options[:quiet] = options[:quiet]
        logger.configure(@options)
      end

      # Validates that required options are present.
      #
      # @param options [Hash] Parsed options
      # @return [void]
      # @raise [ArgumentError] If required options are missing
      def validate_required_options(options)
        unless options[:folder_id]
          puts "Error: --folder-id is required"
          exit 1
        end
      end

      # Sets up the Humata client.
      #
      # @param humata_client [HumataImport::Clients::HumataClient, nil] Optional injected client
      # @return [HumataImport::Clients::HumataClient] Configured client
      def setup_client(humata_client)
        return humata_client if humata_client
        
        api_key = ENV['HUMATA_API_KEY']
        unless api_key
          logger.error "HUMATA_API_KEY environment variable not set"
          exit 1
        end
        
        HumataImport::Clients::HumataClient.new(api_key: api_key)
      end

      # Gets pending files from the database.
      #
      # @param options [Hash] Parsed options
      # @return [Array<Array>] Array of pending file records
      def get_pending_files(options)
        if options[:file_id]
          get_specific_file(options[:file_id])
        else
          get_all_pending_files(options[:skip_retries])
        end
      end

      # Gets a specific file by gdrive_id.
      #
      # @param file_id [String] The gdrive_id to find
      # @return [Array<Array>] Array containing the file record
      def get_specific_file(file_id)
        sql = "SELECT * FROM file_records WHERE gdrive_id = ?"
        pending_files = @db.execute(sql, [file_id])
        
        if pending_files.empty?
          logger.error "No file found with gdrive_id: #{file_id}"
          exit 1
        end
        
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        first_file = columns.zip(pending_files.first).to_h
        logger.info "Found file to upload: #{first_file['name']} (#{file_id})"
        
        pending_files
      end

      # Gets all pending files from the database.
      #
      # @param skip_retries [Boolean] Whether to skip retrying failed uploads
      # @return [Array<Array>] Array of pending file records
      def get_all_pending_files(skip_retries)
        sql = if skip_retries
          "SELECT * FROM file_records WHERE humata_id IS NULL AND upload_status = 'pending' AND processing_status IS NULL"
        else
          "SELECT * FROM file_records WHERE humata_id IS NULL AND (upload_status = 'pending' OR processing_status = 'failed')"
        end
        pending_files = @db.execute(sql)

        if pending_files.empty?
          logger.info "No pending files found for upload."
          return []
        end

        pending_files
      end

      # Processes the uploads in batches.
      #
      # @param client [HumataImport::Clients::HumataClient] The Humata client
      # @param pending_files [Array<Array>] Array of pending file records
      # @param options [Hash] Parsed options
      # @return [void]
      def process_uploads(client, pending_files, options)
        if options[:file_id]
          logger.info "Uploading single file by ID."
        else
          count_retries_vs_new_uploads(pending_files)
        end

        # Process files in batches
        pending_files.each_slice(options[:batch_size]) do |batch|
          process_batch(client, batch, options)
        end

        logger.info "Upload processing completed."
      end

      # Counts retries vs new uploads for logging.
      #
      # @param pending_files [Array<Array>] Array of pending file records
      # @return [void]
      def count_retries_vs_new_uploads(pending_files)
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        retry_count = 0
        new_count = 0

        pending_files.each do |file_data|
          file_hash = columns.zip(file_data).to_h
          if file_hash['processing_status'] == 'failed'
            retry_count += 1
          else
            new_count += 1
          end
        end

        logger.info "Found #{pending_files.size} files to process: #{new_count} new, #{retry_count} retries"
      end

      # Processes a batch of files.
      #
      # @param client [HumataImport::Clients::HumataClient] The Humata client
      # @param batch [Array<Array>] Batch of file records
      # @param options [Hash] Parsed options
      # @return [void]
      def process_batch(client, batch, options)
        batch.each do |file_data|
          process_single_file(client, file_data, options)
        end
      end

      # Processes a single file upload.
      #
      # @param client [HumataImport::Clients::HumataClient] The Humata client
      # @param file_data [Array] File record data
      # @param options [Hash] Parsed options
      # @return [void]
      def process_single_file(client, file_data, options)
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        file_hash = columns.zip(file_data).to_h
        
        gdrive_id = file_hash['gdrive_id']
        name = file_hash['name']
        url = file_hash['url']
        
        logger.info "Uploading: #{name} (#{gdrive_id})"
        
        begin
          # Optimize URL for Humata
          optimized_url = HumataImport::Utils::UrlBuilder.optimize_for_humata(url)
          
          # Upload to Humata
          response = client.upload_file(optimized_url, options[:folder_id])
          
          # Store response and update status
          humata_id = response.dig('data', 'pdf', 'id')
          if humata_id
            update_file_success(gdrive_id, humata_id, response)
            logger.info "✓ Successfully uploaded: #{name} (Humata ID: #{humata_id})"
          else
            update_file_failure(gdrive_id, "No Humata ID in response", response)
            logger.error "✗ Failed to upload: #{name} - No Humata ID in response"
          end
        rescue HumataImport::TransientError => e
          handle_transient_error(gdrive_id, name, e, options)
        rescue HumataImport::PermanentError => e
          handle_permanent_error(gdrive_id, name, e)
        rescue StandardError => e
          handle_unexpected_error(gdrive_id, name, e)
        end
      end

      # Updates file record on successful upload.
      #
      # @param gdrive_id [String] Google Drive file ID
      # @param humata_id [String] Humata file ID
      # @param response [Hash] API response
      # @return [void]
      def update_file_success(gdrive_id, humata_id, response)
        @db.execute(
          "UPDATE file_records SET humata_id = ?, upload_status = 'completed', processing_status = 'pending', humata_import_response = ?, uploaded_at = datetime('now') WHERE gdrive_id = ?",
          [humata_id, response.to_json, gdrive_id]
        )
      end

      # Updates file record on upload failure.
      #
      # @param gdrive_id [String] Google Drive file ID
      # @param error_message [String] Error message
      # @param response [Hash] API response
      # @return [void]
      def update_file_failure(gdrive_id, error_message, response)
        @db.execute(
          "UPDATE file_records SET upload_status = 'failed', processing_status = 'failed', last_error = ?, humata_import_response = ? WHERE gdrive_id = ?",
          [error_message, response.to_json, gdrive_id]
        )
      end

      # Handles transient errors with retry logic.
      #
      # @param gdrive_id [String] Google Drive file ID
      # @param name [String] File name
      # @param error [HumataImport::TransientError] The error
      # @param options [Hash] Parsed options
      # @return [void]
      def handle_transient_error(gdrive_id, name, error, options)
        if options[:skip_retries]
          update_file_failure(gdrive_id, error.message, {})
          logger.error "✗ Failed to upload: #{name} - #{error.message} (retries skipped)"
        else
          update_file_failure(gdrive_id, error.message, {})
          logger.warn "⚠ Retryable error for: #{name} - #{error.message}"
        end
      end

      # Handles permanent errors.
      #
      # @param gdrive_id [String] Google Drive file ID
      # @param name [String] File name
      # @param error [HumataImport::PermanentError] The error
      # @return [void]
      def handle_permanent_error(gdrive_id, name, error)
        update_file_failure(gdrive_id, error.message, {})
        logger.error "✗ Permanent error for: #{name} - #{error.message}"
      end

      # Handles unexpected errors.
      #
      # @param gdrive_id [String] Google Drive file ID
      # @param name [String] File name
      # @param error [StandardError] The error
      # @return [void]
      def handle_unexpected_error(gdrive_id, name, error)
        update_file_failure(gdrive_id, error.message, {})
        logger.error "✗ Unexpected error for: #{name} - #{error.message}"
      end
    end
  end
end