# frozen_string_literal: true

require 'logger'
require 'singleton'

module HumataImport
  # Singleton logger class that provides centralized logging functionality.
  # Supports different log levels and can be configured globally.
  class Logger
    include Singleton

    # @return [Logger] The underlying Ruby Logger instance
    attr_reader :logger

    # @return [Symbol] Current log level (:debug, :info, :warn, :error)
    attr_reader :level

    # @return [Boolean] Whether the logger is in test mode
    attr_reader :test_mode

    # @return [Boolean, nil] Override for test mode detection (for testing)
    attr_accessor :test_mode_override

    # Initializes the singleton logger instance.
    # @param output [IO] Output stream (default: $stdout)
    # @param level [Symbol] Initial log level (default: :info)
    def initialize(output = $stdout, level = :info)
      @logger = ::Logger.new(output)
      @level = level
      @test_mode = test_mode?
      @test_mode_override = nil
      set_level(level)
    end

    # Checks if the current environment is a test environment.
    # @return [Boolean] True if running in test mode
    def test_mode?
      return @test_mode_override unless @test_mode_override.nil?
      
      !!(ENV['TEST_ENV'] == 'true' || 
         ENV['RACK_ENV'] == 'test' || 
         ENV['RAILS_ENV'] == 'test' ||
         defined?(Minitest) ||
         defined?(RSpec))
    end

    # Sets the log level.
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @return [void]
    def set_level(level)
      @level = level
      case level
      when :debug
        @logger.level = ::Logger::DEBUG
      when :info
        @logger.level = ::Logger::INFO
      when :warn
        @logger.level = ::Logger::WARN
      when :error
        @logger.level = ::Logger::ERROR
      when :fatal
        @logger.level = ::Logger::FATAL
      else
        raise ArgumentError, "Invalid log level: #{level}"
      end
    end

    # Sets quiet mode (only error and fatal messages).
    # @return [void]
    def quiet!
      set_level(:error)
    end

    # Sets verbose mode (all messages including debug).
    # @return [void]
    def verbose!
      set_level(:debug)
    end

    # Sets normal mode (info, warn, error, fatal messages).
    # @return [void]
    def normal!
      set_level(:info)
    end

    # Configures the logger for test mode.
    # In test mode, only fatal messages are shown by default unless verbose is enabled.
    # @param verbose [Boolean] Whether to enable verbose logging in test mode
    # @return [void]
    def configure_for_tests(verbose: false)
      if test_mode?
        if verbose
          verbose!
        else
          set_level(:fatal)
        end
      end
    end

    # Logs a debug message.
    # @param message [String] The message to log
    # @return [void]
    def debug(message)
      @logger.debug(message)
    end

    # Logs an info message.
    # @param message [String] The message to log
    # @return [void]
    def info(message)
      @logger.info(message)
    end

    # Logs a warning message.
    # @param message [String] The message to log
    # @return [void]
    def warn(message)
      @logger.warn(message)
    end

    # Logs an error message.
    # @param message [String] The message to log
    # @return [void]
    def error(message)
      @logger.error(message)
    end

    # Logs a fatal message.
    # @param message [String] The message to log
    # @return [void]
    def fatal(message)
      @logger.fatal(message)
    end

    # Configures the logger based on options.
    # @param options [Hash] Options hash containing :verbose and :quiet keys
    # @return [void]
    def configure(options)
      if options[:quiet]
        quiet!
      elsif options[:verbose]
        verbose!
      else
        normal!
      end
      
      # Apply test mode configuration if in test environment
      configure_for_tests(verbose: options[:test_verbose])
    end

    # Returns the underlying Ruby Logger instance for direct access if needed.
    # @return [Logger] The Ruby Logger instance
    def to_logger
      @logger
    end

    # Changes the output stream for testing purposes.
    # @param output [IO] The new output stream
    # @return [void]
    def change_output(output)
      @logger = ::Logger.new(output)
      set_level(@level)  # Restore the current log level
    end
  end
end 