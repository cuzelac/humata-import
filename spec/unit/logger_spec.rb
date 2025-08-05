# frozen_string_literal: true

require_relative '../spec_helper'

describe HumataImport::Logger do
  let(:logger) { HumataImport::Logger.instance }

  describe '#test_mode?' do
    it 'detects test mode when TEST_ENV is set' do
      original_test_env = ENV['TEST_ENV']
      ENV['TEST_ENV'] = 'true'
      _(logger.test_mode?).must_equal true
      ENV['TEST_ENV'] = original_test_env
    end

    it 'detects test mode when RACK_ENV is test' do
      original_test_env = ENV['TEST_ENV']
      original_rack_env = ENV['RACK_ENV']
      ENV['TEST_ENV'] = nil
      ENV['RACK_ENV'] = 'test'
      _(logger.test_mode?).must_equal true
      ENV['TEST_ENV'] = original_test_env
      ENV['RACK_ENV'] = original_rack_env
    end

    it 'detects test mode when RAILS_ENV is test' do
      original_test_env = ENV['TEST_ENV']
      original_rack_env = ENV['RACK_ENV']
      original_rails_env = ENV['RAILS_ENV']
      ENV['TEST_ENV'] = nil
      ENV['RACK_ENV'] = nil
      ENV['RAILS_ENV'] = 'test'
      _(logger.test_mode?).must_equal true
      ENV['TEST_ENV'] = original_test_env
      ENV['RACK_ENV'] = original_rack_env
      ENV['RAILS_ENV'] = original_rails_env
    end

    it 'detects test mode when Minitest is defined' do
      # Store original override to ensure it doesn't interfere
      original_override = logger.test_mode_override
      logger.test_mode_override = nil
      
      # Check if Minitest is actually defined in this environment
      if defined?(Minitest)
        # If Minitest is defined, test_mode? should return true
        _(logger.test_mode?).must_equal true
      else
        # If Minitest is not defined, test_mode? should return false
        _(logger.test_mode?).must_equal false
      end
      
      # Restore original override
      logger.test_mode_override = original_override
    end

    it 'uses override when set' do
      # Store original override
      original_override = logger.test_mode_override
      
      # Test with override set to false
      logger.test_mode_override = false
      _(logger.test_mode?).must_equal false
      
      # Test with override set to true
      logger.test_mode_override = true
      _(logger.test_mode?).must_equal true
      
      # Restore original override
      logger.test_mode_override = original_override
    end
  end

  describe '#configure_for_tests' do
    it 'sets fatal mode by default in test mode' do
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force test mode
      logger.test_mode_override = true
      
      # Test the configuration
      logger.configure_for_tests(verbose: false)
      _(logger.level).must_equal :fatal
      
      # Restore original level and override
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end

    it 'sets verbose mode when verbose is true in test mode' do
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force test mode
      logger.test_mode_override = true
      
      # Test the configuration
      logger.configure_for_tests(verbose: true)
      _(logger.level).must_equal :debug
      
      # Restore original level and override
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end

    it 'does not change level when not in test mode' do
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force non-test mode
      logger.test_mode_override = false
      
      # Test the configuration
      logger.configure_for_tests(verbose: false)
      _(logger.level).must_equal original_level
      
      # Restore original level and override
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end
  end

  describe 'logging in test mode' do
    it 'only logs fatal messages by default' do
      # Capture output
      output = StringIO.new
      original_logger = logger.logger
      logger.instance_variable_set(:@logger, ::Logger.new(output))
      
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force test mode and configure for quiet
      logger.test_mode_override = true
      logger.configure_for_tests(verbose: false)
      
      # Test logging
      logger.debug('Debug message')
      logger.info('Info message')
      logger.warn('Warning message')
      logger.error('Error message')
      logger.fatal('Fatal message')
      
      output.rewind
      log_output = output.read
      
      _(log_output).wont_include('Debug message')
      _(log_output).wont_include('Info message')
      _(log_output).wont_include('Warning message')
      _(log_output).wont_include('Error message')
      _(log_output).must_include('Fatal message')
      
      # Restore original logger, level, and override
      logger.instance_variable_set(:@logger, original_logger)
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end

    it 'logs all messages when verbose is enabled' do
      # Capture output
      output = StringIO.new
      original_logger = logger.logger
      logger.instance_variable_set(:@logger, ::Logger.new(output))
      
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force test mode and configure for verbose
      logger.test_mode_override = true
      logger.configure_for_tests(verbose: true)
      
      # Test logging
      logger.debug('Debug message')
      logger.info('Info message')
      logger.warn('Warning message')
      logger.error('Error message')
      
      output.rewind
      log_output = output.read
      
      _(log_output).must_include('Debug message')
      _(log_output).must_include('Info message')
      _(log_output).must_include('Warning message')
      _(log_output).must_include('Error message')
      
      # Restore original logger, level, and override
      logger.instance_variable_set(:@logger, original_logger)
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end
  end

  describe '#configure' do
    it 'applies test mode configuration when test_verbose option is provided' do
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force test mode
      logger.test_mode_override = true
      
      # Test the configuration
      logger.configure(test_verbose: true)
      _(logger.level).must_equal :debug
      
      # Restore original level and override
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end

    it 'applies normal configuration when not in test mode' do
      # Store original level and override
      original_level = logger.level
      original_override = logger.test_mode_override
      
      # Force non-test mode
      logger.test_mode_override = false
      
      # Test the configuration
      logger.configure(verbose: true)
      _(logger.level).must_equal :debug
      
      # Restore original level and override
      logger.set_level(original_level)
      logger.test_mode_override = original_override
    end
  end
end 