# frozen_string_literal: true

require 'logger'

module HumataImport
  # Singleton logger class that provides centralized logging functionality.
  # Supports different log levels and can be configured globally.
  class Logger
    include Singleton

    # @return [Logger] The underlying Ruby Logger instance
    attr_reader :logger

    # @return [Symbol] Current log level (:debug, :info, :warn, :error)
    attr_reader :level

    # Initializes the singleton logger instance.
    # @param output [IO] Output stream (default: $stdout)
    # @param level [Symbol] Initial log level (default: :info)
    def initialize(output = $stdout, level = :info)
      @logger = ::Logger.new(output)
      @level = level
      set_level(level)
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
    end

    # Returns the underlying Ruby Logger instance for direct access if needed.
    # @return [Logger] The Ruby Logger instance
    def to_logger
      @logger
    end
  end
end 