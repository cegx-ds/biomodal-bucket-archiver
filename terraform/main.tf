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

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
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

# Create Workload Identity Pool for GitHub Actions
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions"
  project                   = var.project_id
}

# Create Workload Identity Provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"
  description                        = "OIDC identity provider for GitHub Actions"
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}'"
}

# Allow the GitHub Actions service account to impersonate the bucket archiver SA
resource "google_service_account_iam_member" "github_sa_impersonation" {
  service_account_id = google_service_account.bucket_archiver.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_org}/${var.github_repo}"
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
    google_storage_bucket_iam_member.config_bucket_reader,
    google_project_service.required_apis
  ]
}

# Upload the function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = var.config_bucket_name
  source = data.archive_file.function_source.output_path
}

# Grant the service account Cloud Run Invoker role in the host project
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Allow the function to be invoked by the scheduler (Cloud Functions permission)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.bucket_archiver.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Create the Cloud Scheduler job
resource "google_cloud_scheduler_job" "weekly_archiver" {
  name             = var.scheduler_job_name
  region           = var.region
  project          = var.project_id
  description      = "Bucket archiver job (see schedule variable for timing)"
  schedule         = var.schedule
  time_zone        = "UTC"
  attempt_deadline = "1800s"

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
    google_cloudfunctions2_function_iam_member.invoker,
    google_project_iam_member.run_invoker,
    google_project_service.required_apis
  ]
}

# Local values for reading the projects list
locals {
  projects_json = file("../config/projects.json")
  projects_list = jsondecode(local.projects_json)
}
