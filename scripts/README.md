# Scripts Directory

This directory contains utility scripts for the Humata Import project.

## Database Schema Management Scripts

### Schema Update Script (`update_schema.rb`)

Updates existing databases to match the current expected schema. This script is safe to run multiple times and will only add missing columns and indexes.

#### Usage
```bash
# Update default database
ruby scripts/update_schema.rb

# Update specific database
ruby scripts/update_schema.rb /path/to/database.db
```

#### What It Does
- Creates automatic backups before any schema changes
- Adds missing columns for new features (e.g., duplicate detection)
- Creates missing indexes for performance optimization
- Provides guidance on additional steps needed

#### Example Output
```
🔧 Updating database schema: ./import_session.db
💾 Created backup: ./import_session.db.backup.1703123456
📋 Current columns: id, gdrive_id, name, url, size, mime_type, ...
➕ Adding column 'file_hash' (TEXT)
✅ Successfully added column 'file_hash'
➕ Adding index 'idx_files_file_hash' on columns: file_hash
✅ Successfully added index 'idx_files_file_hash'
✅ Schema update completed! Applied 2 updates.

🔍 Checking file hash population needs...
📊 Found 150 records without file_hash
💡 To populate file hashes for duplicate detection, run:
   ruby scripts/populate_file_hashes.rb ./import_session.db

   This will enable duplicate detection for all existing files.
```

### File Hash Population Script (`populate_file_hashes.rb`)

Populates the `file_hash` column for existing database records, enabling duplicate detection for files that were discovered before this feature was implemented.

#### Prerequisites
- Run `update_schema.rb` first to add the `file_hash` column
- Database must contain file records with `size`, `name`, and `mime_type` data

#### Usage
```bash
# Populate file hashes in default database
ruby scripts/populate_file_hashes.rb

# Populate file hashes in specific database
ruby scripts/populate_file_hashes.rb /path/to/database.db
```

#### What It Does
- Identifies records without `file_hash` values
- Generates MD5 hashes using the same logic as the discovery process
- Updates all existing records to enable duplicate detection
- Provides progress reporting and error handling

#### Example Output
```
🔍 File Hash Population Script
Database: ./import_session.db
📊 Found 150 records without file_hash

🔄 Starting file hash population...
📊 Progress: 100/150 records updated
📊 Progress: 150/150 records updated

🎯 Population Summary:
   Total records processed: 150
   Successfully updated: 150
   Failed updates: 0

✅ File hash population completed successfully!
   Duplicate detection is now fully functional for all records.
```

#### When to Use
- **After running `update_schema.rb`** and seeing records without file_hash
- **Before running duplicate detection** on existing databases
- **To enable full duplicate detection functionality** for all files

#### Benefits
- **Enables duplicate detection** for existing files
- **Improves discovery performance** by avoiding re-processing
- **Maintains data consistency** across the entire database
- **Provides comprehensive duplicate analysis** for all files

### Duplicate Relationship Population Script (`populate_duplicate_relationships.rb`)

Establishes duplicate relationships between files that have been identified as duplicates, creating a hierarchical structure for duplicate management.

#### Prerequisites
- Run `update_schema.rb` first to add required columns
- Run `populate_file_hashes.rb` to ensure all files have hash values
- Database must contain files with duplicate detection data

#### Usage
```bash
# Populate duplicate relationships in default database
ruby scripts/populate_duplicate_relationships.rb

# Populate duplicate relationships in specific database
ruby scripts/populate_duplicate_relationships.rb /path/to/database.db
```

#### What It Does
- Identifies files that need duplicate relationships established
- Creates `duplicate_of_gdrive_id` references to link duplicates
- Maintains the first discovered file as the "original"
- Provides comprehensive reporting on relationship creation

## Testing and Validation Scripts

### Production Validation Script (`production_validation.rb`)

Comprehensive validation script that tests all aspects of the duplicate detection system to ensure production readiness.

#### Usage
```bash
# Validate default database
ruby scripts/production_validation.rb

# Validate specific database
ruby scripts/production_validation.rb /path/to/database.db
```

#### What It Tests
- Core system functionality (file hash population, duplicate detection)
- Performance metrics and optimization
- Data integrity and consistency
- Error handling and recovery mechanisms
- Production readiness assessment

### CLI Integration Test Script (`test_cli_integration.rb`)

Tests the complete CLI workflow with duplicate detection, including all strategies and reporting options.

