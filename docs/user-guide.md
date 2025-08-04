# Humata.ai Google Drive Import Tool - User Guide

## Overview

The Humata.ai Google Drive Import Tool is a command-line utility that helps you import files from Google Drive folders into your Humata.ai workspace. The tool supports:

- Recursive folder crawling
- File type filtering
- Batch processing
- Progress tracking
- Status monitoring
- Detailed reporting

## Prerequisites

1. **Google Drive Service Account**
   - Create a Google Cloud project
   - Enable the Google Drive API
   - Create a service account
   - Download the service account key file
   - Share target folders with the service account email

2. **Humata.ai API Key**
   - Obtain your API key from Humata.ai
   - Set it as an environment variable:
     ```bash
     export HUMATA_API_KEY='your-api-key'
     ```

## Installation

```bash
gem install humata-import
```

## Basic Usage

The tool provides several commands that can be run independently or as a complete workflow:

### Complete Workflow

To process a Google Drive folder from start to finish:

```bash
humata-import run "https://drive.google.com/drive/folders/your-folder-id" \
  --folder-id "your-humata-folder-id" \
  --database ./import_session.db \
  --verbose
```

This will:
1. Discover files in the Google Drive folder
2. Upload them to Humata.ai
3. Monitor the processing status
4. Generate a final report

### Individual Commands

#### 1. Discover Files

```bash
humata-import discover "https://drive.google.com/drive/folders/your-folder-id" \
  --file-types pdf,doc,docx,txt \
  --recursive \
  --database ./import_session.db
```

Options:
- `--recursive` (default: true) - Crawl subfolders
- `--no-recursive` - Only process the root folder
- `--file-types` - Comma-separated list of file extensions
- `--max-files N` - Limit the number of files to discover

#### 2. Upload Files

```bash
humata-import upload \
  --folder-id "your-humata-folder-id" \
  --batch-size 10 \
  --database ./import_session.db
```

Options:
- `--batch-size N` (default: 10) - Number of files to process in parallel
- `--max-retries N` (default: 3) - Maximum retry attempts per file
- `--retry-delay N` (default: 5) - Seconds to wait between retries

#### 3. Verify Processing

```bash
humata-import verify \
  --poll-interval 10 \
  --timeout 1800 \
  --database ./import_session.db
```

Options:
- `--poll-interval N` (default: 10) - Seconds between status checks
- `--timeout N` (default: 1800) - Total timeout in seconds
- `--batch-size N` (default: 10) - Files to check in parallel

#### 4. Check Status

```bash
humata-import status \
  --format text \
  --database ./import_session.db
```

Options:
- `--format FORMAT` (text/json/csv) - Output format
- `--output FILE` - Write to file instead of stdout
- `--filter STATUS` - Filter by status (completed/failed/pending/processing)

## Common Options

These options are available for all commands:

- `--database PATH` - SQLite database file for session state
- `--verbose` - Enable detailed logging
- `-h, --help` - Show command help

## Best Practices

1. **Use a Dedicated Database File**
   - Create a new database file for each import session
   - Keep database files for reference and resumability

2. **Monitor Progress**
   - Use the `status` command to check progress
   - Enable `--verbose` for detailed logging
   - Export reports in different formats for analysis

3. **Handle Interruptions**
   - The tool is designed to be resumable
   - If interrupted, just run the same command again
   - Use the same database file to continue from where you left off

4. **Large Imports**
   - Start with a small subset to test settings
   - Use `--max-files` to limit initial imports
   - Adjust batch sizes based on your rate limits
   - Monitor memory usage with large folders

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Verify Google Drive service account setup
   - Check if HUMATA_API_KEY is set correctly
   - Ensure folders are shared with service account

2. **Rate Limiting**
   - Reduce batch sizes
   - Increase retry delays
   - Contact Humata.ai for rate limit increases

3. **Processing Failures**
   - Check file formats and sizes
   - Verify file accessibility
   - Review error messages in status reports

4. **Database Issues**
   - Ensure write permissions on database file
   - Check disk space
   - Back up database files before retrying

### Error Messages

Common error messages and their solutions:

1. "Invalid Google Drive folder URL"
   - Ensure the URL is from the folder's sharing link
   - Try using just the folder ID

2. "API request failed"
   - Check API key and permissions
   - Verify network connectivity
   - Look for rate limiting messages

3. "Database is locked"
   - Close other processes using the database
   - Check file permissions
   - Try a new database file

## Support

For additional help:

1. Check the [GitHub repository](https://github.com/yourusername/humata-import) for:
   - Latest updates
   - Known issues
   - Feature requests

2. Contact Humata.ai support for:
   - API issues
   - Rate limit increases
   - Account-specific questions