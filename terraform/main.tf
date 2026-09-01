terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "project" {}

# ---------------------------------------------------------
# Enable necessary APIs
# ---------------------------------------------------------
resource "google_project_service" "services" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "servicedirectory.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "aiplatform.googleapis.com",
    "accesscontextmanager.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# ---------------------------------------------------------
# Random suffix for globally unique bucket names
# ---------------------------------------------------------
#resource "random_string" "bucket_suffix" {
#  length  = 6
#  special = false
#  upper   = false
#}
# ---------------------------------------------------------
# Timestamp suffix for globally unique names
# ---------------------------------------------------------
resource "time_static" "bucket_suffix" {}

# ---------------------------------------------------------
# Random suffix for unique psc  names
# ---------------------------------------------------------
resource "random_string" "psc_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# ---------------------------------------------------------
# VPC Network and Subnets
# ---------------------------------------------------------
resource "google_compute_network" "vpc_network" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.prefix}-subnet"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = var.region
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.prefix}-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "${var.prefix}-services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# ---------------------------------------------------------
# DNS for Private Service Connect / Private Google Access
# ---------------------------------------------------------
resource "google_dns_managed_zone" "pa_googleapis_zone" {
  name        = "pa-googleapis-zone"
  dns_name    = "pa.googleapis.com."
  description = "Private DNS zone for Google APIs"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
  depends_on = [google_project_service.services["dns.googleapis.com"]]
}

resource "google_dns_record_set" "pa_googleapis_a" {
  name         = "*.pa.googleapis.com."
  managed_zone = google_dns_managed_zone.pa_googleapis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.psc_ip.address]
}

resource "google_dns_managed_zone" "googleapis_zone" {
  name        = "googleapis-zone"
  dns_name    = "googleapis.com."
  description = "Private DNS zone for Google APIs"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
  depends_on = [google_project_service.services["dns.googleapis.com"]]
}

resource "google_dns_record_set" "googleapis_a" {
  name         = "googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
}

resource "google_dns_record_set" "googleapis_cname" {
  name         = "*.googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_zone.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["restricted.googleapis.com."]
}

resource "google_dns_record_set" "private_googleapis_a" {
  name         = "private.googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
}

resource "google_dns_record_set" "restricted_googleapis_a" {
  name         = "restricted.googleapis.com."
  managed_zone = google_dns_managed_zone.googleapis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
}


# ---------------------------------------------------------
# Private Service Connect (PSC) for Google APIs
# ---------------------------------------------------------
resource "google_compute_global_address" "psc_ip" {
  name         = "${var.prefix}-psc-ip"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.vpc_network.id
  address      = "10.129.0.50"
}

resource "google_compute_global_forwarding_rule" "psc_forwarding_rule" {
  name                  = "cmsandboxpsc"
  target                = "all-apis"
  network               = google_compute_network.vpc_network.id
  ip_address            = google_compute_global_address.psc_ip.id
  load_balancing_scheme = ""
}


# ---------------------------------------------------------
# Dedicated GKE Cluster Service Account
# ---------------------------------------------------------
resource "google_service_account" "cluster_sa" {
  account_id   = "${var.prefix}-cluster-sa"
  display_name = "GKE Autopilot Cluster Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}

# Assign required IAM roles for GKE Autopilot nodes
resource "google_project_iam_member" "cluster_sa_roles" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cluster_sa.email}"
}

# ---------------------------------------------------------
# Dedicated Cloud Build Service Account
# ---------------------------------------------------------
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "${var.prefix}-build-sa"
  display_name = "Cloud Build Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}

# Project-level roles for Cloud Build Service Account (logging, source staging, GKE deployment)
resource "google_project_iam_member" "cloudbuild_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/storage.admin",
    "roles/container.developer",
    "roles/container.admin",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Allow Cloud Build Service Agent to impersonate this service account
resource "google_service_account_iam_member" "cloudbuild_sa_token_creator" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  depends_on         = [google_project_service.services["cloudbuild.googleapis.com"]]
}

resource "google_service_account_iam_member" "cloudbuild_sa_user" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  depends_on         = [google_project_service.services["cloudbuild.googleapis.com"]]
}

# Allow legacy Cloud Build service account to impersonate if invoked via legacy runner
resource "google_service_account_iam_member" "cloudbuild_legacy_sa_user" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  depends_on         = [google_project_service.services["cloudbuild.googleapis.com"]]
}

