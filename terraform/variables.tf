variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  default     = "prj-platform-tools-prod"
}

variable "region" {
  description = "The GCP region where resources will be deployed"
  type        = string
  default     = "europe-west2"
}

variable "config_bucket_name" {
  description = "Name of the GCS bucket to store configuration files"
  type        = string
  default     = "biomodal-bucket-archiver-configs"
}

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "archive-storage"
}

variable "service_account_name" {
  description = "Name of the dedicated service account for bucket archiving"
  type        = string
  default     = "bucket-archiver-sa"
}

variable "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  type        = string
  default     = "weekly-bucket-archiver"
}

variable "schedule" {
  description = "Cron schedule for the bucket archiver"
  type        = string
  default     = "0 16 * * 2"
}

variable "days_to_wait" {
  description = "Number of days to wait before archiving buckets"
  type        = number
  default     = 180
}

variable "github_org" {
  description = "GitHub organization name for Workload Identity"
  type        = string
  default     = "cegx-ds"
}

variable "github_repo" {
  description = "GitHub repository name for Workload Identity"
  type        = string
  default     = "biomodal-bucket-archiver"
}
