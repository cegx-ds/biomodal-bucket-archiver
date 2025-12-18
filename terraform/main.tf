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
    uri         = google_cloud_run_v2_service.bucket_archiver.uri
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode("{}")

    oidc_token {
      service_account_email = google_service_account.bucket_archiver.email
    }
  }
}

# Upload configuration files
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

# Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "bucket_archiver" {
  location      = var.region
  repository_id = "bucket-archiver"
  description   = "Docker repository for bucket archiver"
  format        = "DOCKER"
  project       = var.project_id
}

# Cloud Run service
resource "google_cloud_run_v2_service" "bucket_archiver" {
  name     = var.function_name
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.bucket_archiver.email

    timeout = "1800s"

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.bucket_archiver.repository_id}/bucket-archiver:latest"

      resources {
        limits = {
          memory = "1Gi"
          cpu    = "1"
        }
      }

      env {
        name  = "CONFIG_BUCKET"
        value = var.config_bucket_name
      }

      env {
        name  = "DAYS_TO_WAIT"
        value = tostring(var.days_to_wait)
      }
    }

    scaling {
      max_instance_count = 1
    }
  }

  # Ensure service account and all IAM bindings are created first
  depends_on = [
    google_service_account.bucket_archiver,
    google_project_iam_member.storage_admin,
    google_project_iam_member.run_viewer,
    google_project_iam_member.run_invoker,
    google_project_iam_member.cf_service_agent,
    google_project_iam_member.logging_writer,
    google_artifact_registry_repository.bucket_archiver
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

# IAM entry for service account to invoke Cloud Run
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.bucket_archiver.location
  name     = google_cloud_run_v2_service.bucket_archiver.name

  role   = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.bucket_archiver.email}"
}

