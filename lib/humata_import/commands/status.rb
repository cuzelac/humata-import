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
          log.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO
        end
      end

      # Runs the status command.
      # @param args [Array<String>] Command-line arguments
      # @return [void]
      def run(args)
        options = {
          format: 'text',
          output: nil,
          filter: nil
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import status [options]"
          opts.on('--format FORMAT', %w[text json csv], 'Output format (text/json/csv)') { |v| options[:format] = v }
          opts.on('--output FILE', String, 'Write output to file') { |v| options[:output] = v }
          opts.on('--filter STATUS', String, 'Filter by status (completed/failed/pending/processing)') { |v| options[:filter] = v }
          opts.on('-h', '--help', 'Show help') { puts opts; exit }
        end
        parser.order!(args)

        # Get overall statistics
        stats = @db.execute(<<-SQL)
          SELECT processing_status, COUNT(*) as count 
          FROM file_records 
          GROUP BY processing_status
        SQL

        # Get detailed file information
        query = "SELECT * FROM file_records"
        query += " WHERE processing_status = ?" if options[:filter]
        files = @db.execute(query, options[:filter] ? [options[:filter]] : [])

        case options[:format]
        when 'json'
          output = generate_json_report(stats, files)
        when 'csv'
          output = generate_csv_report(files)
        else
          output = generate_text_report(stats, files)
        end

        if options[:output]
          File.write(options[:output], output)
          logger.info "Report written to #{options[:output]}"
        else
          puts output
        end
      end

      private

      def generate_text_report(stats, files)
        report = StringIO.new
        report.puts "\nImport Session Status"
        report.puts "===================="
        report.puts "\nOverall Progress:"
        
        total = stats.sum { |_, count| count }
        stats.each do |status, count|
          status_text = status || 'not started'
          percentage = total > 0 ? (count.to_f / total * 100).round(1) : 0
          report.puts "  #{status_text}: #{count} files (#{percentage}%)"
        end

        if files.any?
          report.puts "\nDetailed File Status:"
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