# frozen_string_literal: true

# Command for discovering files in a Google Drive folder.
#
# This file provides the Discover command, which crawls a Google Drive folder
# (optionally recursively), extracts file metadata, and stores discovered files
# in the database. Handles duplicate detection, file type filtering, and limits.
#
# Dependencies:
#   - HumataImport::Clients::GdriveClient
#   - HumataImport::FileRecord
#   - OptionParser (for option parsing)
#
# Configuration:
#   - Accepts options for recursion, max files, timeout, verbosity
#
# Side Effects:
#   - Modifies the file_records table in the database
#   - Prints to stdout
#
# @author Humata Import Team
# @since 0.1.0
require_relative 'base'
require_relative '../clients/gdrive_client'
require_relative '../models/file_record'
require 'optparse'

module HumataImport
  module Commands
    # Command for discovering files in a Google Drive folder.
    class Discover < Base
      DEFAULT_TIMEOUT = 300

      # Runs the discover command, parsing options and crawling the folder.
      #
      # @param args [Array<String>] Command-line arguments
      # @param gdrive_client [HumataImport::Clients::GdriveClient, nil] Optional injected client
      # @return [void]
      def run(args, gdrive_client: nil)
        options = {
          recursive: true,
          max_files: nil,
          timeout: DEFAULT_TIMEOUT
        }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: humata-import discover <gdrive-url> [options]"
          opts.on('--recursive', 'Crawl subfolders (default: true)') { options[:recursive] = true }
          opts.on('--no-recursive', 'Do not crawl subfolders') { options[:recursive] = false }
          opts.on('--max-files N', Integer, 'Limit number of files to discover') { |v| options[:max_files] = v }
          opts.on('--timeout SECONDS', Integer, 'Discovery timeout (default: 300s)') { |v| options[:timeout] = v }
          opts.on('-v', '--verbose', 'Enable verbose output') { @options[:verbose] = true }
          opts.on('-q', '--quiet', 'Suppress non-essential output') { @options[:quiet] = true }
        end
        parser.order!(args)
        gdrive_url = args.shift
        raise ArgumentError, 'Missing Google Drive folder URL' unless gdrive_url
        client = gdrive_client || HumataImport::Clients::GdriveClient.new(timeout: options[:timeout])
        files = client.list_files(gdrive_url, options[:recursive], options[:max_files])
        files.each do |file|
          HumataImport::FileRecord.create(
            db,
            gdrive_id: file[:id],
            name: file[:name],
            url: file[:webContentLink],
            size: file[:size],
            mime_type: file[:mimeType]
          )
        end
      end
    end
  end
end