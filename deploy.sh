#!/bin/bash

# Configuration bucket (change this to your bucket name)
CONFIG_BUCKET="biomodal-bucket-archiver-config"
PROJECT_ID="prj-platform-tools-prod"
FUNCTION_NAME="archive-storage"
REGION="europe-west2"

# Check if we should remove first
if [ "$1" == "--redeploy" ] || [ "$1" == "-r" ]; then
    echo "Removing existing Cloud Function..."
    gcloud functions delete "$FUNCTION_NAME" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --quiet 2>/dev/null || echo "Function doesn't exist or already deleted"
    echo ""
fi

echo "Deploying archive storage configuration to $CONFIG_BUCKET"

# Create bucket if it doesn't exist
gsutil mb -p "$PROJECT_ID" "gs://$CONFIG_BUCKET" 2>/dev/null || echo "Bucket already exists"

# Upload configuration files
echo "Uploading configuration files..."
gsutil cp config/projects.json "gs://$CONFIG_BUCKET/archive_config/"
gsutil cp config/exclude_buckets.json "gs://$CONFIG_BUCKET/archive_config/"

echo "Configuration uploaded successfully!"

# Deploy the Cloud Function
echo "Deploying Cloud Function..."
gcloud functions deploy archive-storage \
  --gen2 \
  --runtime=python311 \
  --region=europe-west2 \
  --source=. \
  --entry-point=archive_storage_handler \
  --memory=2048MB \
  --timeout=3600s \
  --trigger-http \
  --service-account="sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com" \
  --set-env-vars="CONFIG_BUCKET=$CONFIG_BUCKET,DAYS_TO_WAIT=180" \
  --project="$PROJECT_ID"

echo "Deployment complete!"
echo ""
echo "To redeploy (remove and deploy fresh), run: ./deploy.sh --redeploy"
