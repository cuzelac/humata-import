# Humata.ai Google Drive Import Tool

A Ruby CLI tool to import publicly accessible files into Humata.ai using the Humata API. Includes utilities for uploading a file by URL and checking PDF status.

## Overview

This tool provides scripts to:
- Upload a file to Humata.ai by URL (`humata_upload.rb`)
- Retrieve PDF status/details from Humata.ai (`humata_get_pdf.rb`)

## Prerequisites

- Ruby 2.7+ (tested with Ruby 3.x)
- Google Cloud Project with Drive API enabled (for future folder crawling)
- Humata.ai API key

## Installation

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd humata-import
   ```

2. **Install dependencies:**
   ```bash
   gem install google-api-client
   ```

3. **Set up Google Cloud Service Account** (see detailed steps below)

4. **Configure environment variables:**
   ```bash
   export HUMATA_API_KEY="your_humata_api_key"
   export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
   ```

## Google Cloud Service Account Setup

### Step 1: Create Google Cloud Project
1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Click **"Select a project"** → **"New Project"**
3. Enter project name (e.g., "Humata Drive Importer")
4. Click **"Create"**
5. Wait for project creation and select your new project

### Step 2: Enable Google Drive API
1. In the Google Cloud Console, go to **"APIs & Services"** → **"Library"**
2. Search for **"Google Drive API"**
3. Click on **"Google Drive API"**
4. Click **"Enable"**
5. Wait for the API to be enabled

### Step 3: Create Service Account
1. Go to **"APIs & Services"** → **"Credentials"**
2. Click **"Create Credentials"** → **"Service Account"**
3. Fill in the service account details
4. Click **"Create and Continue"**
5. Skip the optional steps (Grant access & Grant users access)
6. Click **"Done"**

### Step 4: Create and Download Service Account Key
1. In the **"Credentials"** page, find your newly created service account
2. Click on the service account name
3. Go to the **"Keys"** tab
4. Click **"Add Key"** → **"Create new key"**
5. Select **"JSON"** format
6. Click **"Create"**
7. The JSON key file will download automatically
8. Move this file to a secure location and rename it (e.g., `google-service-account.json`)

### Step 5: Secure the Credentials File
```bash
mv ~/Downloads/your-project-*.json ./google-service-account.json
chmod 600 google-service-account.json
echo "google-service-account.json" >> .gitignore
```

### Step 6: Set Environment Variable
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/full/path/to/your/google-service-account.json"
```

## Usage

### Upload a File to Humata by URL

```bash
ruby scripts/humata_upload.rb --url <file_url> --folder-id <humata_folder_id> [--verbose|-v]
```

- `--url <file_url>`: The public file URL to import (required)
- `--folder-id <humata_folder_id>`: The Humata folder UUID (required)
- `--verbose` or `-v`: Output HTTP status code and response body (optional)

**Example:**
```bash
ruby scripts/humata_upload.rb --url "https://example.com/file.pdf" --folder-id "your-humata-folder-uuid"
```

### Get PDF Status/Details from Humata

```bash
ruby scripts/humata_get_pdf.rb <pdf_id> [--verbose|-v]
```

- `<pdf_id>`: The Humata PDF ID (required)
- `--verbose` or `-v`: Output HTTP status code and response body (optional)

**Example:**
```bash
ruby scripts/humata_get_pdf.rb 22a6c4b2-caf3-4f8e-8217-6525b0afc3bd
```

## Environment Variables

```bash
export HUMATA_API_KEY="your_humata_api_key"
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"
```

## Troubleshooting

**"Invalid credentials" error:**
- Verify `HUMATA_API_KEY` and `GOOGLE_APPLICATION_CREDENTIALS` are set and correct

**"Permission denied" error:**
- Ensure your Humata API key is valid and has access

## Development

Scripts are located in the `scripts/` directory:
- `humata_upload.rb`: Upload a file by URL to Humata
- `humata_get_pdf.rb`: Get PDF status/details from Humata

## License

[License information]

## Support

For issues related to:
- **Humata API**: Contact Humata.ai support
- **Google Drive API**: Check Google Cloud Console quotas and logs
- **This tool**: Open an issue in this repository

---

**Security Note**: Never commit API keys or service account JSON files to version control. Always use environment variables for sensitive credentials.