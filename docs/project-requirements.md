# Humata.ai Google Drive Import Project - Requirements Document

## Project Overview

A system that integrates with Humata.ai's API to automatically import and process publicly accessible files from Google Drive, enabling document analysis and knowledge extraction capabilities.

## Objectives

### Primary Goals
- Seamlessly import publicly accessible Google Drive files into Humata.ai
- Track each individual file through the complete upload and processing pipeline
- Automate the document processing pipeline
- Provide a reliable and scalable solution for bulk document ingestion

### Success Metrics
- Successfully import files from Google Drive URLs
- Process documents through Humata.ai API with minimal failures
- Handle rate limiting and error scenarios gracefully

## Functional Requirements

### Core Features
1. **Google Drive Integration**
   - Accept Google Drive folder URLs as input
   - Crawl the Google Drive folder to determine the public links of each file
   - Validate file accessibility (public permissions)
   - Support common document formats (PDF, DOC, DOCX, TXT, etc.)
   - Handle both individual files and folder structures

2. **Humata.ai Integration**
   - Authenticate with Humata.ai API
   - Upload documents to Humata.ai
   - Monitor processing status
   - Retrieve processed results

3. **Tracking & Validation**
   - Track all files discovered in Google Drive folders
   - Validate that each file is successfully imported to Humata.ai
   - Monitor processing status for each imported file
   - Maintain comprehensive import/processing status records
   - Identify and report any missing or failed imports
   - Retry mechanisms for failed operations
   - Rate limit handling for both APIs

## Technical Requirements

### Technology Stack
- **Language**: Ruby (chosen based on team experience and research)
- **APIs**: 
  - Google Drive API v3 (using Service Account authentication)
  - Humata.ai REST API
- **Authentication**: 
  - Service Account for Google Drive API (automated, no user interaction)
  - Environment variables for API credentials
- **Libraries**:
  - `google-api-client` gem (official Google library for Drive API)
- **Logging**: Structured logging with different levels

### Dependencies
- `google-api-client` gem (official Google Drive API library)
- Standard Ruby HTTP library (for Humata.ai API calls)
- `optparse` (built-in Ruby library for CLI argument parsing)
- Configuration management for credentials
- Error handling framework
- Data tracking/persistence for validation

## API Integration Details

### Google Drive API
- **Authentication**: Service Account (chosen for automation-friendly approach)
- **Permissions**: Read access to publicly shared files
- **Rate Limits**: 100 requests/100 seconds/user (sufficient for our needs)
- **File Discovery**: Support for file IDs and folder traversal using `files.list` API
- **Library**: `google-api-client` gem

### Humata.ai API
- **Authentication**: API key based (environment variable)
- **File Import**: Direct URL-based import (no local file upload)
- **Processing**: Async processing with status polling
- **Rate Limits**: [RESEARCH REQUIRED]
- **Capabilities**: [RESEARCH REQUIRED - import methods, status tracking, validation endpoints]

## User Stories

### As a User
1. **Single File Import**: "I want to provide a public Google Drive file URL and have it imported into Humata.ai"
2. **Folder Import**: "I want to import all documents from a public Google Drive folder"
3. **Batch Processing**: "I want to import multiple files/folders in one operation"
4. **Individual File Tracking**: "I want to see the status of each individual file as it progresses through discovery, import, and processing"
5. **Status Monitoring**: "I want to see the progress of my import operations"
6. **Error Recovery**: "I want failed imports to be retried automatically"

### As a Developer
1. **Configuration**: "I want to easily configure settings using command-line switches (except for passwords)"
2. **Monitoring**: "I want comprehensive logs to debug issues"
3. **Extensibility**: "I want to easily add support for new features"

## Architecture Overview

```
[Google Drive Folder URLs] 
    ↓
[Folder Crawling & File Discovery]
    ↓
[Public File URL Extraction]
    ↓
[Direct Humata.ai URL Import]
    ↓
[Import Tracking & Status Monitoring]
    ↓
[Validation & Gap Analysis]
    ↓
[Results Reporting]
```

## Data Flow

1. **Input**: User provides Google Drive URL(s)
2. **Discovery**: System identifies accessible files
3. **Import**: File URLs are sent directly to Humata.ai API
4. **Track**: All import requests are recorded
5. **Monitor**: Processing status is tracked for each file
6. **Validate**: Verify all files were successfully processed
7. **Report**: Results and any missing/failed files are reported

## Security Considerations

### Authentication
- Secure storage of API credentials
- Use of service accounts for Google Drive access
- Proper token management and refresh

### Data Handling
- No local file storage or caching
- Only process publicly accessible files
- Minimal persistent data (tracking/validation records only)
- Respect for file access permissions

