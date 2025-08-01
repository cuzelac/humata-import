# Google Drive Folder Crawling Research

## Overview

Research on Google Drive API v3 capabilities and available libraries for crawling public folders and extracting file URLs for use with Humata.ai import.

## Required API Calls

### 1. **Files.list** - Primary File Discovery
- **Endpoint**: `GET https://www.googleapis.com/drive/v3/files`
- **Purpose**: List files in a folder or search for files
- **Key Parameters**:
  - `q`: Query parameter for filtering (e.g., `'parents in "folder_id"'`)
  - `pageSize`: Number of results per page (max 1000)
  - `pageToken`: For pagination
  - `fields`: Specify which file metadata to return
  - `orderBy`: Sort results
- **Returns**: File metadata including IDs, names, MIME types, download URLs

### 2. **Files.get** - Individual File Details
- **Endpoint**: `GET https://www.googleapis.com/drive/v3/files/{fileId}`
- **Purpose**: Get detailed metadata for a specific file
- **Key Parameters**:
  - `fields`: Specify metadata fields to return
  - `supportsAllDrives`: Include shared drives
- **Returns**: Complete file metadata including `webContentLink` for direct download

### 3. **Query Patterns for Folder Crawling**
- **List files in folder**: `q="'FOLDER_ID' in parents"`
- **Recursive folder discovery**: `q="'FOLDER_ID' in parents and mimeType='application/vnd.google-apps.folder'"`
- **Filter file types**: `q="'FOLDER_ID' in parents and mimeType!='application/vnd.google-apps.folder'"`
- **Public files only**: Requires proper authentication and permissions

## Authentication Requirements

### Service Account (Recommended for Automation)
- **Pros**: No user interaction, suitable for server applications
- **Cons**: Requires service account setup, may need domain-wide delegation for some scenarios
- **Setup**: Create service account in Google Cloud Console, download JSON credentials

### OAuth 2.0 (Alternative)
- **Pros**: Can access user's personal Drive
- **Cons**: Requires user interaction for initial authorization
- **Use Case**: When accessing user's own files vs. public shared folders

## Available Libraries

### Ruby Libraries

#### 1. **google-api-client** (Official Google Library)
- **Gem**: `google-api-client`
- **Status**: Official, actively maintained
- **Features**:
  - Full Drive API v3 support
  - Built-in authentication handling
  - Pagination support
  - Retry mechanisms
- **Example Usage**:
  ```ruby
  require 'google/apis/drive_v3'
  
  service = Google::Apis::DriveV3::DriveService.new
  service.authorization = credentials
  
  # List files in folder
  response = service.list_files(
    q: "'#{folder_id}' in parents",
    fields: 'files(id,name,mimeType,webContentLink)'
  )
  ```

#### 2. **google-drive-ruby** (High-level Wrapper)
- **Gem**: `google_drive`
- **Status**: Third-party, well-maintained
- **Features**:
  - Simplified API for common operations
  - Built-in authentication helpers
  - File system-like interface
- **Pros**: Easier to use for basic operations
- **Cons**: May not expose all API features

### Python Libraries

#### 1. **google-api-python-client** (Official Google Library)
- **Package**: `google-api-python-client`
- **Status**: Official, actively maintained
- **Features**:
  - Complete Drive API v3 support
  - Authentication integration with `google-auth`
  - Built-in retry and pagination
- **Example Usage**:
  ```python
  from googleapiclient.discovery import build
  
  service = build('drive', 'v3', credentials=creds)
  
  # List files
  results = service.files().list(
      q=f"'{folder_id}' in parents",
      fields="files(id,name,mimeType,webContentLink)"
  ).execute()
  ```

#### 2. **getfilelistpy** (Specialized Folder Crawling)
- **Package**: `getfilelistpy`
- **Status**: Third-party, specialized for folder traversal
- **Features**:
  - Recursive folder structure retrieval
  - Built-in folder tree mapping
  - Support for both API key and OAuth
- **Pros**: Purpose-built for folder crawling
- **Cons**: Less flexible than official client

#### 3. **GoogleDrivePythonLibrary** (High-level Wrapper)
- **Status**: Third-party, smaller project
- **Features**:
  - File system-like interface
  - String path support (e.g., 'path/to/folder/file.txt')
  - High-level operations
- **Pros**: Very intuitive API
- **Cons**: Smaller community, may have limitations

## Implementation Strategy

### Recommended Approach: Official Libraries
**For Ruby**: Use `google-api-client` gem
**For Python**: Use `google-api-python-client` package

**Reasons**:
1. **Official support** and regular updates
2. **Complete API coverage** - access to all Drive API features
3. **Built-in authentication** handling
4. **Robust error handling** and retry mechanisms
5. **Pagination support** for large folders
6. **Active community** and documentation

### Folder Crawling Algorithm
1. **Start with folder ID** from Google Drive URL
2. **List files in folder** using `files.list` with `parents` query
3. **Separate folders from files**:
   - Folders: `mimeType='application/vnd.google-apps.folder'`
   - Files: All other MIME types
4. **Extract download URLs** from file metadata (`webContentLink`)
5. **Recursively process subfolders** if needed
6. **Handle pagination** for large folders (>1000 items)

### Key Considerations
- **Rate Limits**: Google Drive API has quotas (100 requests/100 seconds/user by default)
- **Public Access**: Ensure folders are publicly accessible or use appropriate authentication
- **File Types**: Filter for supported file types (PDF, DOC, etc.)
- **URL Extraction**: Use `webContentLink` for direct download URLs
- **Error Handling**: Handle network errors, API limits, and permission issues

## Next Steps
1. **Choose language** (Ruby vs Python) based on team preference
2. **Set up Google Cloud project** and enable Drive API
3. **Create service account** or configure OAuth
4. **Test basic folder listing** with a public Google Drive folder
5. **Implement recursive crawling** algorithm
6. **Test URL extraction** and verify compatibility with Humata API

## References
- [Google Drive API v3 Documentation](https://developers.google.com/drive/api/v3/reference/)
- [Files.list Method](https://developers.google.com/drive/api/v3/reference/files/list)
- [Search for Files & Folders Guide](https://developers.google.com/drive/api/guides/search-files)
- [Ruby google-api-client Documentation](https://googleapis.dev/ruby/google-api-client/latest/)
- [Python google-api-python-client Documentation](https://googleapis.github.io/google-api-python-client/)