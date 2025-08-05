# frozen_string_literal: true

require 'optparse'
require 'json'
require 'csv'
require_relative 'base'
require 'logger'

module HumataImport
  module Commands
    # Command for displaying the current status of the import session.
    # Provides progress summary and detailed reporting options.
    class Status < Base
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

      # Runs the status command.
      # @param args [Array<String>] Command-line arguments
      # @return [void]
      def run(args)
        options = {
          format: 'text',
          output: nil,
          filter: nil,
          verbose: @options[:verbose],  # Start with global verbose setting
          quiet: @options[:quiet]
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import status [options]"
          opts.on('--format FORMAT', %w[text json csv], 'Output format (text/json/csv)') { |v| options[:format] = v }
          opts.on('--output FILE', String, 'Write output to file') { |v| options[:output] = v }
          opts.on('--filter STATUS', String, 'Filter by status (completed/failed/pending/processing)') { |v| options[:filter] = v }
          opts.on('--failed-only', 'Show only failed uploads with retry information') { options[:failed_only] = true }
          opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { options[:quiet] = true }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)

        # Update logger level based on verbose setting
        @options[:verbose] = options[:verbose]
        @options[:quiet] = options[:quiet]

        # Get overall statistics
        stats = @db.execute(<<-SQL)
          SELECT processing_status, COUNT(*) as count 
          FROM file_records 
          GROUP BY processing_status
        SQL

        # Get detailed file information
        if options[:failed_only]
          raw_files = @db.execute("SELECT * FROM file_records WHERE processing_status = 'failed'")
        else
          query = "SELECT * FROM file_records"
          query += " WHERE processing_status = ?" if options[:filter]
          raw_files = @db.execute(query, options[:filter] ? [options[:filter]] : [])
        end
        
        # Convert array results to hashes using column names
        columns = @db.execute('PRAGMA table_info(file_records)').map { |col| col[1] }
        files = raw_files.map { |file| columns.zip(file).to_h }

        case options[:format]
        when 'json'
          output = generate_json_report(stats, files)
        when 'csv'
          output = generate_csv_report(files)
        else
          output = generate_text_report(stats, files, options)
        end

        if options[:output]
          File.write(options[:output], output)
          logger.info "Report written to #{options[:output]}"
        else
          puts output
        end
      end

      private

      def generate_text_report(stats, files, options)
        report = StringIO.new
        report.puts "\nImport Session Status"
        report.puts "===================="
        if options[:failed_only]
          report.puts "\nFailed Uploads Summary:"
          failed_count = files.size
          report.puts "  Failed uploads: #{failed_count} files ready for retry"
        else
          report.puts "\nOverall Progress:"
          
          total = stats.sum { |_, count| count }
          stats.each do |status, count|
            status_text = status || 'not started'
            percentage = total > 0 ? (count.to_f / total * 100).round(1) : 0
            report.puts "  #{status_text}: #{count} files (#{percentage}%)"
          end
        end

        if files.any?
          if options[:failed_only]
            report.puts "\nFailed Uploads (Ready for Retry):"
          else
            report.puts "\nDetailed File Status:"
          end
          report.puts "-" * 80
          files.each do |file|
            report.puts "#{file['name']} (#{file['gdrive_id']})"
            report.puts "  Status: #{file['processing_status'] || 'not started'}"
            report.puts "  Humata ID: #{file['humata_id'] || 'not uploaded'}"
            
            if file['humata_import_response']
              import_response = JSON.parse(file['humata_import_response'])
              if import_response['error']
                report.puts "  Import Error: #{import_response['error']}"
              end
              if import_response['attempts']
                report.puts "  Attempts: #{import_response['attempts']}"
              end
              if import_response['last_attempt']
                report.puts "  Last Attempt: #{import_response['last_attempt']}"
              end
            end
            
            if file['humata_verification_response']
              verify_response = JSON.parse(file['humata_verification_response'])
              if verify_response['error']
                report.puts "  Verification Error: #{verify_response['error']}"
              end
            end
            
            report.puts "-" * 80
          end
        end

        report.string
      end

      def generate_json_report(stats, files)
        report = {
          summary: stats.map { |status, count| { status: status || 'not started', count: count } },
          total_files: stats.sum { |_, count| count },
          files: files.map do |file|
            {
              name: file['name'],
              gdrive_id: file['gdrive_id'],
              status: file['processing_status'],
              humata_id: file['humata_id'],
              import_response: file['humata_import_response'] ? JSON.parse(file['humata_import_response']) : nil,
              verification_response: file['humata_verification_response'] ? JSON.parse(file['humata_verification_response']) : nil
            }
          end
        }
        JSON.pretty_generate(report)
      end

      def generate_csv_report(files)
        CSV.generate do |csv|
          csv << ['Name', 'Google Drive ID', 'Status', 'Humata ID', 'Import Error', 'Verification Error']
          
          files.each do |file|
            import_error = if file['humata_import_response']
              response = JSON.parse(file['humata_import_response'])
              response['error']
            end

            verify_error = if file['humata_verification_response']
              response = JSON.parse(file['humata_verification_response'])
              response['error']
            end

            csv << [
              file['name'],
              file['gdrive_id'],
              file['processing_status'] || 'not started',
              file['humata_id'] || 'not uploaded',
              import_error,
              verify_error
            ]
          end
        end
      end
    end
  end
end