#### Usage
```bash
# Test CLI integration with default database
ruby scripts/test_cli_integration.rb

# Test CLI integration with specific database
ruby scripts/test_cli_integration.rb /path/to/database.db
```

#### What It Tests
- Discover command with duplicate detection enabled
- Duplicate strategy options and configurations
- Duplicate reporting and output formats
- Performance with large datasets
- Error handling and edge cases

### Duplicate Detection Test Script (`test_duplicate_detection.rb`)

Comprehensive testing of the duplicate detection system with real data from the database.

#### Usage
```bash
# Test duplicate detection with default database
ruby scripts/test_duplicate_detection.rb

# Test duplicate detection with specific database
ruby scripts/test_duplicate_detection.rb /path/to/database.db
```

#### What It Tests
- File hash population verification
- Duplicate detection methods and algorithms
- Duplicate grouping and categorization
- Duplicate handling strategies
- Performance benchmarks and optimization

### Discover Command Hang Diagnostic Tool (`test_discover_hang.rb`)

Diagnoses hanging issues in the discover command by testing individual components in isolation with timeout protection.

#### Usage
```bash
# Diagnose hanging issues with default timeout
ruby scripts/test_discover_hang.rb "https://drive.google.com/drive/folders/abc123"

# Diagnose with custom timeout
ruby scripts/test_discover_hang.rb "https://drive.google.com/drive/folders/abc123" --timeout 120
```

#### What It Tests
- Environment setup and Ruby configuration
- Database initialization and connectivity
- Google Drive authentication process
- URL parsing and validation
- File listing functionality

#### Requirements
- `GOOGLE_APPLICATION_CREDENTIALS` environment variable set
- Valid Google Drive folder URL
- Ruby dependencies installed via bundler

## Humata API Integration Scripts

### Humata PDF Retrieval Script (`humata_get_pdf.rb`)

Retrieves PDF documents from the Humata API using a PDF ID, demonstrating basic HTTP client usage and API authentication.

#### Usage
```bash
# Retrieve PDF with basic output
ruby scripts/humata_get_pdf.rb <pdf_id>

# Retrieve PDF with verbose output
ruby scripts/humata_get_pdf.rb <pdf_id> --verbose
```

#### Options
- `-v, --verbose` - Output HTTP status code and response body

#### Requirements
- `HUMATA_API_KEY` environment variable must be set
- Valid PDF ID from Humata system

#### Example
```bash
export HUMATA_API_KEY="your_api_key_here"
ruby scripts/humata_get_pdf.rb pdf_123 --verbose
```

### Humata File Upload Script (`humata_upload.rb`)

Uploads files to Humata by providing a public URL and folder ID, demonstrating file import functionality using the Humata API v2.

#### Usage
```bash
# Upload file with required parameters
ruby scripts/humata_upload.rb --url <file_url> --folder-id <folder_id>

# Upload with verbose output
ruby scripts/humata_upload.rb --url <file_url> --folder-id <folder_id> --verbose
```

#### Options
- `--url URL` - The public file URL to import (required)
- `--folder-id ID` - The Humata folder UUID (required)
- `-v, --verbose` - Output HTTP status code and response body

#### Requirements
- `HUMATA_API_KEY` environment variable must be set
- Valid public file URL
- Valid Humata folder UUID

#### Example
```bash
export HUMATA_API_KEY="your_api_key_here"
ruby scripts/humata_upload.rb --url "https://example.com/document.pdf" --folder-id "abc123-def456"
```

## Google Authentication Test Script

The `test_google_auth.rb` script helps you verify that your Google Drive API authentication is working correctly.

### Prerequisites

1. **Google Service Account**: You need a Google Cloud service account with Drive API access
2. **Service Account JSON File**: Download the JSON credentials file from Google Cloud Console
3. **Ruby Dependencies**: Ensure the `google-api-client` gem is installed

### Setup

1. **Create a Service Account**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to "IAM & Admin" > "Service Accounts"
   - Create a new service account or use an existing one
   - Enable the Google Drive API for your project
   - Download the JSON credentials file

