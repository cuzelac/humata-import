# Humata.ai Google Drive Import Tool - Functional Specification

## Document Information

- **Version**: 1.0.0
- **Date**: December 2024
- **Project**: Humata.ai Google Drive Import Tool
- **Status**: Complete Implementation

## Executive Summary

The Humata.ai Google Drive Import Tool is a Ruby-based command-line application that automates the process of importing publicly accessible files from Google Drive folders into Humata.ai for document analysis and knowledge extraction. The tool implements a robust 3-phase workflow with comprehensive state management, error handling, and progress tracking.

## 1. System Overview

### 1.1 Purpose
The system provides a reliable, scalable solution for bulk document ingestion from Google Drive into Humata.ai, enabling users to process large collections of documents for AI-powered analysis and knowledge extraction.

### 1.2 Key Features
- **Recursive Google Drive folder crawling** with file discovery
- **Batch file uploading** to Humata.ai with rate limiting
- **Real-time processing status monitoring** and verification
- **Comprehensive state management** using SQLite database
- **Robust error handling** with automatic retry mechanisms
- **Flexible CLI interface** supporting individual phases or complete workflows
- **Detailed progress tracking** and reporting capabilities
- **Resumable operations** with automatic recovery from interruptions

### 1.3 Target Users
- **Content Managers**: Bulk import document collections for analysis
- **Researchers**: Process research papers and documents for knowledge extraction
- **Business Analysts**: Import business documents for AI-powered insights
- **Developers**: Integrate document processing into automated workflows

## 2. System Architecture

### 2.1 High-Level Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Google Drive  │    │  Humata.ai API  │    │  SQLite Database│
│      API        │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Humata Import Tool                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   Discover  │  │    Upload   │  │   Verify    │            │
│  │   Command   │  │   Command   │  │   Command   │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   GDrive    │  │   Humata    │  │   Status    │            │
│  │   Client    │  │   Client    │  │   Command   │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Core Components

#### 2.2.1 CLI Interface (`lib/humata_import/cli.rb`)
- **Purpose**: Main entry point and command routing
- **Responsibilities**:
  - Parse global command-line options
  - Route to appropriate command implementations
  - Display help and usage information
- **Key Methods**:
  - `run(argv)`: Main CLI entry point
  - `print_commands_help()`: Display available commands

#### 2.2.2 Database Layer (`lib/humata_import/database.rb`)
- **Purpose**: SQLite database management and schema initialization
- **Responsibilities**:
  - Database connection management
  - Schema creation and migration
  - Transaction handling
- **Key Methods**:
  - `connect(db_path)`: Create database connection
  - `initialize_schema(db_path)`: Set up database schema

#### 2.2.3 File Record Model (`lib/humata_import/models/file_record.rb`)
- **Purpose**: Data model for tracking individual files
- **Responsibilities**:
  - File record creation and updates
  - Status tracking and queries
  - Database operations abstraction
- **Key Methods**:
  - `create(db, attributes)`: Create new file record
  - `find_pending(db)`: Find files pending upload
  - `update_status(db, gdrive_id, status)`: Update file status

#### 2.2.4 Logger (`lib/humata_import/logger.rb`)
- **Purpose**: Centralized logging with configurable levels
- **Responsibilities**:
  - Structured logging across all components
  - Log level management
  - Test mode detection and configuration
- **Key Features**:
  - Singleton pattern for global access
  - Configurable log levels (debug, info, warn, error, fatal)
  - Test mode optimization (minimal output during tests)

## 3. Command Specifications

### 3.1 Base Command (`lib/humata_import/commands/base.rb`)
- **Purpose**: Shared functionality for all command implementations
- **Responsibilities**:
  - Database connection management
  - Logger configuration
  - Common option handling
- **Key Methods**:
  - `initialize(options)`: Set up database and logger
  - `logger`: Access to singleton logger instance

### 3.2 Discover Command (`lib/humata_import/commands/discover.rb`)
- **Purpose**: Phase 1 - Discover files in Google Drive folders
- **Command**: `humata-import discover <gdrive-url> [options]`

#### 3.2.1 Functionality
- Crawl Google Drive folders recursively
- Extract file metadata (ID, name, URL, size, MIME type)
- Store discovered files in database
- Handle duplicate detection and skipping
- Support file type filtering and limits

