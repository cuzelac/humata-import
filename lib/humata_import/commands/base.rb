# frozen_string_literal: true

# Base command class providing shared functionality for all command implementations.
# Handles database connection, logger configuration, and common option processing.
#
# @author Humata Import Team
# @since 0.1.0
require_relative '../database'
require_relative '../logger'

module HumataImport
  module Commands
    # Base class for all command implementations.
    # Provides shared functionality including database connection and logger access.
    class Base
      attr_reader :db, :options
      
      def initialize(options)
        @options = options
        # Initialize the database schema before connecting to ensure tables exist
        HumataImport::Database.initialize_schema(options[:database])
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