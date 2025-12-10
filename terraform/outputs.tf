output "service_account_email" {
  description = "Email of the created service account"
  value       = google_service_account.bucket_archiver.email
}

output "service_name" {
  description = "Name of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.bucket_archiver.name
}

output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.bucket_archiver.uri
}

output "config_bucket_name" {
  description = "Name of the configuration bucket"
  value       = var.config_bucket_name
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.weekly_archiver.name
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository for Docker images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.bucket_archiver.repository_id}"
}

# output "projects_with_access" {
#   description = "List of projects where the service account has Storage Admin access"
#   value       = local.projects_list
# }

# output "workload_identity_provider" {
#   description = "The Workload Identity Provider name for GitHub Actions"
#   value       = google_iam_workload_identity_pool_provider.github_provider.name
# }

output "github_service_account" {
  description = "Service account email for GitHub Actions impersonation"
  value       = google_service_account.bucket_archiver.email
}
