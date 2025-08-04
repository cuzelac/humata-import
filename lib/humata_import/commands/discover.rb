# lib/humata_import/commands/discover.rb
require 'optparse'
require_relative 'base'
require_relative '../clients/gdrive_client'
require_relative '../models/file_record'
require 'logger'

module HumataImport
  module Commands
    # Command for discovering files in a Google Drive folder and recording them in the database.
    # Handles recursive crawling, file type filtering, and duplicate skipping.
    class Discover < Base
      DEFAULT_FILE_TYPES = %w[pdf doc docx txt]

      def logger
        @logger ||= Logger.new($stdout).tap do |log|
          log.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO
        end
      end

      # Runs the discover command.
      # @param args [Array<String>] Command-line arguments (should include the GDrive URL and options)
      # @return [void]
      # @raise [ArgumentError] If the GDrive URL is missing or invalid
      def run(args)
        options = {
          recursive: true,
          file_types: DEFAULT_FILE_TYPES,
          max_files: nil
        }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import discover <gdrive-url> [options]"
          opts.on('--recursive', 'Crawl subfolders (default: true)') { options[:recursive] = true }
          opts.on('--no-recursive', 'Do not crawl subfolders') { options[:recursive] = false }
          opts.on('--file-types x,y,z', Array, 'Filter by file types (default: pdf,doc,docx,txt)') { |v| options[:file_types] = v.map(&:strip) }
          opts.on('--max-files N', Integer, 'Limit number of files to discover') { |v| options[:max_files] = v }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)
        gdrive_url = args.shift
        unless gdrive_url
          puts parser
          exit 1
        end

        # Ensure DB schema is initialized
        HumataImport::Database.initialize_schema(@options[:database])

        client = HumataImport::Clients::GdriveClient.new
        logger.debug "Discovering files in Google Drive folder..."
        files = client.list_files(gdrive_url, recursive: options[:recursive])
        logger.debug "Found #{files.size} files before filtering."

        # Filter by file type
        filtered = files.select do |f|
          ext = File.extname(f[:name]).downcase.delete_prefix('.')
          options[:file_types].include?(ext)
        end
        logger.debug "#{filtered.size} files match type filter: #{options[:file_types].join(', ')}."

        # Apply max_files limit
        if options[:max_files]
          filtered = filtered.first(options[:max_files])
          logger.debug "Limiting to first #{filtered.size} files due to --max-files."
        end

        discovered = 0
        skipped = 0
        filtered.each do |file|
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
    end
  end
end