#### 3.2.2 Options
- `--recursive`: Crawl subfolders (default: true)
- `--no-recursive`: Do not crawl subfolders
- `--max-files N`: Limit number of files to discover
- `--timeout SECONDS`: Discovery timeout (default: 300s)
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output

#### 3.2.3 Error Handling
- **Google API Errors**: Logged but don't exit (allows partial discovery)
- **Network Timeouts**: Exit with error message and suggestions
- **Invalid URLs**: Exit with clear error message
- **Large Folders**: Timeout protection with user guidance

### 3.3 Upload Command (`lib/humata_import/commands/upload.rb`)
- **Purpose**: Phase 2 - Upload discovered files to Humata.ai
- **Command**: `humata-import upload --folder-id FOLDER_ID [options]`

#### 3.3.1 Functionality
- Upload files to Humata.ai in configurable batches
- Handle rate limiting and retry logic
- Store complete API responses for debugging
- Track upload status and errors
- Support retry of failed uploads

#### 3.3.2 Options
- `--folder-id ID`: Humata folder ID (required)
- `--id ID`: Upload specific file by gdrive_id
- `--batch-size N`: Files to process in parallel (default: 10)
- `--max-retries N`: Maximum retry attempts (default: 3)
- `--retry-delay N`: Seconds between retries (default: 5)
- `--skip-retries`: Skip retrying failed uploads
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output

#### 3.3.3 Error Handling
- **API Errors**: Automatic retry with exponential backoff
- **Rate Limiting**: Built-in rate limiting (120 requests/minute)
- **Network Failures**: Retry with configurable limits
- **Invalid URLs**: URL optimization to reduce 500 errors

#### 3.3.4 Interruption Handling
- **Signal Trapping**: Graceful shutdown on SIGINT/SIGTERM
- **Progress Checkpointing**: Save upload state before termination
- **Current File Completion**: Allow current file upload to complete
- **Database Consistency**: Ensure partial uploads are properly marked
- **Recovery Instructions**: Provide clear guidance for resuming operations

### 3.4 Verify Command (`lib/humata_import/commands/verify.rb`)
- **Purpose**: Phase 3 - Verify processing status of uploaded files
- **Command**: `humata-import verify [options]`

#### 3.4.1 Functionality
- Poll Humata.ai API for file processing status
- Update database with current status
- Continue polling until completion or timeout
- Handle batch processing for efficiency
- Provide real-time progress updates

#### 3.4.2 Options
- `--poll-interval N`: Seconds between status checks (default: 10)
- `--timeout N`: Total timeout in seconds (default: 1800)
- `--batch-size N`: Files to check in parallel (default: 10)
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output

#### 3.4.3 Error Handling
- **API Errors**: Logged but continue polling other files
- **Timeouts**: Graceful timeout with status summary
- **Network Issues**: Retry individual status checks
- **Partial Failures**: Continue monitoring remaining files

### 3.5 Run Command (`lib/humata_import/commands/run.rb`)
- **Purpose**: Execute complete workflow (discover + upload + verify)
- **Command**: `humata-import run <gdrive-url> --folder-id FOLDER_ID [options]`

#### 3.5.1 Functionality
- Execute all three phases in sequence
- Coordinate phase transitions
- Handle phase-specific failures
- Provide comprehensive progress reporting
- Support phase-specific options

#### 3.5.2 Options
- **Discover Options**: `--recursive`, `--max-files`
- **Upload Options**: `--folder-id`, `--batch-size`, `--max-retries`, `--retry-delay`
- **Verify Options**: `--poll-interval`, `--timeout`
- **Global Options**: `--verbose`, `--quiet`

#### 3.5.3 Error Handling
- **Phase Failures**: Exit with specific error messages
- **Recovery Guidance**: Provide commands for retrying failed phases
- **Partial Success**: Continue to next phase if possible
- **Final Summary**: Always show final status regardless of failures

### 3.6 Status Command (`lib/humata_import/commands/status.rb`)
- **Purpose**: Display current import session status and progress
- **Command**: `humata-import status [options]`

#### 3.6.1 Functionality
- Show overall progress statistics
- Display detailed file status information
- Support multiple output formats (text, JSON, CSV)
- Filter by status (completed, failed, pending, processing)
- Focus on failed uploads with retry information

