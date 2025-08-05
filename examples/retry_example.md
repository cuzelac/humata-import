# Retry Functionality Example

This example demonstrates how the retry functionality works when uploads fail.

## Scenario

You have a large batch of files to upload to Humata.ai, but some uploads fail due to temporary API issues or network problems.

## Step 1: Initial Upload (Some Failures)

```bash
# Run initial upload
humata-import upload --folder-id "your-humata-folder-id" --database ./import_session.db
```

**Output:**
```
Found 100 files pending upload.
  New uploads: 100
  Retries: 0

Uploading: document1.pdf (gdrive-123)
Success: document1.pdf (Humata ID: humata-456)

Uploading: document2.pdf (gdrive-124)
WARN: Upload failed for document2.pdf, attempt 1/3: Rate limit exceeded
WARN: Upload failed for document2.pdf, attempt 2/3: Rate limit exceeded
WARN: Upload failed for document2.pdf, attempt 3/3: Rate limit exceeded
ERROR: Upload failed for document2.pdf after 3 attempts: Rate limit exceeded

Summary:
  Uploaded: 95 files
  Failed:   5 files
  Total:    100 files processed
```

## Step 2: Check Failed Uploads

```bash
# View only failed uploads
humata-import status --failed-only --database ./import_session.db
```

**Output:**
```
Import Session Status
====================

Failed Uploads Summary:
  Failed uploads: 5 files ready for retry

Failed Uploads (Ready for Retry):
--------------------------------------------------------------------------------
document2.pdf (gdrive-124)
  Status: failed
  Humata ID: not uploaded
  Import Error: Rate limit exceeded
  Attempts: 3
  Last Attempt: 2023-12-01T14:30:00Z
--------------------------------------------------------------------------------
document7.pdf (gdrive-129)
  Status: failed
  Humata ID: not uploaded
  Import Error: Network timeout
  Attempts: 3
  Last Attempt: 2023-12-01T14:32:15Z
--------------------------------------------------------------------------------
...
```

## Step 3: Retry Failed Uploads

```bash
# Run upload again - automatically retries failed uploads
humata-import upload --folder-id "your-humata-folder-id" --database ./import_session.db
```

**Output:**
```
Found 5 files pending upload.
  New uploads: 0
  Retries: 5

Retrying failed upload: document2.pdf (gdrive-124)
Retry successful: document2.pdf (Humata ID: humata-789)

Retrying failed upload: document7.pdf (gdrive-129)
Retry successful: document7.pdf (Humata ID: humata-790)

Summary:
  Uploaded: 5 files
  Failed:   0 files
  Total:    5 files processed
```

## Step 4: Verify All Uploads Complete

```bash
# Check final status
humata-import status --database ./import_session.db
```

**Output:**
```
Import Session Status
====================

Overall Progress:
  completed: 100 files (100.0%)
  failed: 0 files (0.0%)

Detailed File Status:
--------------------------------------------------------------------------------
document1.pdf (gdrive-123)
  Status: completed
  Humata ID: humata-456
--------------------------------------------------------------------------------
document2.pdf (gdrive-124)
  Status: completed
  Humata ID: humata-789
--------------------------------------------------------------------------------
...
```

## Key Features

1. **Automatic Retry**: Failed uploads are automatically retried on the next upload run
2. **Retry Tracking**: Each retry attempt is tracked with timestamps
3. **Skip Option**: Use `--skip-retries` to only process new uploads
4. **Status Monitoring**: Use `--failed-only` to quickly see what needs retrying
5. **Resilient**: Handles temporary API issues and network problems gracefully

## Configuration Options

```bash
# Configure retry behavior
humata-import upload \
  --folder-id "your-humata-folder-id" \
  --max-retries 5 \
  --retry-delay 10 \
  --skip-retries \
  --database ./import_session.db
```

- `--max-retries N`: Maximum retry attempts per file (default: 3)
- `--retry-delay N`: Seconds to wait between retries (default: 5)
- `--skip-retries`: Skip retrying failed uploads 