# lib/humata_import/cli.rb
require 'optparse'

module HumataImport
  class CLI
    def run(argv)
      options = {
        database: './import_session.db',
        verbose: false,
        quiet: false
      }
      global = OptionParser.new do |opts|
        opts.banner = "Usage: humata-import <command> [options]"
        opts.on('--database PATH', 'SQLite database file path') { |v| options[:database] = v }
        opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
        opts.on('-q', '--quiet', 'Suppress non-essential output') { options[:quiet] = true }
        opts.on('-h', '--help', 'Show help') { 
          puts opts
          puts "\nAvailable commands:"
          puts "  discover  - Discover files in a Google Drive folder"
          puts "  upload    - Upload discovered files to Humata.ai"
          puts "  verify    - Verify processing status of uploaded files"
          puts "  run       - Run complete workflow (discover + upload + verify)"
          puts "  status    - Show current import session status"
          puts "\nUse 'humata-import <command> --help' for command-specific options"
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
        puts "\nAvailable commands:"
        puts "  discover  - Discover files in a Google Drive folder"
        puts "  upload    - Upload discovered files to Humata.ai"
        puts "  verify    - Verify processing status of uploaded files"
        puts "  run       - Run complete workflow (discover + upload + verify)"
        puts "  status    - Show current import session status"
        puts "\nUse 'humata-import <command> --help' for command-specific options"
        exit 1
      end
    end
  end
end