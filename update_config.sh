#!/bin/bash

# Configuration bucket (change this to your bucket name)
CONFIG_BUCKET="biomodal-bucket-archiver-config"

if [ $# -eq 0 ]; then
    echo "Usage: $0 [projects|exclude_buckets|both]"
    echo "Updates configuration files in GCS bucket"
    exit 1
fi

UPDATE_TYPE="$1"

case "$UPDATE_TYPE" in
    "projects")
        echo "Updating projects configuration..."
        gsutil cp config/projects.json "gs://$CONFIG_BUCKET/archive_config/"
        echo "Projects configuration updated!"
        ;;
    "exclude_buckets")
        echo "Updating exclude buckets configuration..."
        gsutil cp config/exclude_buckets.json "gs://$CONFIG_BUCKET/archive_config/"
        echo "Exclude buckets configuration updated!"
        ;;
    "both")
        echo "Updating all configuration files..."
        gsutil cp config/projects.json "gs://$CONFIG_BUCKET/archive_config/"
        gsutil cp config/exclude_buckets.json "gs://$CONFIG_BUCKET/archive_config/"
        echo "All configuration files updated!"
        ;;
    *)
        echo "Invalid option: $UPDATE_TYPE"
        echo "Usage: $0 [projects|exclude_buckets|both]"
        exit 1
        ;;
esac

echo "Configuration will be loaded automatically on next Cloud Function execution."
