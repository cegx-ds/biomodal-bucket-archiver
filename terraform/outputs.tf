output "service_account_email" {
  description = "Email of the created service account"
  value       = google_service_account.bucket_archiver.email
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.bucket_archiver.name
}

output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.bucket_archiver.service_config[0].uri
}

output "config_bucket_name" {
  description = "Name of the configuration bucket"
  value       = var.config_bucket_name
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.weekly_archiver.name
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
