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