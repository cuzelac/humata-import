# lib/humata_import/commands/base.rb
require_relative '../database'
require_relative '../logger'

module HumataImport
  module Commands
    class Base
      attr_reader :db, :options
      
      def initialize(options)
        @options = options
        @db = HumataImport::Database.connect(options[:database])
        # Configure the singleton logger with the options
        HumataImport::Logger.instance.configure(options)
      end

      # Returns the singleton logger instance.
      # @return [HumataImport::Logger] The singleton logger
      def logger
        HumataImport::Logger.instance
      end
    end
  end
end