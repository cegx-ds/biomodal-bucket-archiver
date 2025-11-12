# Bucket Archiver Cloud Function

This Cloud Function automatically archives Google Cloud Storage buckets older than a specified number of days by changing their storage class to ARCHIVE.

## Features

- Automatically archives buckets matching specific naming patterns (`cegx-run*`, `biomodal-run*`)
- Configurable via JSON files stored in GCS
- Excludes specified buckets from archiving
- Disables Autoclass before archiving
- Transitions buckets from STANDARD to ARCHIVE storage class
- Concurrent blob processing for efficiency (10 workers)
- Comprehensive logging and error handling
- Weekly scheduling via Cloud Scheduler (Mondays at 2 AM UTC)
- Deployed to `prj-platform-tools-prod` project
- Uses service account: `sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com`

## Prerequisites

1. Google Cloud SDK installed and configured
2. Service account with appropriate IAM permissions:
   - Storage Admin on all target projects
   - Cloud Functions Admin
   - Cloud Scheduler Admin
3. Access to `prj-platform-tools-prod` project

## Configuration

Configuration is managed through JSON files that can be stored in multiple locations with a fallback hierarchy:

1. **Primary**: GCS bucket `biomodal-bucket-archiver-config` (loaded at runtime)
2. **Secondary**: Local `config/` directory (used during deployment and as fallback)
3. **Tertiary**: Hardcoded defaults in the code (final fallback)

### Configuration Files

#### `config/projects.json`

List of GCP project IDs to scan for buckets:

```json
[
    "cegx-nextflow",
    "prj-biomodal-castor-5381",
    ...
]
```

#### `config/exclude_buckets.json`

List of bucket names to exclude from archiving:

```json
[
    "cegx-runcrc",
    "cegx-run1808",
    ...
]
```

### GCS Configuration Bucket

The Cloud Function loads configuration from the `biomodal-bucket-archiver-config` GCS bucket:

- **Bucket location**: `gs://biomodal-bucket-archiver-config/`
- **Projects list**: `gs://biomodal-bucket-archiver-config/archive_config/projects.json`
- **Exclusions list**: `gs://biomodal-bucket-archiver-config/archive_config/exclude_buckets.json`

The deployment script automatically:

1. Creates the bucket if it doesn't exist
2. Uploads the local `config/*.json` files to the bucket
3. The Cloud Function loads these files at startup

To update configuration without redeploying the function, modify the files in GCS directly or use the `update_config.sh` script.

## Environment Variables

- `CONFIG_BUCKET`: GCS bucket storing configuration files (default: `biomodal-bucket-archiver-config`)
- `DAYS_TO_WAIT`: Days before archiving buckets (default: `180`)

## Deployment

### Initial Deployment

1. **Deploy the function and upload configuration:**

   ```bash
   ./deploy.sh
   ```

2. **Create the weekly scheduler job:**

   ```bash
   ./create_scheduler.sh
   ```

### Redeployment

To remove and redeploy (useful for updates):

```bash
./deploy.sh --redeploy        # Remove and redeploy Cloud Function
./create_scheduler.sh --redeploy  # Remove and recreate scheduler job
```

Both scripts support `-r` as a shorthand for `--redeploy`.

## Usage

### Manual Invocation

- **Archive buckets in all registered projects:**

  ```bash
  curl -X POST \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    https://europe-west2-prj-platform-tools-prod.cloudfunctions.net/archive-storage
  ```

- **Archive buckets in a specific project:**

  ```bash
  curl -X POST \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"project":"cegx-nextflow"}' \
    https://europe-west2-prj-platform-tools-prod.cloudfunctions.net/archive-storage
  ```

**Note:** Use `print-identity-token` instead of `print-access-token` for authenticated Cloud Functions.

### Update Configuration

Update configuration without redeploying:

```bash
./update_config.sh
```

## Monitoring

- **View function logs:**

  ```bash
  gcloud functions logs read archive-storage --region=europe-west2 --project=prj-platform-tools-prod
  ```

- **View scheduler job status:**

  ```bash
  gcloud scheduler jobs describe weekly-bucket-archiver --location=europe-west2 --project=prj-platform-tools-prod
  ```

- **Check next scheduled run:**

  ```bash
  gcloud scheduler jobs describe weekly-bucket-archiver --location=europe-west2 --project=prj-platform-tools-prod --format='value(scheduleTime)'
  ```

- **Manually trigger scheduler job:**

  ```bash
  gcloud scheduler jobs run weekly-bucket-archiver --location=europe-west2 --project=prj-platform-tools-prod
  ```

## Architecture

1. **Configuration Loading**: Loads project lists and exclusions from GCS
2. **Project Processing**: Iterates through each configured project
3. **Bucket Filtering**: Applies naming patterns and exclusion lists
4. **Age Checking**: Only processes buckets older than specified days
5. **Autoclass Handling**: Disables Autoclass if enabled
6. **Blob Processing**: Updates all blobs to ARCHIVE storage class
7. **Bucket Update**: Sets bucket default storage class to ARCHIVE

## File Structure

```text
bucket_archiver/
├── archive_storage_class.py   # Main Cloud Function implementation
├── main.py                    # Cloud Function entry point
├── requirements.txt           # Python dependencies
├── deploy.sh                  # Deployment script (supports --redeploy)
├── create_scheduler.sh        # Scheduler creation script (supports --redeploy)
├── update_config.sh           # Configuration update script
├── README.md                  # This file
└── config/
    ├── projects.json          # Project list to scan
    └── exclude_buckets.json   # Exclusion list
```

## How It Works

1. **Configuration Loading**:
   - Attempts to load configuration from GCS bucket `biomodal-bucket-archiver-config`
   - Looks for `archive_config/projects.json` and `archive_config/exclude_buckets.json`
   - Falls back to local `config/*.json` files if GCS fails
   - Uses hardcoded defaults as final fallback

2. **Project Processing**:
   - Iterates through each configured project
   - Creates storage client for each project

3. **Bucket Filtering**:
   - Only processes buckets matching patterns: `cegx-run*`, `biomodal-run*`
   - Skips buckets in the exclusion list
   - Skips buckets already in ARCHIVE storage class

4. **Age Checking**:
   - Only processes buckets where the latest blob is older than 180 days
   - Skips empty buckets

5. **Autoclass Handling**:
   - Disables Autoclass if enabled
   - Sets bucket to STANDARD storage class first

6. **Blob Processing**:
   - Updates all blobs (except `nf-work/` folders) to ARCHIVE storage class
   - Uses ThreadPoolExecutor with 10 workers for concurrent processing
   - Adds custom metadata to each blob

7. **Bucket Update**:
   - Sets bucket default storage class to ARCHIVE

## Troubleshooting

- **Permission denied**: Ensure service account `sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com` has Storage Admin role on all target projects
- **Configuration not loading**: Check CONFIG_BUCKET environment variable and GCS bucket accessibility
- **Function timeout**: Large projects may need increased timeout (currently set to 60 minutes)
- **Memory issues**: Function uses 2GB memory for concurrent processing (10 workers)
- **Iterator errors**: The fix converts bucket iterators to lists to prevent exhaustion
- **Deployment errors**: Use `--redeploy` flag to remove and recreate resources
