# Bucket Archiver Terraform Module

This Terraform module deploys the bucket archiver infrastructure to Google Cloud Platform, replacing the shell scripts with Infrastructure as Code.

## Resources Created

- **Cloud Function**: Executes the bucket archiving logic
- **Cloud Scheduler**: Triggers the function on a weekly schedule
- **Service Account**: Dedicated SA with Storage Admin permissions across specified projects
- **Storage Bucket**: Stores configuration files and function source code
- **IAM Bindings**: Grants appropriate permissions to the service account

## Usage

1. Copy the example terraform.tfvars file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Modify `terraform.tfvars` with your specific values if needed.

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Service Account Permissions

The created service account (`bucket-archiver-sa`) will have:
- `roles/storage.admin` in all projects listed in `../config/projects.json`
- `roles/storage.objectViewer` on the configuration bucket
- `roles/cloudfunctions.invoker` on the Cloud Function

## Configuration Files

The module automatically uploads:
- `../config/projects.json` - List of projects to process
- `../config/exclude_buckets.json` - Buckets to exclude from archiving

## Variables

| Name | Description | Default |
|------|-------------|---------|
| project_id | GCP project ID | `prj-platform-tools-prod` |
| region | GCP region | `europe-west2` |
| config_bucket_name | Configuration bucket name | `biomodal-bucket-archiver-configs` |
| function_name | Cloud Function name | `archive-storage` |
| service_account_name | Service account name | `bucket-archiver-sa` |
| scheduler_job_name | Scheduler job name | `weekly-bucket-archiver` |
| schedule | Cron schedule | `0 2 * * 0` (Sunday 2 AM UTC) |
| days_to_wait | Days before archiving | `180` |

## Outputs

- `service_account_email` - Email of the created service account
- `function_name` - Name of the deployed function
- `function_url` - URL of the deployed function
- `config_bucket_name` - Name of the configuration bucket
- `scheduler_job_name` - Name of the scheduler job
- `projects_with_access` - List of projects with SA access

## Migration from Shell Scripts

This Terraform module replaces:
- `deploy.sh` - Creates Cloud Function and uploads configs
- `create_scheduler.sh` - Creates Cloud Scheduler job

The service account is now created and managed by Terraform with proper IAM bindings across all projects.