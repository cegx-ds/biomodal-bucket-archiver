#!/usr/bin/env python3

#
# Copyright (C) 2024-2025 biomodal. All rights reserved.
#

import concurrent.futures
import logging
import functions_framework
import os
import json
from google.cloud import storage
from google.cloud.storage import constants
import datetime
import pytz

# Configure logging for Cloud Functions
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Number of days to wait before archiving a bucket
DAYS_TO_WAIT = int(os.environ.get('DAYS_TO_WAIT', '180'))

# Configuration bucket for storing project lists and exclusions
CONFIG_BUCKET = os.environ.get('CONFIG_BUCKET', 'biomodal-bucket-archiver-configs')

def load_config_from_gcs():
    """Load configuration from GCS bucket."""
    try:
        client = storage.Client()
        bucket = client.bucket(CONFIG_BUCKET)

        # Load projects list
        projects_blob = bucket.blob('config/projects.json')
        if not projects_blob.exists():
            logger.error(f"Missing required config: config/projects.json in GCS bucket '{CONFIG_BUCKET}'.")
            raise FileNotFoundError(f"Required config file 'projects.json' not found in GCS bucket '{CONFIG_BUCKET}'.")
        projects = json.loads(projects_blob.download_as_text())

        # Load exclude buckets list
        exclude_blob = bucket.blob('config/exclude_buckets.json')
        if not exclude_blob.exists():
            logger.error(f"Missing required config: config/exclude_buckets.json in GCS bucket '{CONFIG_BUCKET}'.")
            raise FileNotFoundError(f"Required config file 'exclude_buckets.json' not found in GCS bucket '{CONFIG_BUCKET}'.")
        exclude_buckets = json.loads(exclude_blob.download_as_text())

        logger.info(f"Loaded config from GCS bucket '{CONFIG_BUCKET}': {len(projects)} projects, {len(exclude_buckets)} excluded buckets")
        return projects, exclude_buckets

    except Exception as e:
        logger.error(f"Failed to load config from GCS bucket '{CONFIG_BUCKET}': {e}. Exiting.")
        raise

# Load configuration at startup
projects, storage_class_exclude_buckets = load_config_from_gcs()


def update_blob_storage_class(blob):
    """
    Update the storage class of the blob.

    Args:
        blob (storage.Blob): The blob to change the storage class of.

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        if blob.name.endswith("/"):
            return True

        if blob.storage_class == constants.ARCHIVE_STORAGE_CLASS:
            return True

        if "nf-work/" in blob.name:
            return True

        blob.custom_time = blob.time_created
        # Add custom metadata to the blob
        custom_metadata = {
            "created_date": blob.time_created,
            "updated_date": blob.updated,
        }
        blob.metadata = custom_metadata
        blob.update_storage_class(constants.ARCHIVE_STORAGE_CLASS)
        logger.debug(f"Updated metadata for blob '{blob.id}' ({blob.custom_time})")
        return True
    except Exception as e:
        logger.error(f"Error changing storage class for blob {blob.name}: {str(e)}")
        return False


def change_bucket_storage_class(bucket: storage.Bucket) -> bool:
    """
    Change the storage class of the bucket.

    Args:
        bucket (storage.Bucket): The bucket to change the storage class of.

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        bucket_name = bucket.name
        if bucket_name is None:
            logger.warning(f"Bucket object has no name, skipping: {bucket}")
            return False
        bucket_name = bucket_name.replace(".", "-")

        if bucket_name in storage_class_exclude_buckets:
            return True

        # valid bucket names to archive
        if not any(prefix in bucket_name for prefix in ["cegx-run", "biomodal-run"]):
            return True

        if bucket.storage_class == constants.ARCHIVE_STORAGE_CLASS:
            return True

        latest_blob_update_create_date = None
        # Make the current datetime aware
        now_aware = datetime.datetime.now(pytz.utc)

        for blob in bucket.list_blobs():
            if latest_blob_update_create_date is None:
                latest_blob_update_create_date = blob.updated
            elif blob.updated > latest_blob_update_create_date:
                latest_blob_update_create_date = blob.updated

        if latest_blob_update_create_date is None:
            logger.info(f"Skipping bucket '{bucket.name}' as it has no blobs")
            return True

        # Compare the naive datetimes
        # if bucket_name == 'cegx-run2120' or latest_blob_update_create_date < now_aware - datetime.timedelta(days=DAYS_TO_WAIT):
        if latest_blob_update_create_date < now_aware - datetime.timedelta(days=DAYS_TO_WAIT):
            logger.info(f"Processing bucket '{bucket.name}' (last updated: {latest_blob_update_create_date})")

            # Disable Autoclass if enabled
            if bucket.autoclass_enabled:
                bucket.autoclass_enabled = False
                bucket.patch()
                logger.info(f"Disabled Autoclass for bucket '{bucket.name}'")

            # Ensure the bucket's storage class is explicitly set to STANDARD before changing to ARCHIVE
            if bucket.storage_class != constants.STANDARD_STORAGE_CLASS:
                bucket.storage_class = constants.STANDARD_STORAGE_CLASS
                bucket.patch()
                logger.info(f"Set storage class of bucket '{bucket.name}' to '{constants.STANDARD_STORAGE_CLASS}'")

            # Update all blobs in the bucket to the new storage class
            blobs = list(bucket.list_blobs())
            failed_blobs = 0

            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                results = list(executor.map(update_blob_storage_class, blobs))
                failed_blobs = sum(1 for result in results if not result)

            if failed_blobs > 0:
                error_msg = f"Failed to update {failed_blobs} blobs in bucket '{bucket.name}'. Exiting."
                logger.error(error_msg)
                raise RuntimeError(error_msg)

            # Finally, update the storage class of the bucket to ARCHIVE
            bucket.storage_class = constants.ARCHIVE_STORAGE_CLASS
            bucket.patch()
            logger.info(f"Changed storage class of bucket '{bucket.name}' to '{constants.ARCHIVE_STORAGE_CLASS}'")

            return failed_blobs == 0
        else:
            logger.debug(f"Skipping bucket '{bucket.name}' as it has been updated in the last {DAYS_TO_WAIT} days")
            return True

    except Exception as e:
        logger.error(f"Error changing storage class for bucket '{bucket.name}': {str(e)}")
        return False


