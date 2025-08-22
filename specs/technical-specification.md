# Humata.ai Google Drive Import Tool - Technical Specification

## Document Information

- **Version**: 1.0.0
- **Date**: December 2024
- **Project**: Humata.ai Google Drive Import Tool
- **Status**: Complete Implementation

## 1. Technology Stack

### 1.1 Core Technologies
- **Language**: Ruby 2.7+
- **Database**: SQLite 3.x
- **HTTP Client**: Standard Ruby Net::HTTP
- **CLI Framework**: Ruby OptionParser (built-in)
- **Logging**: Ruby Logger (built-in)

### 1.2 External Dependencies
```ruby
# Gemfile dependencies
gem 'sqlite3', '~> 1.6'           # SQLite database adapter
gem 'google-api-client', '~> 0.53' # Google Drive API client
```

### 1.3 Ruby Version Requirements
- **Minimum**: Ruby 2.7.0
- **Recommended**: Ruby 3.0+
- **Features Used**:
  - Keyword arguments
  - Pattern matching (Ruby 2.7+)
  - Safe navigation operator (`&.`)
  - Array#dig method
  - Modern hash syntax

## 2. API Specifications

### 2.1 Google Drive API v3

#### 2.1.1 Authentication
```ruby
# Service Account Authentication
scope = Google::Apis::DriveV3::AUTH_DRIVE_READONLY
credentials = Google::Auth.get_application_default([scope])
service.authorization = credentials
```

#### 2.1.2 File Discovery Endpoint
```ruby
# List files in folder
response = service.list_files(
  q: "'#{folder_id}' in parents",
  fields: 'nextPageToken, files(id, name, mimeType, webContentLink, size)',
  page_token: page_token,
  supports_all_drives: true,
  include_items_from_all_drives: true,
  page_size: 100
)
```

#### 2.1.3 Rate Limits
- **Quota**: 100 requests/100 seconds/user
- **Page Size**: Maximum 1000 items per request
- **Pagination**: Automatic handling with `nextPageToken`

#### 2.1.4 Error Handling
```ruby
rescue Google::Apis::Error => e
  # API errors (rate limits, permissions, etc.)
rescue Net::OpenTimeout, Net::ReadTimeout => e
  # Network timeouts
rescue StandardError => e
  # Unexpected errors
```

### 2.2 Humata.ai API

#### 2.2.1 Authentication
```ruby
# API Key Authentication
request['Authorization'] = "Bearer #{api_key}"
request['Content-Type'] = 'application/json'
```

#### 2.2.2 File Upload Endpoint
```ruby
# POST /api/v2/import-url
POST https://app.humata.ai/api/v2/import-url
Content-Type: application/json
Authorization: Bearer {api_key}

{
  "url": "https://drive.google.com/file/d/{file_id}/view?usp=drive_link",
  "folder_id": "humata-folder-uuid"
}
```

#### 2.2.3 Status Check Endpoint
```ruby
# GET /api/v1/pdf/{humata_id}
GET https://app.humata.ai/api/v1/pdf/{humata_id}
Authorization: Bearer {api_key}
```

#### 2.2.4 Rate Limits
- **Default**: 120 requests/minute
- **Configurable**: Can be increased by request
- **Implementation**: Automatic throttling with sleep

#### 2.2.5 Response Formats
```json
// Upload Response
{
  "data": {
    "pdf": {
      "id": "humata-file-id",
      "status": "pending"
    }
  }
}

// Status Response
{
  "id": "humata-file-id",
  "name": "example.pdf",
  "organization_id": "fcf6c954-ba68-4e39-a7b5-960dc8274ec0",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "number_of_pages": 1,
  "folder_id": "6c702c82-bb8a-4274-8cb6-074e0bf78084",
  "read_status": "SUCCESS",
  "created_by": "07f5bfc7-72c9-40b7-8151-dcfc2f9613dc",
  "from_url": "text",
  "file_type": "PDF"
}
```

## 3. Database Schema Details

