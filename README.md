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
2. Your user account needs these IAM permissions:
   - Cloud Functions Admin (to deploy functions)
   - Cloud Scheduler Admin (to create scheduler jobs)
   - Service Account User role on the service account `sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com`
3. Service account `sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com` needs:
   - Storage Admin on all target projects
4. Access to `prj-platform-tools-prod` project
5. Required Google Cloud APIs (will be prompted to enable during first deployment):
   - Cloud Functions API (`cloudfunctions.googleapis.com`)
   - Cloud Build API (`cloudbuild.googleapis.com`)
   - Cloud Scheduler API (`cloudscheduler.googleapis.com`)

## Configuration

Configuration is managed through JSON files stored in a Google Cloud Storage (GCS) bucket. **Both configuration files must exist in the specified bucket. If either file is missing or cannot be loaded, the process will raise an error and exit. No fallback to local files or hardcoded defaults will occur.**

### Required Configuration Files in GCS

- `config/projects.json`: List of GCP project IDs to scan for buckets
- `config/exclude_buckets.json`: List of bucket names to exclude from archiving

**Both files must be present in the bucket specified by the `CONFIG_BUCKET` environment variable (default: `biomodal-bucket-archiver-configs`).**

Example bucket structure:

```text
gs://<CONFIG_BUCKET>/config/projects.json
gs://<CONFIG_BUCKET>/config/exclude_buckets.json
```

If either file is missing, the function will log an error including the bucket name and exit immediately.

### GCS Configuration Bucket

The Cloud Function loads configuration from the `biomodal-bucket-archiver-configs` GCS bucket:

- **Bucket location**: `gs://biomodal-bucket-archiver-configs/`
- **Projects list**: `gs://biomodal-bucket-archiver-configs/config/projects.json`
- **Exclusions list**: `gs://biomodal-bucket-archiver-configs/config/exclude_buckets.json`

The deployment script automatically:

1. Creates the bucket if it doesn't exist
2. Uploads the local `config/*.json` files to the bucket
3. The Cloud Function loads these files at startup

To update configuration without redeploying the function, modify the files in GCS directly or use the `update_config.sh` script.

## Environment Variables

- `CONFIG_BUCKET`: GCS bucket storing configuration files (default: `biomodal-bucket-archiver-configs`)
- `DAYS_TO_WAIT`: Days before archiving buckets (default: `180`)

## Deployment

### Initial Deployment

**Note:** On first deployment, you will be prompted to enable required APIs if they're not already enabled:

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

Answer `y` when prompted. This is a one-time setup and may take a few minutes.

**Important:** If you see a warning about the Cloud Build service account missing the `roles/cloudbuild.builds.builder` role, run the following command (replace the project ID and service account number if different):

```bash
gcloud projects add-iam-policy-binding prj-platform-tools-prod \
  --member=serviceAccount:858243249399-compute@developer.gserviceaccount.com \
  --role=roles/cloudbuild.builds.builder
```

For more information, see: [Cloud Functions Troubleshooting](https://cloud.google.com/functions/docs/troubleshooting#build-service-account)

**Important:** If you see an error about missing `iam.serviceaccounts.actAs` permission, you need the Service Account User role on the service account. Have a project admin run:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com \
  --member=user:YOUR_EMAIL@example.com \
  --role=roles/iam.serviceAccountUser \
  --project=prj-biomodal-project-factory
```

Replace `YOUR_EMAIL@example.com` with your Google Cloud account email. Note: The `--project` flag is required because the service account exists in the `prj-biomodal-project-factory` project.

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
   - Loads configuration from GCS bucket specified by `CONFIG_BUCKET`
   - Requires both `config/projects.json` and `config/exclude_buckets.json` to exist
   - If either file is missing, the process raises an error and exits

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
- **Missing configuration files**: Ensure both `projects.json` and `exclude_buckets.json` exist in the correct GCS bucket. The error message will include the bucket name if either file is missing.
