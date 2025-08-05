# Humata.ai Google Drive Import Tool - Implementation Plan

## Overview

This implementation plan details the step-by-step development of the Humata.ai Google Drive Import Tool based on the architecture design and project requirements. The plan is organized into phases that build upon each other, ensuring a working tool at each milestone.

## Development Approach

### Core Principles
- **Incremental Development**: Working functionality at each phase
- **Test-Driven**: Validate each component as it's built
- **Idempotent Design**: Each phase can be safely re-run
- **Minimal Viable Product**: Focus on core functionality first

### Prerequisites Completed ✅
- API research and documentation review
- Technology stack decisions (Ruby, SQLite, Service Account)
- Architecture design finalized
- Humata API credentials obtained and tested

## Phase A: Foundation & Core Infrastructure

**Goal**: Establish the basic project structure, database, and CLI framework

### Deliverable 1: Project Setup [✅ Completed 2024-06-09]
Create Ruby gem structure and dependencies

*Implemented: Gemfile, gemspec, .gitignore, and main module file created.*

**Files to create:**
- `Gemfile` - Ruby dependencies
- `humata-import.gemspec` - Gem specification
- `.gitignore` - Exclude sensitive files and databases
- `lib/humata_import.rb` - Main module file

**Dependencies to add to Gemfile:**
```ruby
gem 'sqlite3', '~> 1.6'
gem 'google-api-client', '~> 0.53'
```

**Representative code changes:**
```ruby
# lib/humata_import.rb
module HumataImport
  VERSION = "0.1.0"
end
```

### Deliverable 2: Database Foundation [✅ Completed 2024-06-09]
Implement SQLite database and file record model

*Implemented: Database connection, schema initialization, and file record model with basic CRUD methods.*

**Files to create:**
- `lib/humata_import/database.rb` - SQLite connection management
- `lib/humata_import/models/file_record.rb` - File record ORM

**Representative code changes:**
```ruby
# lib/humata_import/database.rb
module HumataImport
  class Database
    def self.connect(db_path)
      SQLite3::Database.new(db_path)
    end
    def self.initialize_schema(db_path)
      # Create file_records table with schema from architecture
    end
  end
end

# lib/humata_import/models/file_record.rb
module HumataImport
  class FileRecord
    def self.create(db, gdrive_id:, name:, url:, **attrs)
      # Insert new file record
    end
    
    def self.find_pending(db)
      # Query pending files for upload
    end

    def self.update_status(db, gdrive_id, status)
      # Update processing status
    end

    def self.all(db)
      # Fetch all file records
    end
  end
end
```

### Deliverable 3: CLI Framework [✅ Completed 2024-06-10]
Build command routing and argument parsing

**Files to create:**
- `bin/humata-import` - Executable CLI entry point
- `lib/humata_import/cli.rb` - Command routing and option parsing
- `lib/humata_import/commands/base.rb` - Shared command functionality

**Representative code changes:**
```ruby
# lib/humata_import/cli.rb
class CLI
  def run(args)
    # Parse global options (--database, --verbose)
    # Route to appropriate command
  end
end

# lib/humata_import/commands/base.rb
class Base
  def initialize(options)
    # Setup database connection
    # Setup logging
  end
end
```

**Test Milestone:**
```bash
./bin/humata-import --help
./bin/humata-import discover --help
./bin/humata-import upload --help
./bin/humata-import verify --help
```

## Phase B: Google Drive Integration

**Goal**: Implement the discover command for crawling Google Drive folders

### Deliverable 1: Google Drive API Client [✅ Completed 2024-06-10]
Build service account authentication and folder crawling

*Implemented: GdriveClient supports service account authentication and recursive folder crawling using the Google Drive API. Extracts file metadata (id, name, mimeType, webContentLink, size) for all files in a folder tree. Note: Implementation uses recursion; for very deep folder trees, an iterative approach may be needed due to Ruby's lack of tail call optimization.*

**Files to create:**
- `lib/humata_import/clients/gdrive_client.rb` - Google Drive API wrapper

