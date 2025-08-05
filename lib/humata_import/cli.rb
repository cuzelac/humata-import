# frozen_string_literal: true

# Main CLI interface for the Humata.ai Google Drive Import Tool.
#
# This file provides the main entry point for the CLI, handling global
# options, command routing, and help output. It depends on OptionParser
# from Ruby stdlib and loads all command implementations.
#
# Dependencies:
#   - OptionParser (stdlib)
#   - All command classes in lib/humata_import/commands/
#
# Configuration:
#   - Accepts --database and --verbose global options
#   - Uses ENV for any environment-specific config
#
# Side Effects:
#   - Exits the process on help or invalid command
#   - Prints to stdout
#
# @author Humata Import Team
# @since 0.1.0
require 'optparse'

module HumataImport
  # Main CLI class that handles command routing and global options.
  # Provides a unified interface for all import tool commands.
  class CLI
    # Runs the CLI, parsing global options and routing to the appropriate command.
    #
    # @param argv [Array<String>] The command-line arguments
    # @return [void]
    def run(argv)
      options = {
        database: './import_session.db',
        verbose: false
      }
      global = OptionParser.new do |opts|
        opts.banner = "Usage: humata-import <command> [options]"
        opts.on('--database PATH', 'SQLite database file path') { |v| options[:database] = v }
        opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
        opts.on('-h', '--help', 'Show help') { 
          puts opts
          print_commands_help
          exit 
        }
      end
      # Parse global options up to the first non-option (the command)
      global.order!(argv)
      command = argv.shift
      case command
      when 'discover'
        require_relative 'commands/discover'
        HumataImport::Commands::Discover.new(options).run(argv)
      when 'upload'
        require_relative 'commands/upload'
        HumataImport::Commands::Upload.new(options).run(argv)
      when 'verify'
        require_relative 'commands/verify'
        HumataImport::Commands::Verify.new(options).run(argv)
      when 'run'
        require_relative 'commands/run'
        HumataImport::Commands::Run.new(options).run(argv)
      when 'status'
        require_relative 'commands/status'
        HumataImport::Commands::Status.new(options).run(argv)
      else
        puts global
        print_commands_help
        exit 1
      end
    end

    private

    # Prints the list of available commands and help usage.
    #
    # @return [void]
    def print_commands_help
      puts "\nAvailable commands:"
      puts "  discover  - Discover files in a Google Drive folder"
      puts "  upload    - Upload discovered files to Humata.ai"
      puts "  verify    - Verify processing status of uploaded files"
      puts "  run       - Run complete workflow (discover + upload + verify)"
      puts "  status    - Show current import session status"
      puts "\nUse 'humata-import <command> --help' for command-specific options"
    end
  end
end