#### 3.6.2 Options
- `--format FORMAT`: Output format (text/json/csv)
- `--output FILE`: Write output to file
- `--filter STATUS`: Filter by status
- `--failed-only`: Show only failed uploads
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output

#### 3.6.3 Output Formats
- **Text**: Human-readable summary with detailed file listings
- **JSON**: Structured data for programmatic processing
- **CSV**: Tabular format for spreadsheet analysis

## 4. API Client Specifications

### 4.1 Google Drive Client (`lib/humata_import/clients/gdrive_client.rb`)
- **Purpose**: Interface with Google Drive API v3
- **Dependencies**: `google-api-client` gem

#### 4.1.1 Authentication
- **Method**: Service Account authentication
- **Configuration**: `GOOGLE_APPLICATION_CREDENTIALS` environment variable
- **Scope**: `Google::Apis::DriveV3::AUTH_DRIVE_READONLY`
- **Test Mode**: Skip authentication when `TEST_ENV=true`

#### 4.1.2 Key Methods
- `initialize(service:, credentials:, timeout:)`: Client initialization
- `authenticate()`: Perform authentication
- `list_files(folder_url, recursive:, max_files:)`: Discover files in folder
- `crawl_folder(folder_id, files, recursive, max_files)`: Recursive folder crawling
- `extract_folder_id(url)`: Extract folder ID from various URL formats

#### 4.1.3 Error Handling
- **API Errors**: Logged but don't re-raise (graceful degradation)
- **Network Timeouts**: Re-raise for user handling
- **Invalid URLs**: Clear error messages with suggestions
- **Rate Limiting**: Built into Google API client

### 4.2 Humata Client (`lib/humata_import/clients/humata_client.rb`)
- **Purpose**: Interface with Humata.ai API
- **Dependencies**: Standard Ruby HTTP libraries

#### 4.2.1 Authentication
- **Method**: API key authentication
- **Configuration**: `HUMATA_API_KEY` environment variable
- **Headers**: `Authorization: Bearer {api_key}`

#### 4.2.2 Key Methods
- `initialize(api_key:, http_client:, base_url:)`: Client initialization
- `upload_file(url, folder_id)`: Upload file via URL
- `get_file_status(humata_id)`: Check processing status
- `make_request(uri, request)`: HTTP request handling
- `enforce_rate_limit()`: Rate limiting (120 requests/minute)

#### 4.2.3 Error Handling
- **HTTP Errors**: Detailed error messages with status codes
- **Network Failures**: Comprehensive error categorization
- **Rate Limiting**: Automatic throttling with sleep
- **JSON Parsing**: Graceful handling of malformed responses

## 5. Database Schema

### 5.1 File Records Table
```sql
CREATE TABLE file_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gdrive_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  size INTEGER,
  mime_type TEXT,
  humata_folder_id TEXT,
  humata_id TEXT,
  upload_status TEXT DEFAULT 'pending',
  processing_status TEXT,
  last_error TEXT,
  humata_verification_response TEXT,
  humata_import_response TEXT,
  discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  uploaded_at DATETIME,
  completed_at DATETIME,
  last_checked_at DATETIME
);
```

### 5.2 Indexes
- `idx_files_status`: Fast status-based queries
- `idx_files_gdrive_id`: Fast gdrive_id lookups
- `idx_files_humata_id`: Fast humata_id lookups

### 5.3 Status Values

#### Upload Status
- `pending`: Discovered, not yet uploaded
- `uploading`: Upload in progress
- `completed`: Successfully uploaded to Humata
- `failed`: Upload failed (after retries)
- `retrying`: Currently retrying failed upload

#### Processing Status
- `null`: Not yet uploaded
- `pending`: Uploaded, waiting for processing
- `processing`: Being processed by Humata
- `completed`: Processing complete
- `failed`: Processing failed

## 6. Utility Components

### 6.1 URL Converter (`lib/humata_import/utils/url_converter.rb`)
- **Purpose**: Optimize Google Drive URLs for Humata.ai API
- **Functionality**:
  - Convert various Google Drive URL formats
  - Sanitize URLs to remove problematic parameters
  - Extract file IDs from different URL patterns
  - Optimize URLs to reduce 500 errors