**Representative code changes:**
```ruby
# lib/humata_import/clients/gdrive_client.rb
class GdriveClient
  def authenticate
    # Setup service account authentication
  end
  
  def list_files(folder_url, recursive: true)
    # Use files.list API to crawl folder structure
    # Extract public URLs for files
    # Handle rate limiting (100 requests/100 seconds)
  end
  
  def extract_folder_id(url)
    # Parse Google Drive folder URL to get folder ID
  end
end
```

### Deliverable 2: Discover Command Implementation
Complete the discover command with progress reporting

**Files to create:**
- `lib/humata_import/commands/discover.rb` - Discover command implementation

**Representative code changes:**
```ruby
# lib/humata_import/commands/discover.rb
class Discover < Base
  def execute(gdrive_url, options)
    # Initialize database if needed
    # Parse folder URL and crawl using GdriveClient
    # Store discovered files in database (skip duplicates)
    # Report progress and final count
  end
end
```

**Test Milestone:**
```bash
./bin/humata-import discover "https://drive.google.com/folder/ABC123" \
  --database ./test_session.db --verbose

sqlite3 test_session.db "SELECT COUNT(*) FROM file_records;"
```

## Phase C: Humata.ai Integration

**Goal**: Implement the upload command for sending files to Humata

### Deliverable 1: Humata API Client
Build API key authentication and file upload functionality

**Files to create:**
- `lib/humata_import/clients/humata_client.rb` - Humata API wrapper

**Representative code changes:**
```ruby
# lib/humata_import/clients/humata_client.rb
class HumataClient
  def upload_file(url, folder_id)
    # POST to /api/v2/import-url
    # Handle rate limiting (120 requests/minute)
    # Return full API response
  end
  
  def get_file_status(humata_id)
    # GET /api/v1/pdf/{id}
    # Return processing status
  end
end
```

### Deliverable 2: Upload Command Implementation
Complete the upload command with batch processing and response storage

**Files to create:**
- `lib/humata_import/commands/upload.rb` - Upload command implementation

**Representative code changes:**
```ruby
# lib/humata_import/commands/upload.rb
class Upload < Base
  def execute(options)
    # Query pending files from database
    # Upload in batches with concurrency control
    # Store full API responses in humata_import_response field
    # Update file records with Humata IDs and folder IDs
    # Report progress
  end
end
```

**Test Milestone:**
```bash
./bin/humata-import upload --folder-id "uuid-here" \
  --database ./test_session.db --verbose

sqlite3 test_session.db "SELECT COUNT(*) FROM file_records WHERE humata_id IS NOT NULL;"
```

## Phase D: Status Verification

**Goal**: Implement the verify command for checking processing status

### Deliverable 1: Verify Command Implementation
Complete the verify command with status polling and timeout handling

**Files to create:**
- `lib/humata_import/commands/verify.rb` - Verify command implementation

**Representative code changes:**
```ruby
# lib/humata_import/commands/verify.rb
class Verify < Base
  def execute(options)
    # Query uploaded files from database
    # Poll Humata API for processing status
    # Update processing_status and humata_verification_response in database
    # Handle timeouts and polling intervals
    # Report final status summary
  end
end
```

**Test Milestone:**
```bash
./bin/humata-import verify --database ./test_session.db \
  --poll-interval 10s --timeout 30m --verbose

sqlite3 test_session.db "SELECT processing_status, COUNT(*) FROM file_records GROUP BY processing_status;"
```

## Phase E: End-to-End Workflow

**Goal**: Implement the run command for complete workflow execution

### Deliverable 1: Run Command Implementation
Complete the run command that executes all phases in sequence

**Files to create:**
- `lib/humata_import/commands/run.rb` - Run command implementation

**Representative code changes:**
```ruby
# lib/humata_import/commands/run.rb
class Run < Base
  def execute(gdrive_url, options)
    # Execute discover phase
    # Execute upload phase
    # Execute verify phase
    # Handle failures gracefully between phases
    # Provide comprehensive progress reporting
  end
end
```

**Test Milestone:**
```bash
./bin/humata-import run "https://drive.google.com/folder/ABC123" \
  --folder-id "uuid-here" --database ./full_test.db --verbose
```

## Phase F: Status Reporting & Utilities

**Goal**: Add monitoring commands and utility enhancements

### Deliverable 1: Status Command Implementation
Complete the status command for progress monitoring