def process_project(project_id: str) -> dict:
    """
    Process a single project.

    Args:
        project_id (str): The project ID to process

    Returns:
        dict: Processing results
    """
    results = {
        "project_id": project_id,
        "buckets_processed": 0,
        "buckets_successful": 0,
        "buckets_failed": 0,
        "errors": []
    }

    try:
        logger.info(f"Processing project: {project_id}")
        storage_client = storage.Client(project=project_id)
        buckets = list(storage_client.list_buckets())  # Convert to list to avoid iterator exhaustion

        for bucket in buckets:
            results["buckets_processed"] += 1
            if change_bucket_storage_class(bucket):
                results["buckets_successful"] += 1
            else:
                results["buckets_failed"] += 1

    except Exception as e:
        error_msg = f"Error processing project {project_id}: {str(e)}"
        logger.error(error_msg)
        results["errors"].append(error_msg)

    return results


@functions_framework.http
def archive_storage_handler(request):
    """
    Cloud Function entry point for archiving storage.

    Args:
        request: HTTP request object

    Returns:
        dict: Processing results
    """
    start_time = datetime.datetime.now()
    logger.info("Starting storage archival process")

    # Parse request parameters
    request_json = request.get_json(silent=True)
    project_filter = None

    if request_json and 'project' in request_json:
        project_filter = request_json['project']
        target_projects = [project_filter] if project_filter in projects else []
    else:
        target_projects = projects

    if not target_projects:
        return {
            "status": "error",
            "message": f"No valid projects to process. Filter: {project_filter}"
        }

    total_results = {
        "status": "success",
        "start_time": start_time.isoformat(),
        "projects_processed": 0,
        "total_buckets_processed": 0,
        "total_buckets_successful": 0,
        "total_buckets_failed": 0,
        "project_results": [],
        "errors": []
    }

    # Process projects
    for project_id in target_projects:
        project_results = process_project(project_id)
        total_results["project_results"].append(project_results)
        total_results["projects_processed"] += 1
        total_results["total_buckets_processed"] += project_results["buckets_processed"]
        total_results["total_buckets_successful"] += project_results["buckets_successful"]
        total_results["total_buckets_failed"] += project_results["buckets_failed"]
        total_results["errors"].extend(project_results["errors"])

    end_time = datetime.datetime.now()
    total_results["end_time"] = end_time.isoformat()
    total_results["duration_seconds"] = (end_time - start_time).total_seconds()

    if total_results["total_buckets_failed"] > 0 or total_results["errors"]:
        total_results["status"] = "partial_success"

    logger.info(f"Storage archival process completed. Status: {total_results['status']}")
    return total_results


def find_all_buckets() -> None:
    """
    Find all Google Cloud Storage (GCS) buckets for all projects.
    (Legacy function for local testing)
    """
    for project in projects:
        process_project(project)
    logger.info("Done archiving buckets!")


if __name__ == "__main__":
    find_all_buckets()
