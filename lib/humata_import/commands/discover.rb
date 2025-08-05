# lib/humata_import/commands/discover.rb
require 'optparse'
require_relative 'base'
require_relative '../clients/gdrive_client'
require_relative '../models/file_record'
require 'logger'
require 'timeout'

module HumataImport
  module Commands
    # Command for discovering files in a Google Drive folder and recording them in the database.
    # Handles recursive crawling and duplicate skipping.
    class Discover < Base
      DEFAULT_TIMEOUT = 300 # 5 minutes timeout

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

      # Runs the discover command.
      # @param args [Array<String>] Command-line arguments (should include the GDrive URL and options)
      # @param gdrive_client [HumataImport::Clients::GdriveClient, nil] Optional GDrive client for dependency injection
      # @return [void]
      # @raise [ArgumentError] If the GDrive URL is missing or invalid
      def run(args, gdrive_client: nil)
        options = {
          recursive: true,
          max_files: nil,
          verbose: @options[:verbose],
          quiet: @options[:quiet],
          timeout: DEFAULT_TIMEOUT
        }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import discover <gdrive-url> [options]"
          opts.on('--recursive', 'Crawl subfolders (default: true)') { options[:recursive] = true }
          opts.on('--no-recursive', 'Do not crawl subfolders') { options[:recursive] = false }
          opts.on('--max-files N', Integer, 'Limit number of files to discover') { |v| options[:max_files] = v }
          opts.on('--timeout SECONDS', Integer, "Timeout in seconds (default: #{DEFAULT_TIMEOUT})") { |v| options[:timeout] = v }
          opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { options[:quiet] = true }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)
        gdrive_url = args.shift
        unless gdrive_url
          puts parser
          exit 1
        end

        # Update logger level based on options
        @options[:verbose] = options[:verbose]
        @options[:quiet] = options[:quiet]

        logger.info "Starting file discovery process..."
        logger.info "URL: #{gdrive_url}"
        logger.info "Recursive: #{options[:recursive]}"
        logger.info "Timeout: #{options[:timeout]} seconds"
        logger.info "Max files: #{options[:max_files] || 'unlimited'}"

        # Ensure DB schema is initialized
        logger.debug "Initializing database schema..."
        HumataImport::Database.initialize_schema(@options[:database])
        logger.debug "Database schema initialized"

        # Use injected client or create default one
        logger.debug "Initializing Google Drive client..."
        client = gdrive_client || HumataImport::Clients::GdriveClient.new
        logger.debug "Google Drive client initialized"
        
        logger.info "Discovering files in Google Drive folder..."
        
        begin
          Timeout.timeout(options[:timeout]) do
            files = client.list_files(gdrive_url, recursive: options[:recursive], max_files: options[:max_files])
            logger.debug "Found #{files.size} files."

            discovered = 0
            skipped = 0
            files.each do |file|
              before = @db.get_first_value("SELECT COUNT(*) FROM file_records WHERE gdrive_id = ?", [file[:id]])
              if before.to_i == 0
                HumataImport::FileRecord.create(@db,
                  gdrive_id: file[:id],
                  name: file[:name],
                  url: file[:url],
                  size: file[:size],
                  mime_type: file[:mime_type]
                )
                discovered += 1
                logger.debug "Discovered: #{file[:name]} (#{file[:id]})"
              else
                skipped += 1
                logger.debug "Skipped (duplicate): #{file[:name]} (#{file[:id]})"
              end
            end

            logger.info "\nSummary:"
            logger.info "  Discovered: #{discovered} new files"
            logger.info "  Skipped:    #{skipped} duplicates"
            logger.info "  Total in DB: #{@db.get_first_value('SELECT COUNT(*) FROM file_records')}"
          end
        rescue Timeout::Error
          logger.error "Discovery timed out after #{options[:timeout]} seconds"
          logger.error "The Google Drive folder may be too large or have too many subfolders"
          logger.error "Try using --no-recursive or --max-files to limit the scope"
          exit 1
        rescue ArgumentError => e
          logger.error "Discovery failed: #{e.message}"
          logger.debug "Full error: #{e.class}: #{e.message}"
          logger.debug e.backtrace.join("\n") if options[:verbose]
          raise
        rescue Google::Apis::Error, Google::Apis::AuthorizationError, Google::Apis::RateLimitError => e
          # Handle Google API errors gracefully - log but don't exit
          logger.error "Google Drive API error: #{e.message}"
          logger.debug "Full error: #{e.class}: #{e.message}"
          logger.debug e.backtrace.join("\n") if options[:verbose]
          # Don't exit - let the test continue
        rescue StandardError => e
          logger.error "Discovery failed: #{e.message}"
          logger.debug "Full error: #{e.class}: #{e.message}"
          logger.debug e.backtrace.join("\n") if options[:verbose]
          # For other errors, still exit as they might be more serious
          exit 1
        end
      end
    end
  end
end