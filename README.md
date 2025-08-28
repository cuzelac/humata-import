# Humata.ai Google Drive Import Tool

A Ruby command-line tool for importing files from Google Drive folders into Humata.ai. Features recursive folder crawling, batch processing, comprehensive status tracking, and intelligent duplicate detection.

## Features

- 🔍 **Google Drive Integration**
  - Recursive folder crawling
  - File type filtering
  - Public URL extraction

- 📤 **Humata.ai Integration**
  - Batch file uploading
  - Processing status monitoring
  - Rate limit compliance

- 📊 **Progress Tracking**
  - SQLite-based state management
  - Detailed status reporting
  - Multiple output formats (text/JSON/CSV)

- 🛠 **Robust Error Handling**
  - Automatic retries with configurable limits
  - Failed upload retry on subsequent runs
  - Rate limiting
  - Comprehensive error reporting

- 🔄 **Smart Duplicate Detection**
  - Intelligent duplicate identification using file size + name + MIME type
  - Configurable duplicate handling strategies (skip, upload, replace)
  - Cross-session duplicate tracking
  - Performance-optimized detection with composite database indexes
  - Comprehensive duplicate reporting and analysis

## Prerequisites

1. **Ruby**
   - Ruby 2.7 or later
   - Bundler gem installed

2. **Google Drive**
   - Google Cloud project
   - Drive API enabled
   - Service account with key file

3. **Humata.ai**
   - Active Humata.ai account
   - API key

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
   # Set Humata API key
   export HUMATA_API_KEY='your-api-key'

   # Set Google application credentials
   export GOOGLE_APPLICATION_CREDENTIALS='path/to/service-account-key.json'
   ```

2. **Run complete workflow**
   ```bash
   humata-import run \
     "https://drive.google.com/drive/folders/your-folder-id" \
     --folder-id "your-humata-folder-id" \
     --database ./import_session.db \
     --verbose
   ```

   **Note**: The `run` command executes the complete workflow but doesn't support duplicate strategy options. Use the individual `discover` command for duplicate detection configuration.

## Usage

### Individual Commands

1. **Discover files with duplicate detection**
   ```bash
   humata-import discover \
     "https://drive.google.com/drive/folders/your-folder-id" \
     --database ./import_session.db \
     --duplicate-strategy skip \
     --show-duplicates
   ```

   **Duplicate handling strategies:**
   - `--duplicate-strategy skip` - Skip duplicate files (default)
   - `--duplicate-strategy upload` - Upload duplicates anyway
   - `--duplicate-strategy replace` - Replace existing files with duplicates
   - `--show-duplicates` - Display detailed duplicate information

   **Additional discover options:**
   - `--recursive` / `--no-recursive` - Control subfolder crawling (default: recursive)
   - `--max-files N` - Limit number of files to discover
   - `--timeout SECONDS` - Discovery timeout (default: 300s)

2. **Upload files**
   ```bash
   humata-import upload \
     --folder-id "your-humata-folder-id" \
     --batch-size 10 \
     --database ./import_session.db
   ```

   **Upload options:**
   - `--folder-id ID` - Humata folder ID (required)
   - `--batch-size N` - Number of files to process in parallel (default: 10)
   - `--threads N` - Number of concurrent upload threads (default: 4, max: 16)
   - `--max-retries N` - Maximum retry attempts per file (default: 3)
   - `--retry-delay N` - Base delay in seconds between retries (default: 5)
   - `--id ID` - Upload only the file with this specific gdrive_id
   - `--skip-retries` - Skip retrying failed uploads

   **Retry failed uploads:**
   ```bash
   # Automatically retry failed uploads (default behavior)
   humata-import upload \
     --folder-id "your-humata-folder-id" \
     --database ./import_session.db

   # Skip retrying failed uploads
   humata-import upload \
     --folder-id "your-humata-folder-id" \
     --skip-retries \
     --database ./import_session.db
   ```

3. **Verify processing**
   ```bash
   humata-import verify \
     --poll-interval 10 \
     --timeout 1800 \
     --database ./import_session.db
   ```

   **Verify options:**
   - `--poll-interval N` - Seconds between status checks (default: 10)
   - `--timeout N` - Verification timeout in seconds (default: 1800)
   - `--batch-size N` - Number of files to check in parallel (default: 10)

4. **Check status and duplicates**
   ```bash
   # Overall status
   humata-import status \
     --format text \
     --database ./import_session.db

   # Failed uploads only
   humata-import status \
     --failed-only \
     --database ./import_session.db

   # Export to CSV for analysis
   humata-import status \
     --format csv \
     --output status_report.csv \
     --database ./import_session.db
   ```

   **Status options:**
   - `--format FORMAT` - Output format (text/json/csv, default: text)
   - `--output FILE` - Write output to file
   - `--filter STATUS` - Filter by status (completed/failed/pending/processing)
   - `--failed-only` - Show only failed uploads with retry information

### Duplicate Detection Features

The tool provides comprehensive duplicate detection capabilities:

- **Smart Detection**: Uses file size + name + MIME type combination for reliable identification
- **Performance Optimized**: Composite database indexes ensure fast detection even with 10,000+ files
- **Cross-Session Tracking**: Detects duplicates across different import sessions
- **Flexible Handling**: Choose how to handle duplicates (skip, upload, or replace)
- **Detailed Reporting**: Get comprehensive information about duplicate groups

**Example duplicate detection output:**
```bash
🔄 Duplicate detected: document.pdf (same as: document.pdf)
⏭️  Skipping duplicate file: document.pdf

🎯 Discovery Summary:
   Total files found: 150
   New files added: 120
   Existing files skipped: 20
   Duplicate files detected: 10
   Database now contains: 150 total files

🔄 Duplicate Files Details:
   📁 Group (3 files):
      - document.pdf (1024000 bytes, application/pdf)
      - document.pdf (1024000 bytes, application/pdf)
      - document.pdf (1024000 bytes, application/pdf)
      Hash: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

### Common Options

All commands support:
- `--database PATH` - SQLite database file
- `--verbose` - Enable detailed logging
- `-h, --help` - Show command help

## Database Management

The tool automatically manages database schema updates and provides utilities for data maintenance:

```bash
# Update database schema (adds duplicate detection fields)
ruby scripts/update_schema.rb [database_path]

# Populate file hashes for existing files
ruby scripts/populate_file_hashes.rb [database_path]

# Test duplicate detection system
ruby scripts/test_duplicate_detection.rb [database_path]
```

## Documentation

- [User Guide](docs/user-guide.md) - Complete usage instructions
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Architecture Design](docs/architecture-design.md) - Technical details

## Development

### Setup

```bash
# Clone repository
git clone https://github.com/yourusername/humata-import.git
cd humata-import

# Install dependencies
bundle install

# Run tests
bundle exec rake test
```

### Testing

```bash
# Run all tests
bundle exec rake test

# Run tests with verbose logging (shows all log levels)
bundle exec rake test_verbose

# Run specific test file
bundle exec ruby -Ilib:test test/path/to/test_file.rb

# Run with verbose output
bundle exec rake test TESTOPTS="--verbose"
```

**Test Logging Behavior:**
- By default, tests only show fatal-level log messages to keep output clean
- Use `rake test_verbose` to see all log levels (debug, info, warn, error, fatal) during tests
- This helps with debugging while keeping normal test runs quiet

### Contributing

1. Fork the repository
2. Create your feature branch
3. Write tests for your changes
4. Implement your changes
5. Ensure tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/yourusername/humata-import/issues)
- [Documentation](docs/)
- [Humata.ai Support](https://humata.ai/support)