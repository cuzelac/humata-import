# Humata.ai Google Drive Import Tool

A Ruby command-line tool for importing files from Google Drive folders into Humata.ai. Features recursive folder crawling, batch processing, comprehensive status tracking, and intelligent duplicate detection.

## What It Does

This tool automates the process of importing publicly accessible files from Google Drive into Humata.ai for AI-powered document analysis. It works in three phases:

1. **Discover** - Crawls Google Drive folders to find files
2. **Upload** - Uploads discovered files to Humata.ai 
3. **Verify** - Monitors processing status until completion

The tool maintains a SQLite database to track progress, handle duplicates intelligently, and provide resumable operations.

## Key Features

- 🔍 **Google Drive Integration**
  - Recursive folder crawling with configurable limits
  - File metadata extraction (name, size, type, timestamps)
  - Public URL generation for Humata.ai processing

- 📤 **Humata.ai Integration**
  - Batch file uploading with parallel processing
  - Rate limit compliance (120 requests/minute)
  - Processing status monitoring and verification

- 📊 **Progress Tracking**
  - SQLite-based state management
  - Detailed status reporting with multiple output formats
  - Resumable operations across sessions

- 🛠 **Robust Error Handling**
  - Automatic retries with exponential backoff
  - Failed upload retry on subsequent runs
  - Comprehensive error logging and reporting

- 🔄 **Smart Duplicate Detection**
  - Identifies duplicates using file size + name + MIME type
  - Configurable handling strategies (skip, upload, replace, track)
  - Cross-session duplicate tracking
  - Performance-optimized with database indexes

## Prerequisites

1. **Ruby** - Ruby 2.7 or later with Bundler
2. **Google Drive** - Service account with Drive API access
3. **Humata.ai** - Active account with API key

## Installation

```bash
# Install from RubyGems
gem install humata-import

# Or build from source
git clone https://github.com/yourusername/humata-import.git
cd humata-import
bundle install
rake install
```

## Quick Start

1. **Set up credentials**
   ```bash
   export HUMATA_API_KEY='your-api-key'
   export GOOGLE_APPLICATION_CREDENTIALS='path/to/service-account-key.json'
   ```

2. **Run complete workflow**
   ```bash
   humata-import run \
     "https://drive.google.com/drive/folders/your-folder-id" \
     --folder-id "your-humata-folder-id" \
     --verbose
   ```

## Usage

### Complete Workflow
```bash
# Run all phases in sequence
humata-import run <gdrive-url> --folder-id <humata-folder-id>
```

### Individual Commands

**Discover files:**
```bash
humata-import discover <gdrive-url> [options]
# Options: --recursive, --max-files, --duplicate-strategy, --timeout
```

**Upload files:**
```bash
humata-import upload --folder-id <id> [options]
# Options: --batch-size, --threads, --max-retries, --retry-delay
```

**Verify processing:**
```bash
humata-import verify [options]
# Options: --poll-interval, --timeout, --batch-size
```

**Check status:**
```bash
humata-import status [options]
# Options: --format, --output, --filter, --failed-only
```

### Duplicate Handling

The tool automatically detects duplicates during discovery and provides strategies:

- `skip` - Skip duplicate files (default)
- `upload` - Upload and mark as duplicates
- `replace` - Replace original with duplicate
- `track-duplicates` - Track all files with duplicate marking

### Performance Options

- **Parallel processing**: Up to 16 concurrent upload threads
- **Batch operations**: Configurable batch sizes for discovery and upload
- **Rate limiting**: Built-in compliance with Humata.ai API limits
- **Retry logic**: Configurable retry attempts with exponential backoff

## Database Management

The tool automatically manages its SQLite database. For existing databases, use the migration scripts:

```bash
# Update schema for new features
ruby scripts/update_schema.rb [database_path]

# Populate data for existing records
ruby scripts/populate_file_hashes.rb [database_path]
ruby scripts/populate_duplicate_relationships.rb [database_path]
```

## Architecture Overview

The application is organized into several key components:

- **CLI Interface** (`lib/humata_import/cli.rb`) - Main entry point and command routing
- **Commands** (`lib/humata_import/commands/`) - Individual command implementations
- **Clients** (`lib/humata_import/clients/`) - API clients for Google Drive and Humata.ai
- **Models** (`lib/humata_import/models/`) - Data models and database operations
- **Database** (`lib/humata_import/database.rb`) - SQLite connection and schema management
- **Utilities** (`lib/humata_import/utils/`) - Helper functions and URL processing

Each component follows dependency injection patterns for testability and uses Ruby's standard library where possible.

## Development

```bash
# Setup
git clone <repository>
cd humata-import
bundle install

# Testing
bundle exec rake test
bundle exec rake test_verbose  # For detailed logging
```

## Documentation

- [Functional Specification](specs/functional-specification.md) - Complete technical specification
- [User Guide](docs/user-guide.md) - Detailed usage instructions
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/yourusername/humata-import/issues)
- [Documentation](docs/)
- [Humata.ai Support](https://humata.ai/support)