resource "google_service_account_iam_member" "cloudbuild_legacy_sa_token_creator" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  depends_on         = [google_project_service.services["cloudbuild.googleapis.com"]]
}

# ---------------------------------------------------------
# Artifact Registry
# ---------------------------------------------------------
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "${var.prefix}-repo"
  description   = "Docker repository for Codemender images"
  format        = "DOCKER"
  depends_on    = [google_project_service.services["artifactregistry.googleapis.com"]]
}

resource "google_artifact_registry_repository_iam_member" "repo_reader" {
  project    = google_artifact_registry_repository.repo.project
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cluster_sa.email}"
}

# Allow custom Cloud Build service account to push built images to the repository
resource "google_artifact_registry_repository_iam_member" "cloudbuild_sa_writer" {
  project    = google_artifact_registry_repository.repo.project
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# ---------------------------------------------------------
# GKE Autopilot Cluster
# ---------------------------------------------------------
resource "google_container_cluster" "autopilot_cluster" {
  provider            = google-beta
  name                = "${var.prefix}-cluster"
  location            = var.region
  deletion_protection = false

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Enable Autopilot
  enable_autopilot = true

  # Configure dedicated node service account for Autopilot
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.cluster_sa.email
    }
  }

  # Enable Agent Sandbox
  # The google-beta provider is needed for this feature block currently
  # Note: The terraform provider attribute for agent sandbox might not explicitly exist as a high-level block
  # but setting it via the corresponding addons config or letting Autopilot default/beta flags handle it.
  # However, GKE Autopilot supports --enable-agent-sandbox at creation. 
  # We can configure it in terraform if supported or it is enabled via CLI. 
  # Currently, the terraform provider might need to be explicitly configured.
  # According to docs, Agent sandbox is an addon or cluster setting.
  # If it's not yet in the TF provider, we might have to use local-exec or beta provider attributes.
  # Wait, docs say: "gcloud beta container clusters create-auto ... --enable-agent-sandbox"

  # For Terraform, let's try the settings. If not natively supported, we'll use a local-exec provisioner to update it.
  # We will just deploy a standard Autopilot cluster and use a local-exec script to ensure Agent Sandbox is enabled,
  # or rely on the beta provider's secret/advanced fields if they exist.

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.subnet.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.subnet.secondary_ip_range[1].range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Ensure Workload Identity is enabled (Autopilot does this by default, but explicit is good)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  depends_on = [
    google_project_service.services["container.googleapis.com"],
    google_project_iam_member.cluster_sa_roles
  ]
}

# Null resource to enable Agent Sandbox if the provider doesn't support it directly yet.
# Since the docs state it requires gcloud beta and the provider might lag.
resource "null_resource" "enable_agent_sandbox" {
  depends_on = [google_container_cluster.autopilot_cluster]

  provisioner "local-exec" {
    command = <<EOF
      gcloud beta container clusters update ${google_container_cluster.autopilot_cluster.name} \
        --location=${var.region} \
        --enable-agent-sandbox \
        --project=${var.project_id}
    EOF
  }
}

# ---------------------------------------------------------
# Workload Identity IAM
# ---------------------------------------------------------
# Service Account for the GKE Pod
resource "google_service_account" "codemender_sa" {
  account_id   = "${var.prefix}-sa"
  display_name = "Codemender Service Account"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}

# Allow K8s Service Account to impersonate Google Service Account
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.codemender_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/codemender-sa]"
  depends_on         = [google_container_cluster.autopilot_cluster]
}

# ---------------------------------------------------------
# GCS Buckets for Codemender (Source and Output)
# ---------------------------------------------------------
resource "google_storage_bucket" "src_bucket" {
  name                        = "${var.prefix}-src-${formatdate("YYYYMMDDhhmmss", time_static.bucket_suffix.rfc3339)}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.services["storage.googleapis.com"]]
}

resource "google_storage_bucket" "out_bucket" {
  name                        = "${var.prefix}-out-${formatdate("YYYYMMDDhhmmss", time_static.bucket_suffix.rfc3339)}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.services["storage.googleapis.com"]]
}

# Grant the Codemender Service Account access to the source bucket
resource "google_storage_bucket_iam_member" "src_bucket_access" {
  bucket = google_storage_bucket.src_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.codemender_sa.email}"
}

