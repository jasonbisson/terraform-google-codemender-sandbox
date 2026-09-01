output "cluster_name" {
  description = "The name of the GKE Autopilot cluster"
  value       = google_container_cluster.autopilot_cluster.name
}

output "cluster_location" {
  description = "The location of the GKE Autopilot cluster"
  value       = google_container_cluster.autopilot_cluster.location
}

output "artifact_registry_repo" {
  description = "The Artifact Registry repository name"
  value       = google_artifact_registry_repository.repo.name
}

output "service_account_email" {
  description = "The Google Service Account email for Workload Identity"
  value       = google_service_account.codemender_sa.email
}

output "cluster_service_account_email" {
  description = "The Google Service Account email for the GKE Autopilot cluster nodes"
  value       = google_service_account.cluster_sa.email
}

output "cloud_build_service_account_email" {
  description = "The Google Service Account email for Cloud Build"
  value       = google_service_account.cloudbuild_sa.email
}

output "vpc_name" {
  description = "The VPC Network Name"
  value       = google_compute_network.vpc_network.name
}

output "src_bucket_name" {
  description = "The Source Code GCS Bucket name"
  value       = google_storage_bucket.src_bucket.name
}

output "out_bucket_name" {
  description = "The Output Reports GCS Bucket name"
  value       = google_storage_bucket.out_bucket.name
}

output "dns_zone_name" {
  description = "The DNS Managed Zone name"
  value       = google_dns_managed_zone.pa_googleapis_zone.name
}

output "container_image" {
  description = "The container image URI built and pushed to Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}/codemender-worker:latest"
}

output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "target_repo" {
  description = "The target Git repository URL staged into the source bucket"
  value       = var.target_repo
}

output "vpc_sc_perimeter_name" {
  description = "The VPC Service Controls Perimeter name if enabled"
  value       = var.enable_vpc_sc && var.access_policy_id != "" ? google_access_context_manager_service_perimeter.sandbox_perimeter[0].name : "Disabled"
}