#### 6.1.1 Key Methods
- `convert_google_drive_url(url)`: Convert to direct file view format
- `google_drive_url?(url)`: Check if URL is Google Drive
- `extract_file_id(url)`: Extract file ID from URL
- `sanitize_url(url)`: Remove problematic parameters
- `optimize_for_humata(url)`: Complete URL optimization

## 7. Configuration and Environment

### 7.1 Environment Variables
```bash
# Required
export HUMATA_API_KEY="your_humata_api_key"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# Optional
export TEST_ENV="true"  # Skip authentication in tests
```

### 7.2 Global Options
- `--database PATH`: SQLite database file path (default: `./import_session.db`)
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output
- `--help, -h`: Show help information

## 8. Error Handling and Resilience

### 8.1 Error Categories
- **Transient Errors**: Network timeouts, rate limits, temporary API failures
- **Permanent Errors**: Invalid URLs, access denied, unsupported file types
- **System Errors**: Database corruption, disk space issues
- **Interruption Errors**: Process termination, signal interrupts (SIGINT/SIGTERM)

### 8.2 Recovery Mechanisms
- **Idempotent Operations**: All phases can be safely re-run
- **State Preservation**: Complete error details stored in database
- **Selective Processing**: Only unprocessed files handled on re-run
- **Graceful Degradation**: Continue processing despite individual failures
- **Interruption Recovery**: Automatic resumption from last known state
- **Database Consistency**: Transaction-based operations ensure data integrity

### 8.3 Retry Logic
- **Upload Retries**: Configurable retry attempts with exponential backoff
- **Status Polling**: Continuous polling until completion or timeout
- **Rate Limiting**: Automatic throttling to respect API limits
- **Network Resilience**: Handle temporary network issues

### 8.4 Interruption Handling
- **Signal Trapping**: Graceful shutdown on SIGINT/SIGTERM signals
- **Progress Checkpointing**: Save partial upload state before termination
- **Resource Cleanup**: Proper cleanup of database connections and file handles
- **User Feedback**: Clear indication of interruption and recovery instructions
- **Transaction Safety**: Ensure database operations complete or rollback cleanly

## 8.5 Signal Handling and Process Management

### 8.5.1 Current Implementation
The current implementation does not include explicit signal handling for process interruptions:
- **No Signal Trapping**: No `Signal.trap` calls for SIGINT/SIGTERM
- **Immediate Termination**: Ctrl-C causes immediate process termination
- **No Cleanup**: No graceful shutdown or resource cleanup
- **State Preservation**: Database state remains consistent due to transaction-based operations

### 8.5.2 Recommended Improvements
To enhance the robustness of the application, the following improvements are recommended:

#### Signal Handling
- **SIGINT (Ctrl-C)**: Graceful shutdown with progress checkpointing
- **SIGTERM**: Clean termination with resource cleanup
- **SIGUSR1**: Graceful pause/resume capability for maintenance

#### Graceful Shutdown Process
1. **Stop Accepting New Work**: Cease processing new files immediately
2. **Complete Current Operations**: Allow current file uploads to complete
3. **Save Progress State**: Update database with current progress
4. **Cleanup Resources**: Close database connections and file handles
5. **User Feedback**: Provide clear status and recovery instructions

#### Implementation Considerations
- **Transaction Management**: Use database transactions to ensure atomicity
- **Progress Checkpointing**: Save partial upload state at regular intervals
- **Resource Cleanup**: Implement proper cleanup in `ensure` blocks
- **User Experience**: Clear messaging about interruption and recovery

### 8.5.3 Benefits of Enhanced Signal Handling
- **Improved User Experience**: Clear feedback during interruptions
- **Data Consistency**: Better database state management
- **Resource Management**: Proper cleanup of system resources
- **Production Readiness**: More suitable for enterprise environments
- **Debugging Support**: Better visibility into interruption scenarios

## 9. Performance Characteristics

### 9.1 Expected Performance
- **Discovery**: ~100 files/second (Google Drive API limited)
- **Upload**: ~5-10 files/second (Humata API rate limited)
- **Verification**: ~120 status checks/minute (Humata API limit)
- **Database**: Handles 10,000+ files efficiently