2. **Set Environment Variable** (optional):
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account.json"
   ```

### Usage

#### Basic Test (using environment variable)
```bash
bundle exec ruby scripts/test_google_auth.rb
```

#### Test with specific credentials file
```bash
bundle exec ruby scripts/test_google_auth.rb --credentials-file /path/to/service-account.json
```

#### Test with folder access
```bash
bundle exec ruby scripts/test_google_auth.rb --test-folder-id "your-folder-id-here"
```

#### Verbose output for debugging
```bash
bundle exec ruby scripts/test_google_auth.rb --verbose
```

#### Show help
```bash
bundle exec ruby scripts/test_google_auth.rb --help
```

### What the Script Tests

1. **Environment Variables**: Checks if `GOOGLE_APPLICATION_CREDENTIALS` is set
2. **Credentials File**: Validates the JSON structure and required fields
3. **Authentication**: Tests obtaining application default credentials
4. **API Connectivity**: Makes a test API call to verify connectivity
5. **File Listing** (optional): Lists files in a specified folder

### Example Output

```
🔐 Google Authentication Test Script
==================================================

📋 Test 1: Environment Variables
------------------------------
✅ GOOGLE_APPLICATION_CREDENTIALS is set: /path/to/service-account.json
✅ Credentials file exists at specified path
📊 File size: 2345 bytes
✅ Credentials file is not empty

📄 Test 2: Credentials File Validation
-----------------------------------
✅ Credentials file contains all required fields
📊 Project ID: my-project-123
📧 Client Email: service-account@my-project-123.iam.gserviceaccount.com
🔑 Type: service_account

🔑 Test 3: Authentication
--------------------
✅ Successfully obtained application default credentials
📊 Scope: https://www.googleapis.com/auth/drive.readonly
✅ Successfully initialized Google Drive service

🌐 Test 4: API Connectivity
----------------------
✅ Successfully connected to Google Drive API
📊 User: Service Account
📊 Email: service-account@my-project-123.iam.gserviceaccount.com
💾 Storage Quota:
   - Total: 15.00 GB
   - Used: 1.25 GB
   - Available: 13.75 GB

==================================================
📊 Test Summary
==================================================
✅ Passed: 4/4
❌ Failed: 0/4

🎉 All tests passed! Google authentication is working correctly.
```

### Troubleshooting

#### Common Issues

1. **"Default credentials error"**
   - Ensure your service account JSON file is valid
   - Check that the file path is correct
   - Verify the service account has the necessary permissions

2. **"Authorization error"**
   - Make sure the Google Drive API is enabled in your Google Cloud project
   - Verify the service account has Drive API access
   - Check that the folder you're trying to access is shared with the service account

3. **"Network timeout"**
   - Check your internet connection
   - Verify firewall settings aren't blocking the connection

4. **"Client error"**
   - Ensure the folder ID is correct
   - Verify the folder exists and is accessible

#### Getting a Folder ID

To get a Google Drive folder ID:
1. Open the folder in Google Drive
2. Look at the URL: `https://drive.google.com/drive/folders/FOLDER_ID_HERE`
3. Copy the folder ID (the long string after `/folders/`)

### Security Notes

- Keep your service account JSON file secure and never commit it to version control
- Use environment variables or secure credential management in production
- The script only requests read-only access to Google Drive
- Consider using the `--verbose` flag only when debugging, as it may expose sensitive information

## Script Execution Order

For new installations or when upgrading existing databases, follow this order:

1. **Schema Update**: `ruby scripts/update_schema.rb`
2. **File Hash Population**: `ruby scripts/populate_file_hashes.rb`
3. **Duplicate Relationship Population**: `ruby scripts/populate_duplicate_relationships.rb`
4. **Validation**: `ruby scripts/production_validation.rb`

## Testing and Diagnostics

For troubleshooting and testing:

1. **Google Authentication**: `ruby scripts/test_google_auth.rb`
2. **Discover Command Issues**: `ruby scripts/test_discover_hang.rb <gdrive-url>`
3. **Duplicate Detection**: `ruby scripts/test_duplicate_detection.rb`
4. **CLI Integration**: `ruby scripts/test_cli_integration.rb`

## API Integration

For Humata API operations:

1. **PDF Retrieval**: `ruby scripts/humata_get_pdf.rb <pdf_id>`
2. **File Upload**: `ruby scripts/humata_upload.rb --url <url> --folder-id <id>`

## Environment Variables

The following environment variables are required for various scripts:

- `GOOGLE_APPLICATION_CREDENTIALS`: Path to Google service account JSON file
- `HUMATA_API_KEY`: Humata API authentication key

## Dependencies

Most scripts require:
- Ruby 2.7+ with bundler
- SQLite3 gem for database operations
- Google API client gems for Google Drive integration
- Net::HTTP for Humata API calls

Install dependencies with:
```bash
bundle install
``` 