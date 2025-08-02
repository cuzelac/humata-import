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
        opts.on('-h', '--help', 'Show help') { puts opts; exit }
      end
      # Parse global options up to the first non-option (the command)
      global.order!(argv)
      command = argv.shift
      case command
      when 'discover', 'upload', 'verify', 'run', 'status'
        # Placeholder: require and dispatch to command class
        puts "[Stub] Would run '#{command}' with options: #{options.inspect} and args: #{argv.inspect}"
      else
        puts global
        exit 1
      end
    end
  end
end