# lib/humata_import/commands/base.rb
require_relative '../database'

module HumataImport
  module Commands
    class Base
      attr_reader :db, :options
      def initialize(options)
        @options = options
        @db = HumataImport::Database.connect(options[:database])
        # Stub: setup logging here if needed
      end
    end
  end
end