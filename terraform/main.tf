# Load projects list for cross-project IAM bindings
locals {
  projects_json = file("../config/projects.json")
  projects_list = jsondecode(local.projects_json)
}

# Create service account first, before any other resources
resource "google_service_account" "bucket_archiver" {
  account_id   = "sa-bucket-archiver"
  display_name = "Bucket Archiver Service Account"
  description  = "Service account for automated bucket archiving across projects"
  project      = var.project_id
}

# Grant Storage Admin access to the service account in each project
resource "google_project_iam_member" "storage_admin" {
  for_each = toset(local.projects_list)
  project  = each.value
  role     = "roles/storage.admin"
  member   = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Grant Cloud Run Viewer access to the service account in each project
resource "google_project_iam_member" "run_viewer" {
  for_each = toset(local.projects_list)
  project  = each.value
  role     = "roles/run.viewer"
  member   = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

# Grant Cloud Build service account access to read from config bucket for deployment
data "google_project" "project" {
  project_id = var.project_id
}

resource "google_storage_bucket_iam_member" "cloudbuild_bucket_access" {
  bucket = var.config_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}


# Permissions for bucket archiver service account in prj-platform-tools-prod
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.bucket_archiver.email}"
}


resource "google_project_iam_member" "cf_service_agent" {
  project = var.project_id
  role    = "roles/cloudfunctions.serviceAgent"
  member  = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bucket_archiver.email}"
}


resource "google_cloud_scheduler_job" "weekly_archiver" {
  name             = var.scheduler_job_name
  region           = var.region
  project          = var.project_id
  description      = "Bucket archiver job"
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
}

# Cloud Function V2
resource "google_storage_bucket_object" "archive" {
  name   = "index.zip"
  bucket = var.config_bucket_name
  source = data.archive_file.function_source.output_path
}

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

resource "google_storage_bucket_object" "projects_config" {
  name   = "config/projects.json"
  bucket = var.config_bucket_name
  source = "../config/projects.json"
}

# Upload exclude_buckets configuration
resource "google_storage_bucket_object" "exclude_buckets_config" {
  name   = "config/exclude_buckets.json"
  bucket = var.config_bucket_name
  source = "../config/exclude_buckets.json"
}

resource "google_cloudfunctions2_function" "bucket_archiver" {
  name        = var.function_name
  location    = var.region
  description = "Cloud Function to archive GCS buckets"

  build_config {
    runtime     = "python311"
    entry_point = "archive_storage_handler"
    source {
      storage_source {
        bucket = var.config_bucket_name
        object = google_storage_bucket_object.archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "1024M"
    timeout_seconds       = 1800
    service_account_email = google_service_account.bucket_archiver.email
    environment_variables = {
      CONFIG_BUCKET = var.config_bucket_name
      DAYS_TO_WAIT  = var.days_to_wait
    }
  }

  # Ensure service account and all IAM bindings are created first
  depends_on = [
    google_service_account.bucket_archiver,
    google_project_iam_member.storage_admin,
    google_project_iam_member.run_viewer,
    google_project_iam_member.run_invoker,
    google_project_iam_member.cf_service_agent,
    google_project_iam_member.logging_writer
  ]
}

# IAM entry for service account to invoke the function
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.bucket_archiver.location
  cloud_function = google_cloudfunctions2_function.bucket_archiver.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.bucket_archiver.email}"
}


####

# Create Workload Identity Pool for GitHub Actions
# resource "google_iam_workload_identity_pool" "github_pool" {
#   workload_identity_pool_id = "github-actions-pool"
#   display_name              = "GitHub Actions Pool"
#   description               = "Workload Identity Pool for GitHub Actions"
#   project                   = var.project_id
# }

# Create Workload Identity Provider for GitHub
# resource "google_iam_workload_identity_pool_provider" "github_provider" {
#   workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
#   workload_identity_pool_provider_id = "github-provider"
#   display_name                       = "GitHub Provider"
#   description                        = "OIDC identity provider for GitHub Actions"
#   project                            = var.project_id

#   attribute_mapping = {
#     "google.subject"             = "assertion.sub"
#     "attribute.actor"            = "assertion.actor"
#     "attribute.repository"       = "assertion.repository"
#     "attribute.repository_owner" = "assertion.repository_owner"
#   }

#   oidc {
#     issuer_uri = "https://token.actions.githubusercontent.com"
#   }

#   attribute_condition = "assertion.repository_owner == '${var.github_org}'"
# }

####