### 9.2 Scalability Limits
- **Single Process**: Limited by API rate limits, not database
- **Database Size**: SQLite handles millions of records
- **Memory Usage**: Minimal (only active batch in memory)
- **Concurrent Operations**: Configurable batch sizes for parallel processing

### 9.3 Resource Requirements
- **Disk Space**: ~1KB per file record + database overhead
- **Memory**: Minimal (streaming processing)
- **Network**: Dependent on file sizes and API response times
- **CPU**: Low (mostly I/O bound operations)

## 10. Security Considerations

### 10.1 Authentication
- **Google Drive**: Service Account with minimal required permissions
- **Humata.ai**: API key authentication
- **No Hardcoded Secrets**: All credentials via environment variables

### 10.2 Data Privacy
- **Public Files Only**: Only processes publicly accessible files
- **No File Caching**: URLs only, no content storage
- **Minimal Metadata**: Only essential tracking information
- **Audit Trail**: Complete record of all operations

### 10.3 Access Control
- **Database Permissions**: Restrict database file access
- **Log Security**: No sensitive data in logs
- **Error Messages**: Sanitized error information

## 11. Testing and Quality Assurance

### 11.1 Test Structure
- **Unit Tests**: Individual component testing
- **Integration Tests**: API integration testing
- **Error Handling Tests**: Comprehensive error scenario coverage
- **Performance Tests**: Load and stress testing

### 11.2 Test Environment
- **Mock APIs**: Simulated Google Drive and Humata APIs
- **Test Database**: Isolated test database instances
- **Environment Isolation**: `TEST_ENV=true` for test mode
- **Logging Control**: Minimal output during normal test runs

### 11.3 Quality Metrics
- **Code Coverage**: Comprehensive test coverage
- **Error Handling**: All error scenarios tested
- **Performance**: Meets specified performance requirements
- **Documentation**: Complete API and usage documentation

## 12. Deployment and Operations

### 12.1 Installation
```bash
# From RubyGems
gem install humata-import

# From source
git clone <repository>
cd humata-import
bundle install
rake install
```

### 12.2 Configuration
- **Credentials Setup**: Configure Google Service Account and Humata API key
- **Database Location**: Specify database file path
- **Logging Configuration**: Set appropriate log levels
- **Rate Limiting**: Configure batch sizes and intervals

### 12.3 Monitoring
- **Progress Tracking**: Real-time status monitoring
- **Error Monitoring**: Comprehensive error logging
- **Performance Monitoring**: Track processing rates and bottlenecks
- **Resource Monitoring**: Monitor disk space and memory usage

## 13. Future Enhancements

### 13.1 Potential Features
- **Web Interface**: Browser-based management interface
- **Webhook Notifications**: Real-time completion notifications
- **Advanced Filtering**: File type and size-based filtering
- **Scheduled Operations**: Automated recurring imports
- **Multi-Provider Support**: Support for other cloud storage providers
- **Enhanced Interruption Handling**: Improved signal handling and graceful shutdown
- **Progress Persistence**: Save and restore upload progress across sessions
- **Resume Points**: User-configurable checkpoint intervals for long-running operations

### 13.2 Scalability Improvements
- **Distributed Processing**: Multi-node processing capabilities
- **Queue-Based Architecture**: Message queue for high-volume processing
- **Database Scaling**: Support for larger databases and concurrent sessions
- **API Optimization**: Enhanced rate limiting and batching strategies
- **Fault Tolerance**: Improved handling of process interruptions and system failures
- **State Management**: Enhanced transaction management and rollback capabilities

## 14. Conclusion

The Humata.ai Google Drive Import Tool provides a robust, scalable solution for bulk document ingestion from Google Drive into Humata.ai. The 3-phase workflow with comprehensive state management ensures reliable processing of large document collections, while the modular architecture supports both automated workflows and manual intervention as needed.

The tool's focus on error handling, progress tracking, and user experience makes it suitable for production use in enterprise environments, while the comprehensive documentation and testing ensure maintainability and reliability. The current design prioritizes resumability and data consistency over graceful interruption handling, which means the system can recover from interruptions but may not provide optimal user experience during process termination.

---

*This functional specification serves as the complete reference for the Humata.ai Google Drive Import Tool implementation. All development work should align with these specifications to ensure consistency and quality.* 