# Grant the Codemender Service Account access to the output bucket
resource "google_storage_bucket_iam_member" "out_bucket_access" {
  bucket = google_storage_bucket.out_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.codemender_sa.email}"
}

# Grant project-level storage and Vertex AI permissions for Codemender pod
resource "google_project_iam_member" "codemender_sa_project_roles" {
  for_each = toset([
    "roles/storage.admin",
    "roles/aiplatform.user",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.codemender_sa.email}"
}

# Grant Cloud Build service account access to the source bucket for build staging
resource "google_storage_bucket_iam_member" "cloudbuild_sa_src_bucket_access" {
  bucket = google_storage_bucket.src_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# ---------------------------------------------------------
# Build & Push Container Image and Deploy K8s via Cloud Build
# ---------------------------------------------------------
resource "null_resource" "build_and_push_image" {
  triggers = {
    dockerfile_sha = filesha256("${path.module}/../k8s/Dockerfile")
    cloudbuild_sha = filesha256("${path.module}/../k8s/cloudbuild.yaml")
    k8s_sha        = sha256(join("", [for f in fileset("${path.module}/../k8s", "*.yaml") : filesha256("${path.module}/../k8s/${f}")]))
    image_name     = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}/codemender-worker:latest"
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = <<EOF
      set -e

      # Ensure default Cloud Build bucket access if present
      gcloud storage buckets add-iam-policy-binding "gs://${var.project_id}_cloudbuild" \
        --member="serviceAccount:${google_service_account.cloudbuild_sa.email}" \
        --role="roles/storage.admin" \
        --quiet 2>/dev/null || true

      # Submit build using dedicated service account and staging bucket
      gcloud builds submit \
        --config=k8s/cloudbuild.yaml \
        --service-account="projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild_sa.email}" \
        --gcs-source-staging-dir="gs://${google_storage_bucket.src_bucket.name}/build-source" \
        --substitutions=_IMAGE_NAME="${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}/codemender-worker:latest",_LOCATION="${var.region}",_SRC_BUCKET="${google_storage_bucket.src_bucket.name}",_OUT_BUCKET="${google_storage_bucket.out_bucket.name}",_CLUSTER_NAME="${google_container_cluster.autopilot_cluster.name}" \
        --project="${var.project_id}" \
        .
    EOF
  }

  depends_on = [
    google_project_service.services["cloudbuild.googleapis.com"],
    google_project_service.services["artifactregistry.googleapis.com"],
    google_project_service.services["storage.googleapis.com"],
    google_artifact_registry_repository.repo,
    google_artifact_registry_repository_iam_member.cloudbuild_sa_writer,
    google_service_account.cloudbuild_sa,
    google_project_iam_member.cloudbuild_sa_roles,
    google_service_account_iam_member.cloudbuild_sa_token_creator,
    google_service_account_iam_member.cloudbuild_sa_user,
    google_storage_bucket.src_bucket,
    google_storage_bucket_iam_member.cloudbuild_sa_src_bucket_access,
    google_container_cluster.autopilot_cluster,
    null_resource.enable_agent_sandbox,
  ]
}

# ---------------------------------------------------------
# Optional: VPC Service Controls Service Perimeter
# ---------------------------------------------------------
resource "google_access_context_manager_service_perimeter" "sandbox_perimeter" {
  count = var.enable_vpc_sc && var.access_policy_id != "" ? 1 : 0

  parent = "accessPolicies/${var.access_policy_id}"
  name   = "accessPolicies/${var.access_policy_id}/servicePerimeters/${replace(var.prefix, "-", "_")}_perimeter"
  title  = "${var.prefix} Service Perimeter"

  status {
    resources = [
      "projects/${data.google_project.project.number}"
    ]

    restricted_services = [
      "storage.googleapis.com",
      "artifactregistry.googleapis.com",
      "aiplatform.googleapis.com",
      "container.googleapis.com",
      "cloudbuild.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
    ]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services = [
        "storage.googleapis.com",
        "artifactregistry.googleapis.com",
        "aiplatform.googleapis.com",
        "container.googleapis.com",
        "cloudbuild.googleapis.com",
        "logging.googleapis.com",
        "monitoring.googleapis.com",
      ]
    }
  }

  depends_on = [
    google_project_service.services,
    google_compute_network.vpc_network,
  ]
}