### 3.1 File Records Table
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
  humata_pages INTEGER,
  discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  uploaded_at DATETIME,
  completed_at DATETIME,
  last_checked_at DATETIME
);
```

### 3.2 Indexes for Performance
```sql
CREATE INDEX idx_files_status ON file_records(upload_status);
CREATE INDEX idx_files_gdrive_id ON file_records(gdrive_id);
CREATE INDEX idx_files_humata_id ON file_records(humata_id);
```

### 3.3 Data Types and Constraints
- **TEXT Fields**: URLs, IDs, names, responses (JSON strings), read status
- **INTEGER Fields**: File sizes, timestamps, page counts
- **DATETIME Fields**: ISO 8601 format timestamps
- **UNIQUE Constraints**: `gdrive_id` prevents duplicate discoveries
- **DEFAULT Values**: `upload_status = 'pending'`, `discovered_at = CURRENT_TIMESTAMP`

### 3.4 New Fields for Enhanced Status Tracking
- **`humata_pages`**: INTEGER field storing the number of pages processed by Humata
- **Status Mapping**: Internal `processing_status` field maps to Humata `read_status` values
- **Data Consistency**: Page count only populated when `read_status = 'SUCCESS'`

## 4. Class Specifications

### 4.1 CLI Class (`HumataImport::CLI`)
```ruby
class CLI
  def run(argv)
    # Parse global options
    # Route to command implementations
    # Handle help and errors
  end
  
  private
  
  def print_commands_help
    # Display available commands
  end
end
```

### 4.2 Base Command Class (`HumataImport::Commands::Base`)
```ruby
class Base
  attr_reader :db, :options
  
  def initialize(options)
    @options = options
    @db = HumataImport::Database.connect(options[:database])
    HumataImport::Logger.instance.configure(options)
  end
  
  def logger
    HumataImport::Logger.instance
  end
end
```

### 4.3 Google Drive Client (`HumataImport::Clients::GdriveClient`)
```ruby
class GdriveClient
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY
  
  def initialize(service: nil, credentials: nil, timeout: 60)
    # Initialize Google Drive API client
  end
  
  def authenticate
    # Perform service account authentication
  end
  
  def list_files(folder_url, recursive: true, max_files: nil)
    # Discover files in Google Drive folder
  end
  
  private
  
  def crawl_folder(folder_id, files, recursive, max_files)
    # Recursive folder crawling with pagination
  end
  
  def extract_folder_id(url)
    # Extract folder ID from various URL formats
  end
end
```

### 4.4 Humata Client (`HumataImport::Clients::HumataClient`)
```ruby
class HumataClient
  RATE_LIMIT = 120
  API_BASE_URL = 'https://app.humata.ai'
  
  def initialize(api_key:, http_client: nil, base_url: API_BASE_URL)
    # Initialize Humata API client
  end
  
  def upload_file(url, folder_id)
    # Upload file via URL to Humata
  end
  
  def get_file_status(humata_id)
    # Check file processing status
  end
  
  private
  
  def make_request(uri, request)
    # HTTP request handling with error management
  end
  
  def enforce_rate_limit
    # Rate limiting implementation
  end
end
```

### 4.5 Logger Class (`HumataImport::Logger`)
```ruby
class Logger
  include Singleton
  
  def initialize(output = $stdout, level = :info)
    # Initialize singleton logger
  end
  
  def configure(options)
    # Configure log level based on options
  end
  
  def test_mode?
    # Detect test environment
  end
  
  # Logging methods
  def debug(message); end
  def info(message); end
  def warn(message); end
  def error(message); end
  def fatal(message); end
end
```

## 5. Command Implementation Details

### 5.1 Discover Command
```ruby
class Discover < Base
  DEFAULT_TIMEOUT = 300
  
  def run(args, gdrive_client: nil)
    # Parse command options
    # Initialize Google Drive client
    # Discover files with timeout protection
    # Store in database with duplicate detection
  end
end
```

**Key Features**:
- Timeout protection for large folders
- Duplicate detection using `INSERT OR IGNORE`
- Recursive crawling with configurable depth
- File type filtering support
- Graceful error handling for API failures

### 5.2 Upload Command
```ruby
class Upload < Base
  def run(args, humata_client: nil)
    # Parse command options
    # Initialize Humata client
    # Process files in batches
    # Handle retries and rate limiting
    # Store API responses
  end
end
```

**Key Features**:
- Batch processing with configurable size
- Automatic retry with exponential backoff
- Rate limiting (120 requests/minute)
- URL optimization for Google Drive links
- Complete API response storage

### 5.3 Verify Command
```ruby
class Verify < Base
  def run(args, humata_client: nil)
    # Parse command options
    # Initialize Humata client
    # Poll status in batches
    # Update database with status
    # Handle timeouts and errors
  end
