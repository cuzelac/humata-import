# Humata.ai Google Drive Import Tool

A Ruby command-line tool for importing files from Google Drive folders into Humata.ai. Features recursive folder crawling, batch processing, and comprehensive status tracking.

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

## Usage

### Individual Commands

1. **Discover files**
   ```bash
   humata-import discover \
     "https://drive.google.com/drive/folders/your-folder-id" \
     --file-types pdf,doc,docx \
     --database ./import_session.db
   ```

2. **Upload files**
   ```bash
   humata-import upload \
     --folder-id "your-humata-folder-id" \
     --batch-size 10 \
     --database ./import_session.db
   ```

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

4. **Check status**
   ```bash
   humata-import status \
     --format text \
     --database ./import_session.db
   ```

   **View failed uploads:**
   ```bash
   # Show only failed uploads ready for retry
   humata-import status \
     --failed-only \
     --database ./import_session.db
   ```

### Common Options

All commands support:
- `--database PATH` - SQLite database file
- `--verbose` - Enable detailed logging
- `-h, --help` - Show command help

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

# Run specific test file
bundle exec ruby -Ilib:test test/path/to/test_file.rb

# Run with verbose output
bundle exec rake test TESTOPTS="--verbose"
```

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