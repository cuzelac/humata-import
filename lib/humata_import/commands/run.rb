# frozen_string_literal: true

require 'optparse'
require_relative 'base'
require_relative 'discover'
require_relative 'upload'
require_relative 'verify'
require 'logger'

module HumataImport
  module Commands
    # Command for running the complete workflow: discover, upload, and verify.
    # Handles phase coordination and error recovery between phases.
    class Run < Base
      def logger
        @logger ||= Logger.new($stdout).tap do |log|
          log.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO
        end
      end

      # Runs the complete workflow.
      # @param args [Array<String>] Command-line arguments
      # @return [void]
      def run(args)
        options = {
          recursive: true,
          batch_size: 10,
          max_retries: 3,
          retry_delay: 5,
          poll_interval: 10,
          timeout: 1800
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import run <gdrive-url> --folder-id FOLDER_ID [options]"
          
          # Discover options
          opts.on('--recursive', 'Crawl subfolders (default: true)') { options[:recursive] = true }
          opts.on('--no-recursive', 'Do not crawl subfolders') { options[:recursive] = false }
          opts.on('--max-files N', Integer, 'Limit number of files to discover') { |v| options[:max_files] = v }
          
          # Upload options
          opts.on('--folder-id ID', String, 'Humata folder ID (required)') { |v| options[:folder_id] = v }
          opts.on('--batch-size N', Integer, 'Files to process in parallel (default: 10)') { |v| options[:batch_size] = v }
          opts.on('--max-retries N', Integer, 'Maximum retry attempts (default: 3)') { |v| options[:max_retries] = v }
          opts.on('--retry-delay N', Integer, 'Seconds between retries (default: 5)') { |v| options[:retry_delay] = v }
          
          # Verify options
          opts.on('--poll-interval N', Integer, 'Seconds between status checks (default: 10)') { |v| options[:poll_interval] = v }
          opts.on('--timeout N', Integer, 'Verification timeout in seconds (default: 1800)') { |v| options[:timeout] = v }
          
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)
        
        gdrive_url = args.shift
        unless gdrive_url && options[:folder_id]
          puts parser
          exit 1
        end

        unless ENV['HUMATA_API_KEY']
          logger.error "HUMATA_API_KEY environment variable not set"
          exit 1
        end

        # Phase 1: Discover
        logger.info "\n=== Phase 1: Discovering Files ==="
        discover_args = [
          gdrive_url,
          '--recursive'
        ]
        discover_args.concat(['--max-files', options[:max_files].to_s]) if options[:max_files]
        discover_args.concat(['--database', @options[:database]]) if @options[:database]
        discover_args.concat(['--verbose']) if @options[:verbose]

        discover = Discover.new(@options)
        begin
          discover.run(discover_args)
        rescue StandardError => e
          logger.error "Discover phase failed: #{e.message}"
          exit 1
        end

        # Phase 2: Upload
        logger.info "\n=== Phase 2: Uploading Files ==="
        upload_args = [
          '--folder-id', options[:folder_id],
          '--batch-size', options[:batch_size].to_s,
          '--max-retries', options[:max_retries].to_s,
          '--retry-delay', options[:retry_delay].to_s
        ]
        upload_args.concat(['--database', @options[:database]]) if @options[:database]
        upload_args.concat(['--verbose']) if @options[:verbose]

        upload = Upload.new(@options)
        begin
          upload.run(upload_args)
        rescue StandardError => e
          logger.error "Upload phase failed: #{e.message}"
          logger.warn "You can retry the upload phase with: humata-import upload --folder-id #{options[:folder_id]}"
          exit 1
        end

        # Phase 3: Verify
        logger.info "\n=== Phase 3: Verifying Processing ==="
        verify_args = [
          '--poll-interval', options[:poll_interval].to_s,
          '--timeout', options[:timeout].to_s,
          '--batch-size', options[:batch_size].to_s
        ]
        verify_args.concat(['--database', @options[:database]]) if @options[:database]
        verify_args.concat(['--verbose']) if @options[:verbose]

        verify = Verify.new(@options)
        begin
          verify.run(verify_args)
        rescue StandardError => e
          logger.error "Verify phase failed: #{e.message}"
          logger.warn "You can retry the verify phase with: humata-import verify"
          exit 1
        end

        logger.info "\n=== Workflow Complete ==="
        
        # Show final status summary
        results = @db.execute(<<-SQL)
          SELECT processing_status, COUNT(*) as count 
          FROM file_records 
          GROUP BY processing_status
        SQL

        logger.info "\nFinal Status Summary:"
        results.each do |status, count|
          logger.info "  #{status || 'not started'}: #{count} files"
        end
      end
    end
  end
end