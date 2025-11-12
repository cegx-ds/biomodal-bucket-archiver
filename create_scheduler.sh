#!/bin/bash

# Configuration
PROJECT_ID="prj-platform-tools-prod"
FUNCTION_NAME="archive-storage"
REGION="europe-west2"
JOB_NAME="weekly-bucket-archiver"
SCHEDULE="0 2 * * 1"  # Every Monday at 2 AM UTC
SERVICE_ACCOUNT="sa-dashboarding-internal-dev@prj-biomodal-project-factory.iam.gserviceaccount.com"

# Check if we should remove first
if [ "$1" == "--redeploy" ] || [ "$1" == "-r" ]; then
    echo "Removing existing Cloud Scheduler job..."
    gcloud scheduler jobs delete "$JOB_NAME" \
      --location="$REGION" \
      --project="$PROJECT_ID" \
      --quiet 2>/dev/null || echo "Job doesn't exist or already deleted"
    echo ""
fi

echo "Creating Cloud Scheduler job for weekly bucket archiving..."

# Create the Cloud Scheduler job
gcloud scheduler jobs create http "$JOB_NAME" \
  --location="$REGION" \
  --schedule="$SCHEDULE" \
  --uri="https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_NAME" \
  --http-method=POST \
  --headers="Content-Type=application/json" \
  --message-body='{}' \
  --oidc-service-account-email="$SERVICE_ACCOUNT" \
  --description="Weekly bucket archiver - runs every Monday at 2 AM UTC" \
  --project="$PROJECT_ID" \
  --time-zone="UTC"

echo "Cloud Scheduler job '$JOB_NAME' created successfully!"
echo "Schedule: Every Monday at 2 AM UTC"
echo "Next run will be: $(gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format='value(scheduleTime)' --project=$PROJECT_ID)"
echo ""
echo "To redeploy (remove and create fresh), run: ./create_scheduler.sh --redeploy"