end
```

**Key Features**:
- Configurable polling intervals
- Batch status checking
- Timeout protection
- Progress reporting
- Graceful handling of partial failures
- Enhanced status tracking with Humata metadata
- Processing status updates based on Humata read_status
- Page count storage when processing completes
- Complete API response preservation for debugging

### 5.4 Run Command
```ruby
class Run < Base
  def run(args)
    # Parse all phase options
    # Execute discover phase
    # Execute upload phase
    # Execute verify phase
    # Provide final summary
  end
end
```

**Key Features**:
- Phase coordination
- Error handling per phase
- Recovery guidance
- Comprehensive progress reporting

### 5.5 Status Command
```ruby
class Status < Base
  def run(args)
    # Parse output format options
    # Query database for statistics
    # Generate formatted output
    # Handle file output
  end
end
```

**Key Features**:
- Multiple output formats (text, JSON, CSV)
- Status filtering
- Failed upload focus
- File output support

## 6. Error Handling Specifications

### 6.1 Error Categories
```ruby
# Transient Errors (retryable)
class TransientError < StandardError; end

# Permanent Errors (not retryable)
class PermanentError < StandardError; end

# API-specific Errors
class HumataError < StandardError; end
```

### 6.2 Retry Logic
```ruby
def retry_with_backoff(max_retries: 3, base_delay: 5)
  retries = 0
  begin
    yield
  rescue TransientError => e
    retries += 1
    if retries <= max_retries
      delay = base_delay * (2 ** (retries - 1)) # Exponential backoff
      sleep(delay)
      retry
    else
      raise e
    end
  end
end
```

### 6.3 Rate Limiting
```ruby
def enforce_rate_limit
  return unless @last_request_time
  
  elapsed = Time.now - @last_request_time
  min_interval = 60.0 / RATE_LIMIT
  
  if elapsed < min_interval
    sleep_time = min_interval - elapsed
    sleep(sleep_time)
  end
end
```

## 7. URL Processing Specifications

### 7.1 Google Drive URL Patterns
```ruby
# Supported URL formats
URL_PATTERNS = [
  %r{/file/d/([a-zA-Z0-9_-]+)/},           # /file/d/{id}/view
  %r{/document/d/([a-zA-Z0-9_-]+)/},       # /document/d/{id}/
  %r{/spreadsheets/d/([a-zA-Z0-9_-]+)/},   # /spreadsheets/d/{id}/
  %r{/presentation/d/([a-zA-Z0-9_-]+)/},   # /presentation/d/{id}/
  %r{[?&]id=([a-zA-Z0-9_-]+)},             # ?id={id}
  %r{/open\?id=([a-zA-Z0-9_-]+)}           # /open?id={id}
]
```

### 7.2 URL Optimization
```ruby
def optimize_for_humata(url)
  # 1. Sanitize URL (remove problematic parameters)
  sanitized = sanitize_url(url)
  
  # 2. Convert to direct download format
  convert_google_drive_url(sanitized)
end

def sanitize_url(url)
  # Remove problematic query parameters
  # Preserve usp=drive_link
  # Remove fragments
end
```

## 8. Performance Optimizations

### 8.1 Database Optimizations
- **Indexes**: Fast lookups on frequently queried fields
- **Batch Operations**: Use `INSERT OR IGNORE` for bulk inserts
- **Connection Pooling**: Single connection per process
- **Transaction Management**: Efficient transaction handling

### 8.2 Memory Management
- **Streaming Processing**: Process files in batches, not all at once
- **Garbage Collection**: Minimal object creation in loops
- **Database Queries**: Use specific field selection, not `SELECT *`

### 8.3 Network Optimizations
- **Connection Reuse**: Reuse HTTP connections where possible
- **Batch Processing**: Minimize API calls through batching
- **Rate Limiting**: Respect API limits to avoid throttling
- **Timeout Management**: Appropriate timeouts for different operations

## 9. Testing Specifications

### 9.1 Test Structure
```
spec/
├── unit/                    # Unit tests
│   ├── clients/            # API client tests
│   ├── commands/           # Command tests
│   ├── models/             # Model tests
│   └── utils/              # Utility tests
├── integration/            # Integration tests
│   ├── clients/            # API integration tests
│   ├── commands/           # End-to-end command tests
│   └── models/             # Database integration tests
└── spec_helper.rb          # Test configuration
```

### 9.2 Test Environment
```ruby
# Test configuration
ENV['TEST_ENV'] = 'true'
ENV['HUMATA_API_KEY'] = 'test-key'
ENV['GOOGLE_APPLICATION_CREDENTIALS'] = 'test-credentials.json'

