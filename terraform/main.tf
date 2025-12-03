terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Upload configuration files to the existing bucket
resource "google_storage_bucket_object" "projects_config" {
  name   = "config/projects.json"
  bucket = var.config_bucket_name
  source = "../config/projects.json"
}

resource "google_storage_bucket_object" "exclude_buckets_config" {
  name   = "config/exclude_buckets.json"
  bucket = var.config_bucket_name
  source = "../config/exclude_buckets.json"
}

# Create a dedicated service account for the bucket archiver
resource "google_service_account" "bucket_archiver" {
  account_id   = var.service_account_name
  display_name = "Bucket Archiver Service Account"
  description  = "Service account for automated bucket archiving across projects"
  project      = var.project_id
}

# Grant Storage Admin role to the service account in each project
resource "google_project_iam_member" "storage_admin" {
  for_each = toset(local.projects_list)

  project = each.value
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Grant the service account access to read from the config bucket
resource "google_storage_bucket_iam_member" "config_bucket_reader" {
  bucket = var.config_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Create archive of the source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source_dir  = "../"
  excludes = [
    "terraform/",
    ".git/",
    ".gitignore",
    "README.md",
    "*.sh",
    "__pycache__/",
    "*.pyc"
  ]
}

# Create the Cloud Function
resource "google_cloudfunctions2_function" "bucket_archiver" {
  name        = var.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated bucket archiving function"

  build_config {
    runtime     = "python311"
    entry_point = "archive_storage_handler"
    source {
      storage_source {
        bucket = var.config_bucket_name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "2Gi"
    timeout_seconds       = 3600
    service_account_email = google_service_account.bucket_archiver.email

    environment_variables = {
      CONFIG_BUCKET = var.config_bucket_name
      DAYS_TO_WAIT  = var.days_to_wait
    }
  }

  depends_on = [
    google_project_iam_member.storage_admin,
    google_storage_bucket_iam_member.config_bucket_reader
  ]
}

# Upload the function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = var.config_bucket_name
  source = data.archive_file.function_source.output_path
}

# Allow the function to be invoked by the scheduler
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.bucket_archiver.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Create the Cloud Scheduler job
resource "google_cloud_scheduler_job" "weekly_archiver" {
  name        = var.scheduler_job_name
  region      = var.region
  project     = var.project_id
  description = "Weekly bucket archiver - runs every Sunday at 2 AM UTC"
  schedule    = var.schedule
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.bucket_archiver.service_config[0].uri
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode("{}")

    oidc_token {
      service_account_email = google_service_account.bucket_archiver.email
    }
  }

  depends_on = [
    google_cloudfunctions2_function.bucket_archiver,
    google_cloudfunctions2_function_iam_member.invoker
  ]
}

# Local values for reading the projects list
locals {
  projects_json = file("../config/projects.json")
  projects_list = jsondecode(local.projects_json)
}
