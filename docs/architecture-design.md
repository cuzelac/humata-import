# Humata.ai Google Drive Import Tool - Architecture Design

## Project Overview

A Ruby CLI tool that imports publicly accessible files from Google Drive folders into Humata.ai using a 3-phase workflow with SQLite-based state management.

## Core Architecture Decisions

### 1. **Single CLI with Subcommands**
- **Main CLI**: `humata-import <command> [options]`
- **Modular Design**: Each phase implemented as a separate subcommand
- **Shared State**: All commands operate on the same SQLite database
- **Flexibility**: Can run phases independently or in sequence

### 2. **SQLite as Data Store**
- **Single File Database**: Each database file represents one import session
- **ACID Transactions**: Guaranteed data integrity during operations
- **Concurrent Reads**: Multiple processes can monitor progress
- **Efficient Updates**: Only modified records are updated
- **Indexing**: Fast lookups and filtering capabilities
- **Scalability**: Handles thousands of files efficiently

### 3. **3-Phase Workflow**

```
Phase 1: DISCOVER → Phase 2: UPLOAD → Phase 3: VERIFY
     ↓                    ↓                 ↓
  SQLite DB          SQLite DB         SQLite DB
```

## CLI Interface Design

### Commands Structure
```bash
humata-import discover <gdrive-url> [options]    # Phase 1: Extract URLs from GDrive
humata-import upload [options]                   # Phase 2: Upload discovered URLs  
humata-import verify [options]                   # Phase 3: Verify processing status
humata-import run <gdrive-url> [options]         # All phases in sequence
humata-import status [options]                   # Show current session status
```

### Global Options
- `--database <path>`: SQLite database file path (default: `./import_session.db`)
- `--verbose, -v`: Enable verbose output
- `--quiet, -q`: Suppress non-essential output
- `--help, -h`: Show help information

### Phase-Specific Options

#### Discover Command
```bash
humata-import discover <gdrive-url> [options]
  --recursive              # Crawl subfolders (default: true)
  --file-types <types>     # Filter by file types (default: pdf,doc,docx,txt)
  --max-files <n>          # Limit number of files to discover
```

#### Upload Command  
```bash
humata-import upload [options]
  --folder-id <uuid>       # Humata folder UUID (required)
  --batch-size <n>         # Concurrent uploads (default: 5)
```

#### Verify Command
```bash
humata-import verify [options]
  --poll-interval <sec>    # Status check interval (default: 30s)
  --timeout <duration>     # Max wait time (default: 1h)
```

#### Run Command (All Phases)
```bash
humata-import run <gdrive-url> [options]
  --folder-id <uuid>       # Humata folder UUID (required)
  --batch-size <n>         # Concurrent uploads (default: 5)
  --poll-interval <sec>    # Status check interval (default: 30s)
  --timeout <duration>     # Max wait time (default: 1h)
```

## Project Structure

```
├── bin/
│   └── humata-import                           # Main CLI entry point
├── lib/
│   ├── humata_import/
│   │   ├── cli.rb                             # CLI argument parsing & routing
│   │   ├── database.rb                        # SQLite connection management
│   │   ├── models/                            # Data models
│   │   │   └── file_record.rb                 # Individual file tracking
│   │   ├── commands/                          # Phase implementations
│   │   │   ├── base.rb                        # Shared command functionality
│   │   │   ├── discover.rb                    # Phase 1: GDrive crawling
│   │   │   ├── upload.rb                      # Phase 2: Humata upload
│   │   │   ├── verify.rb                      # Phase 3: Status verification
│   │   │   ├── run.rb                         # All phases combined
│   │   │   └── status.rb                      # Status reporting
│   │   ├── clients/                           # API wrappers
│   │   │   ├── gdrive_client.rb               # Google Drive API wrapper
│   │   │   └── humata_client.rb               # Humata API wrapper
│   │   ├── utils/                             # Utilities
│   │   │   ├── logger.rb                      # Structured logging
│   │   │   ├── rate_limiter.rb                # Rate limiting
│   │   │   └── retry_handler.rb               # Retry logic
│   │   └── version.rb                         # Version information
│   └── humata_import.rb                       # Main module
├── scripts/                                   # Individual utility scripts
│   ├── humata_upload.rb                       # Single file upload
│   └── humata_get_pdf.rb                      # Status checker
├── docs/                                      # Documentation
├── spec/                                      # Tests
└── data/                                      # Session databases (gitignored)
    └── .gitkeep
```

## Database Schema

### SQLite Tables

```sql
-- Individual file records (only table needed)
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
  humata_response TEXT,
  discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  uploaded_at DATETIME,
  completed_at DATETIME,
  last_checked_at DATETIME
);

-- Indexes for performance
CREATE INDEX idx_files_status ON file_records(upload_status);
CREATE INDEX idx_files_gdrive_id ON file_records(gdrive_id);
CREATE INDEX idx_files_humata_id ON file_records(humata_id);
```