### Privacy
- Only process publicly accessible files
- No caching of document contents
- Compliance with both platforms' terms of service

## Configuration Requirements

### Environment Variables (Secrets Only)
- `GOOGLE_DRIVE_API_KEY` or service account credentials
- `HUMATA_API_KEY`

### CLI Switches (Non-Secret Configuration)
- `--log-level` / `-l`: Set logging verbosity (debug, info, warn, error)
- `--batch-size` / `-b`: Number of files to process concurrently
- `--max-retries` / `-r`: Maximum retry attempts for failed operations
- `--dry-run` / `-n`: Preview operations without executing
- `--verbose` / `-v`: Enable verbose output
- `--quiet` / `-q`: Suppress non-essential output

### Runtime Configuration
- Retry policies
- Rate limiting parameters
- Concurrent operation limits

### CLI Design Requirements
- All configuration options (except passwords/secrets) should be available as command-line switches
- Passwords and API keys should only be provided via environment variables
- Support for both short (-v) and long (--verbose) switch formats
- Clear help documentation for all available switches

## Future Considerations

### Potential Enhancements
- Support for password-protected files
- Integration with other cloud storage providers
- Webhook notifications for completion
- Web interface for easier operation
- Database for tracking import history
- Advanced error recovery mechanisms

### Scalability
- Support for large-scale batch operations
- Distributed processing capabilities
- Queue-based architecture for high volume

## Research Results & Remaining Questions

### ✅ Major Breakthrough - Complete API Documentation Found!

**Source**: [Humata.ai API Documentation](https://docs.humata.ai/guides/)

1. **✅ OpenAPI Specifications**: Complete technical specs with validation tools available
2. **✅ Full Endpoint Documentation**: All required endpoints (Import, Status, Query) documented
3. **❌ CORRECTED**: Language choice remains flexible - Python references are only for OpenAPI validation
4. **✅ Professional API**: Includes formal validation and development tools
5. **✅ URL Import**: Confirmed support for URL-based imports
6. **✅ No Local Storage**: Perfect match for project requirements

### ⚠️ Remaining Items to Investigate
1. ✅ **Google Drive Compatibility**: Test if Google Drive URLs work with import API
2. ✅ **Rate Limits**: The Humata API rate limit is 120 requests/minute by default ([source](https://docs.humata.ai/guides/humata-api/faq)). This can be increased by request.
3. ✅ **Bulk Operations**: The Humata API does not support bulk operations; files must be imported individually.
4. **Status Polling**: Study tracking mechanisms in API specs

### 🔄 Secondary Questions
1. ✅ Programming Language: Ruby (chosen based on team experience and research)
2. ✅ Google Drive Authentication: Service Account (chosen for automation-friendly approach)
3. Concurrent Operations: How many parallel operations should we support?
4. ✅ CLI Implementation: OptionParser (Ruby built-in library for CLI switches)

## Next Steps - Updated Based on Research

### ✅ **PHASE 0: API Research - COMPLETE**
1. ✅ Documentation Found: Complete API docs with OpenAPI specs located
2. ✅ Ruby Chosen: Language and libraries selected based on research
3. ✅ Google Drive Research: API calls and authentication method determined

**Next Immediate Steps**:
2. ✅ Study Import Endpoint: Understand "How to Import Document"
3. Setup Development Environment: Ruby environment with `google-api-client` gem
4. Setup Google Cloud Project: Create project, enable Drive API, create Service Account (**PENDING**)
5. ✅ Obtain Humata API Credentials
6. ✅ Test Google Drive Compatibility: Verify URL import works

### 📋 **PHASE 1: Proof of Concept (AFTER API CONFIRMATION)**
1. **Google Drive Integration**:
   - Set up Google Drive API access
   - Test folder crawling and file discovery
   - Extract public URLs from discovered files

2. **Humata Integration**:
   - Implement single file import to Humata
   - Build status tracking system
   - Create validation and error handling

### 🔧 **PHASE 2: Full Implementation (CONDITIONAL)**
- Build complete folder crawling system
- Implement batch import with comprehensive tracking
- Add CLI interface with proper switches
- Create robust error handling and retry mechanisms
- Implement validation and gap analysis reporting

**⚠️ Note**: Phases 1 & 2 are contingent on successful completion of Phase 0 API research.

## 📋 Current Status

**Research Phase**: ✅ COMPLETED - API documentation located successfully!  
**Next Critical Step**: 🔍 Access OpenAPI specifications for technical details  
**Major Breakthrough**: ✅ Complete API documentation found at https://docs.humata.ai/guides/  
**Status**: 🗡️ Ready to proceed with development setup  

**See also**: `docs/api-research-findings.md` for detailed research results

---

*This document is a living specification that will be updated as the project evolves.*