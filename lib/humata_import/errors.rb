# frozen_string_literal: true

# Custom error hierarchy for Humata Import Tool.
#
# This file defines the error classes used throughout the application,
# providing specific error types for different failure scenarios.
#
# Dependencies:
#   - StandardError (stdlib)
#
# @author Humata Import Team
# @since 0.1.0

module HumataImport
  # Base error class for all Humata Import errors.
  class Error < StandardError; end

  # Errors related to API operations (Google Drive, Humata).
  class APIError < Error; end

  # Errors related to Google Drive API operations.
  class GoogleDriveError < APIError; end

  # Errors related to Humata API operations.
  class HumataError < APIError; end

  # Errors related to database operations.
  class DatabaseError < Error; end

  # Errors related to file operations and validation.
  class FileError < Error; end

  # Errors related to configuration and setup.
  class ConfigurationError < Error; end

  # Errors related to network connectivity and timeouts.
  class NetworkError < Error; end

  # Errors related to authentication and authorization.
  class AuthenticationError < Error; end

  # Errors related to invalid input or arguments.
  class ValidationError < Error; end

  # Errors that are transient and may be retried.
  class TransientError < Error; end

  # Errors that are permanent and should not be retried.
  class PermanentError < Error; end
end 