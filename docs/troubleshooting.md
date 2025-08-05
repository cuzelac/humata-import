# Humata.ai Google Drive Import Tool - Troubleshooting Guide

## Common Issues and Solutions

### Authentication and Access

#### Google Drive Authentication

**Issue**: Service account authentication fails
```
Google Drive API error: Not authorized
```

**Solutions**:
1. Verify service account setup:
   - Check if Google Drive API is enabled
   - Ensure service account key file is valid
   - Confirm service account has necessary permissions
2. Share target folders:
   - Share folders with service account email
   - Verify sharing settings allow file listing

#### Humata API Authentication

**Issue**: API key validation fails
```
API request failed (401): Invalid API key
```

**Solutions**:
1. Check environment variable:
   ```bash
   echo $HUMATA_API_KEY
   ```
2. Reset API key:
   - Generate new key in Humata dashboard
   - Update environment variable
3. Verify API key format and length

### Rate Limiting

#### Google Drive API

**Issue**: Rate limit exceeded
```
Google Drive API error: Rate limit exceeded
```

**Solutions**:
1. Reduce batch size:
   ```bash
   humata-import discover --max-files 100
   ```
2. Add delays between requests:
   ```bash
   humata-import upload --batch-size 5 --retry-delay 10
   ```

#### Humata API

**Issue**: Too many requests
```
API request failed (429): Rate limit exceeded
```

**Solutions**:
1. Adjust batch processing:
   ```bash
   humata-import upload --batch-size 5
   ```
2. Increase retry delays:
   ```bash
   humata-import upload --retry-delay 10
   ```
3. Contact Humata support for rate limit increase

### File Processing

#### Invalid Files

**Issue**: File format not supported
```
API request failed (400): Invalid file format
```

**Solutions**:
1. Check file size limits
2. Verify file accessibility
3. Contact Humata.ai support for unsupported file types

#### Server Errors (500)

**Issue**: Internal server error
```
API request failed (500): Internal server error
```

**Common Causes**:
1. **Invalid Google Drive URLs**: Some Google Drive URL formats may cause server errors
2. **Large file URLs**: Very long URLs or URLs with special characters
3. **Invalid folder IDs**: Non-existent or malformed folder IDs
4. **Rate limiting**: Too many requests in a short time period
5. **Server maintenance**: Humata API may be temporarily unavailable

**Solutions**:
1. **Use direct file view URLs**: Convert Google Drive URLs to direct file view format
   ```bash
   # Instead of: https://drive.google.com/file/d/ID/view?usp=sharing
   # Use: https://drive.google.com/file/d/ID/view?usp=drive_link
   ```
2. **Reduce batch size**: Process fewer files at once
   ```bash
   humata-import upload --batch-size 3 --retry-delay 10
   ```
3. **Verify folder ID**: Ensure the Humata folder ID exists and is correct
4. **Wait and retry**: Server errors are often temporary
5. **Contact support**: If 500 errors persist, contact Humata.ai support

#### Processing Timeouts

**Issue**: Processing takes too long
```
Timeout reached after 1800 seconds
```

**Solutions**:
1. Increase timeout:
   ```bash
   humata-import verify --timeout 3600
   ```
2. Check file sizes
3. Monitor processing status separately

### Database Issues

#### Database Locking

**Issue**: Database is locked
```
SQLite3::BusyException: database is locked
```

**Solutions**:
1. Close other processes using the database
2. Check file permissions:
   ```bash
   chmod 644 your_database.db
   ```
3. Use a new database file

#### Write Permission

**Issue**: Cannot write to database
```
SQLite3::ReadOnlyException: attempt to write a readonly database
```

**Solutions**:
1. Check file permissions:
   ```bash
   ls -l your_database.db
   chmod 644 your_database.db
   ```
2. Verify directory permissions
3. Use a different location

### Network Issues

#### Connection Timeouts

**Issue**: Network requests fail
```
HTTP request failed: execution expired
```

**Solutions**:
1. Check network connectivity
2. Increase retry attempts:
   ```bash
   humata-import upload --max-retries 5
   ```
3. Verify proxy settings

#### SSL/TLS Errors

**Issue**: SSL certificate validation fails
```
SSL_connect returned=1 errno=0 state=error: certificate verify failed
```

**Solutions**:
1. Update SSL certificates
2. Check system time
3. Verify SSL/TLS configuration

## Recovery Strategies

### Interrupted Operations

If an operation is interrupted, you can resume using the same database:

1. Check current status:
   ```bash
   humata-import status --database your_database.db
   ```

2. Resume appropriate phase:
   ```bash
   # For upload phase
   humata-import upload --folder-id your-folder-id --database your_database.db

   # For verification phase
   humata-import verify --database your_database.db
   ```

### Data Recovery

If database corruption occurs:

1. Back up the current database:
   ```bash
   cp your_database.db your_database.backup.db
   ```

2. Check database integrity:
   ```bash
   sqlite3 your_database.db "PRAGMA integrity_check;"
   ```

3. Export data if possible:
   ```bash
   humata-import status --format csv --output export.csv --database your_database.db
   ```

### Clean Start

If recovery isn't possible:

1. Archive the problematic database:
   ```bash
   mv your_database.db your_database.$(date +%Y%m%d).db
   ```

2. Start fresh:
   ```bash
   humata-import run \
     "https://drive.google.com/drive/folders/your-folder-id" \
     --folder-id "your-humata-folder-id" \
     --database new_session.db
   ```

## Performance Optimization

### Memory Usage

If experiencing high memory usage:

1. Reduce batch sizes:
   ```bash
   humata-import upload --batch-size 5
   humata-import verify --batch-size 5
   ```

2. Process in chunks:
   ```bash
   humata-import discover --max-files 100
   ```

### Processing Speed

To optimize processing speed:

1. Adjust concurrent operations:
   ```bash
   humata-import upload --batch-size 10
   ```

2. Balance rate limits:
   ```bash
   humata-import verify --poll-interval 5
   ```

## Monitoring and Debugging

### Verbose Logging

Enable detailed logging for troubleshooting:

```bash
humata-import run ... --verbose
```

### Status Reports

Generate detailed reports:

```bash
# Text report
humata-import status --format text --output status.txt

# JSON for parsing
humata-import status --format json --output status.json

# CSV for analysis
humata-import status --format csv --output status.csv
```

### Error Analysis

Filter status by error state:

```bash
humata-import status --filter failed
```

## Getting Help

If issues persist:

1. Collect information:
   - Command output with `--verbose`
   - Status report in JSON format
   - Database file (if possible)
   - Error messages and stack traces

2. Check documentation:
   - User guide
   - API documentation
   - GitHub issues

3. Contact support:
   - Provide collected information
   - Describe steps to reproduce
   - Include environment details