**Files to create:**
- `lib/humata_import/commands/status.rb` - Status command implementation

**Representative code changes:**
```ruby
# lib/humata_import/commands/status.rb
class Status < Base
  def execute(options)
    # Query database for current session status
    # Display progress summary
    # Show failed files and errors
    # Export status reports if requested
  end
end
```

### Deliverable 2: Utility Enhancements
Add logging and rate limiting utilities

**Files to create:**
- `lib/humata_import/utils/logger.rb` - Structured logging
- `lib/humata_import/utils/rate_limiter.rb` - API rate limiting

**Representative code changes:**
```ruby
# lib/humata_import/utils/logger.rb
class Logger
  def self.info(message)
    # Structured logging with levels
  end
end

# lib/humata_import/utils/rate_limiter.rb
class RateLimiter
  def initialize(requests_per_minute)
    # Implement rate limiting with exponential backoff
  end
end
```

## Phase G: Testing & Validation

**Goal**: Ensure reliability and handle edge cases

### Deliverable 1: Integration Testing
Create comprehensive test suite

**Files to create:**
- `spec/integration/full_workflow_spec.rb` - End-to-end workflow tests
- `spec/integration/error_handling_spec.rb` - Error scenario tests

**Representative code changes:**
```ruby
# spec/integration/full_workflow_spec.rb
RSpec.describe "Full Workflow" do
  it "processes a complete Google Drive folder import" do
    # Test end-to-end workflow
    # Verify database state at each phase
  end
end
```

### Deliverable 2: Edge Case Handling
Enhance error handling across all commands

**Areas to enhance:**
- Network timeout recovery in all API clients
- Invalid URL handling in discover command
- Permission denied scenarios
- Large dataset processing

## Phase H: Documentation & Polish

**Goal**: Production-ready tool with complete documentation

### Deliverable 1: User Documentation
Create comprehensive user guides

**Files to create:**
- `docs/user-guide.md` - Complete usage guide
- `docs/troubleshooting.md` - Common issues and solutions

**Files to update:**
- `README.md` - Update with full usage examples

### Deliverable 2: Code Polish
Final code cleanup and optimization

**Areas to polish:**
- Code comments and inline documentation
- Error message clarity and helpfulness
- Help text completeness for all commands
- Performance optimization for large datasets

## Success Criteria

### Functional Requirements ✅
- [ ] Discover files from Google Drive folders
- [ ] Upload files to Humata.ai via URL
- [ ] Track processing status for each file
- [ ] Handle thousands of files efficiently
- [ ] Idempotent operations (safe to re-run)
- [ ] Comprehensive error handling

### Technical Requirements ✅
- [ ] Ruby CLI with subcommands
- [ ] SQLite database for state management
- [ ] Service Account authentication for Google Drive
- [ ] API key authentication for Humata
- [ ] Rate limiting compliance for both APIs
- [ ] Structured logging and progress reporting

### User Experience ✅
- [ ] Clear command-line interface
- [ ] Helpful error messages
- [ ] Progress indicators
- [ ] Resume capability after interruption
- [ ] Complete status reporting

## Implementation Timeline

- **Week 1**: Phase A - Foundation & Core Infrastructure
- **Week 2**: Phase B - Google Drive Integration
- **Week 3**: Phase C - Humata.ai Integration
- **Week 4**: Phase D & E - Status Verification & End-to-End Workflow
- **Week 5**: Phase F & G - Status Reporting & Testing
- **Week 6**: Phase H - Documentation & Polish

## Risk Mitigation

### Technical Risks
- **API Changes**: Monitor API documentation for changes
- **Rate Limiting**: Implement conservative rate limiting
- **Large Datasets**: Test with thousands of files
- **Network Failures**: Robust retry and recovery mechanisms

### Development Risks
- **Scope Creep**: Focus on core functionality first
- **API Complexity**: Start with simple test cases
- **Authentication Issues**: Test service account setup early
- **Performance**: Profile with realistic data sizes

---

*This implementation plan provides a roadmap for building the Humata.ai Google Drive Import Tool. Each phase builds upon the previous one, ensuring a working tool at every milestone while maintaining focus on the core requirements.*