### Status Values

**File Upload Status:**
- `pending` - Discovered, not yet uploaded
- `uploading` - Upload in progress
- `uploaded` - Successfully uploaded to Humata
- `failed` - Upload failed (after retries)
- `skipped` - Skipped (duplicate, unsupported type, etc.)

**File Processing Status:**
- `null` - Not yet uploaded
- `processing` - Being processed by Humata
- `completed` - Processing complete
- `failed` - Processing failed

## Data Flow & State Management

### Phase 1: Discover (Idempotent)
1. Use Google Drive API to crawl folder
2. Insert discovered files into `file_records` table (skip duplicates)
3. **Idempotent**: Re-running will discover any new files, skip existing ones

### Phase 2: Upload (Idempotent)
1. Query pending files from database
2. Upload files to Humata API in batches
3. Record full Humata API response in `humata_response` field
4. Update file records with Humata IDs, folder ID, and status
5. **Idempotent**: Re-running will only upload files not yet uploaded

### Phase 3: Verify (Idempotent)
1. Query uploaded files from database
2. Poll Humata API for processing status
3. Update file processing status
4. Continue until all files complete or timeout
5. **Idempotent**: Re-running will check status of all uploaded files

### State Persistence Benefits
- **Resumability**: Restart any phase after interruption
- **Monitoring**: Real-time progress tracking
- **Debugging**: Complete audit trail with full API responses
- **Reporting**: Detailed success/failure analysis
- **Idempotency**: Each phase can be safely re-run

## API Integration

### Google Drive API v3
- **Authentication**: Service Account (JSON key file)
- **Operations**: `files.list` for folder crawling
- **Rate Limits**: 100 requests/100 seconds/user
- **Library**: `google-api-client` gem

### Humata.ai API
- **Authentication**: API key (environment variable)
- **Import Endpoint**: `POST /api/v2/import-url`
- **Status Endpoint**: `GET /api/v1/pdf/{id}`
- **Rate Limits**: 120 requests/minute (can be increased)

## Environment Variables

```bash
# Required
export HUMATA_API_KEY="your_humata_api_key"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# Optional
export HUMATA_IMPORT_DB_PATH="./custom_import_sessions.db"
export HUMATA_IMPORT_LOG_LEVEL="info"
```

## Error Handling & Resilience

### Idempotent Design
- **No built-in retries**: Each phase is idempotent - simply re-run to fix failures
- **State preservation**: All errors and responses stored in database
- **Clean recovery**: Re-running a phase will pick up where it left off

### Error Categories
- **Transient**: Network timeouts, rate limits → Re-run phase
- **Permanent**: Invalid URLs, access denied → Logged and skipped
- **Unknown**: Unexpected errors → Logged for investigation

### Recovery Mechanisms
- **Phase re-execution**: Simply re-run the failed phase
- **Full API responses**: Complete error details stored for debugging
- **Selective processing**: Only unprocessed files are handled on re-run

## Performance Characteristics

### Expected Performance
- **Discovery**: ~100 files/second (limited by Google Drive API)
- **Upload**: ~5-10 files/second (limited by Humata API rate limits)
- **Verification**: ~120 status checks/minute (Humata API limit)
- **Database**: Handles 10,000+ files efficiently

### Scalability Limits
- **Single process**: Limited by API rate limits, not database
- **Database size**: SQLite handles millions of records
- **One session per database**: Each import session uses its own database file
- **Memory usage**: Minimal (only active batch in memory)

## Security Considerations

### Credential Management
- **Service Account**: JSON key file for Google Drive
- **API Keys**: Environment variables only
- **File Permissions**: Restrict database file access
- **No Secrets in Code**: All credentials externalized

### Data Privacy
- **Public Files Only**: Only processes publicly accessible files
- **No File Caching**: URLs only, no content storage
- **Minimal Metadata**: Only essential tracking information
- **Audit Trail**: Complete record of all operations



---

## Implementation Priority

### Phase 1: Core Infrastructure
1. ✅ CLI framework with subcommands
2. ✅ SQLite database setup and models
3. ✅ Basic Google Drive API integration
4. ✅ Basic Humata API integration

### Phase 2: Command Implementation
1. 🔄 `discover` command (Google Drive crawling)
2. 🔄 `upload` command (Humata import)
3. 🔄 `verify` command (Status monitoring)
4. 🔄 `run` command (End-to-end workflow)

### Phase 3: Production Features
1. ⏳ Error handling and retry logic
2. ⏳ Rate limiting and throttling
3. ⏳ Comprehensive logging
4. ⏳ Status reporting and monitoring

### Phase 4: Polish & Documentation
1. ⏳ Comprehensive testing
2. ⏳ User documentation
3. ⏳ Performance optimization
4. ⏳ Deployment guides

---

*This architecture design serves as the foundation for all development work on the Humata.ai Google Drive Import Tool. All future AI agent interactions should reference this document for architectural decisions and implementation guidance.*