# Mock APIs for testing
class MockGoogleDriveAPI
  # Simulate Google Drive API responses
end

class MockHumataAPI
  # Simulate Humata API responses
end
```

### 9.3 Test Coverage Requirements
- **Unit Tests**: 90%+ code coverage
- **Integration Tests**: All API interactions
- **Error Scenarios**: All error handling paths
- **Performance Tests**: Load testing with large datasets

## 10. Deployment Specifications

### 10.1 Gem Packaging
```ruby
# humata-import.gemspec
Gem::Specification.new do |spec|
  spec.name          = 'humata-import'
  spec.version       = '0.1.0'
  spec.executables   = ['humata-import']
  spec.require_paths = ['lib']
  
  spec.add_runtime_dependency 'sqlite3', '~> 1.6'
  spec.add_runtime_dependency 'google-api-client', '~> 0.53'
end
```

### 10.2 Installation Methods
```bash
# From RubyGems
gem install humata-import

# From source
git clone <repository>
cd humata-import
bundle install
rake install
```

### 10.3 Environment Setup
```bash
# Required environment variables
export HUMATA_API_KEY="your-api-key"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# Optional configuration
export HUMATA_IMPORT_DB_PATH="./custom-database.db"
export HUMATA_IMPORT_LOG_LEVEL="info"
```

## 11. Security Specifications

### 11.1 Authentication Security
- **API Keys**: Never logged or stored in plain text
- **Service Accounts**: Minimal required permissions
- **Environment Variables**: Secure credential storage
- **No Hardcoded Secrets**: All credentials externalized

### 11.2 Data Security
- **Public Files Only**: Only process publicly accessible files
- **No Content Storage**: URLs only, no file content
- **Audit Trail**: Complete operation logging
- **Database Security**: File permissions and access control

### 11.3 Network Security
- **HTTPS Only**: All API communications over HTTPS
- **Certificate Validation**: Proper SSL certificate verification
- **Timeout Protection**: Prevent hanging connections
- **Rate Limiting**: Respect API limits to avoid abuse

## 12. Monitoring and Observability

### 12.1 Logging Specifications
```ruby
# Log levels and usage
logger.debug("Detailed debugging information")
logger.info("General operational information")
logger.warn("Warning conditions")
logger.error("Error conditions")
logger.fatal("Fatal errors")
```

### 12.2 Metrics Collection
- **Processing Rates**: Files per second/minute
- **Success Rates**: Upload and processing success percentages
- **Error Rates**: Failure rates by error type
- **Performance Metrics**: Response times and throughput

### 12.3 Health Checks
- **Database Connectivity**: Verify database access
- **API Connectivity**: Test Google Drive and Humata API access
- **Rate Limit Status**: Monitor API quota usage
- **Resource Usage**: Disk space, memory, and CPU monitoring

## 13. Configuration Management

### 13.1 Configuration Sources
1. **Environment Variables**: Credentials and sensitive data
2. **Command Line Options**: Runtime configuration
3. **Default Values**: Sensible defaults for all options
4. **Database Settings**: Per-session configuration storage

### 13.2 Configuration Validation
```ruby
def validate_configuration
  # Validate required environment variables
  # Validate command line options
  # Validate database connectivity
  # Validate API credentials
end
```

## 14. Future Technical Enhancements

### 14.1 Scalability Improvements
- **Database Scaling**: Support for PostgreSQL/MySQL
- **Queue Processing**: Background job processing
- **Distributed Processing**: Multi-node processing
- **Caching Layer**: Redis-based caching

### 14.2 API Enhancements
- **Bulk Operations**: Batch API endpoints
- **Webhook Support**: Real-time notifications
- **Advanced Filtering**: Complex query support
- **Streaming Uploads**: Large file support

### 14.3 Performance Optimizations
- **Connection Pooling**: Enhanced connection management
- **Parallel Processing**: Multi-threaded operations
- **Memory Optimization**: Reduced memory footprint
- **Network Optimization**: Enhanced HTTP client configuration

---

*This technical specification provides detailed implementation guidance for the Humata.ai Google Drive Import Tool. All development work should follow these specifications to ensure consistency, performance, and maintainability.* 