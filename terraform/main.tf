terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Data source to get the project number
data "google_project" "project" {
  project_id = var.gcp_project_id
}

# --- Services --- #
resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

# --- Artifact Registry --- #
resource "google_artifact_registry_repository" "n8n_repo" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = var.artifact_repo_name
  description   = "Repository for n8n workflow images"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry]
}

# --- Secret Manager --- #
# Secret Manager: n8n encryption key
resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "encryption_key_secret" {
  secret_id = "${var.cloud_run_service_name}-encryption-key"
  project   = var.gcp_project_id
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "encryption_key_secret_version" {
  secret      = google_secret_manager_secret.encryption_key_secret.id
  secret_data = random_password.n8n_encryption_key.result
}


# --- IAM Service Account & Permissions --- #
resource "google_service_account" "n8n_sa" {
  account_id   = var.service_account_name
  display_name = "n8n Service Account for Cloud Run"
  project      = var.gcp_project_id
}

resource "google_secret_manager_secret_iam_member" "encryption_key_secret_accessor" {
  project   = google_secret_manager_secret.encryption_key_secret.project
  secret_id = google_secret_manager_secret.encryption_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_sa.email}"
}


# Cloud Build service account permissions
resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.gcp_project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  depends_on = [google_project_service.cloudbuild]
}

resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  depends_on = [google_project_service.cloudbuild]
}

# --- Cloud Run Service --- #
locals {
  # Construct the image name dynamically
  n8n_image_name = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.artifact_repo_name}/${var.cloud_run_service_name}:latest"
}

resource "google_cloud_run_v2_service" "n8n" {
  name     = var.cloud_run_service_name
  location = var.gcp_region
  project  = var.gcp_project_id

  ingress             = "INGRESS_TRAFFIC_ALL" # Allow unauthenticated
  deletion_protection = false

  template {
    service_account = google_service_account.n8n_sa.email
    scaling {
      max_instance_count = var.cloud_run_max_instances
      min_instance_count = 0
    }
    
    containers {
      image = local.n8n_image_name
      
      ports {
        container_port = var.cloud_run_container_port
      }
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        startup_cpu_boost = true
      }
      
      # Basic n8n configuration
      env {
        name  = "N8N_PATH"
        value = "/"
      }
      
      env {
        name  = "N8N_PORT"
        value = "5678"
      }
      
      env {
        name  = "N8N_PROTOCOL"
        value = "https"
      }
      
      
      env {
        name = "N8N_ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.encryption_key_secret.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name = "N8N_HOST"
        value = "${var.cloud_run_service_name}-${data.google_project.project.number}.${var.gcp_region}.run.app"
      }
      
      env {
        name = "N8N_WEBHOOK_URL"
        value = "https://${var.cloud_run_service_name}-${data.google_project.project.number}.${var.gcp_region}.run.app"
      }
      
      env {
        name = "N8N_EDITOR_BASE_URL"
        value = "https://${var.cloud_run_service_name}-${data.google_project.project.number}.${var.gcp_region}.run.app"
      }
      
      env {
        name = "WEBHOOK_URL"
        value = "https://${var.cloud_run_service_name}-${data.google_project.project.number}.${var.gcp_region}.run.app"
      }
      
      env {
        name  = "N8N_USER_FOLDER"
        value = "/home/node/.n8n"
      }
      
      env {
        name  = "GENERIC_TIMEZONE"
        value = var.generic_timezone
      }
      
      env {
        name  = "QUEUE_HEALTH_CHECK_ACTIVE"
        value = "true"
      }
      
      env {
        name  = "N8N_RUNNERS_ENABLED"
        value = "true"
      }
      
      env {
        name  = "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS"
        value = "true"
      }
      
      env {
        name  = "N8N_DIAGNOSTICS_ENABLED"
        value = "false"
      }
      
      env {
        name  = "EXECUTIONS_PROCESS"
        value = "main"
      }
      
      env {
        name  = "EXECUTIONS_MODE"
        value = "regular"
      }
      
      env {
        name  = "N8N_LOG_LEVEL"
        value = "info"
      }
      
      # SQLite configuration
      env {
        name  = "DB_SQLITE_POOL_SIZE"
        value = "3"
      }
      
      # Security settings
      env {
        name  = "N8N_BLOCK_ENV_ACCESS_IN_NODE"
        value = "false"
      }
      

      startup_probe {
        initial_delay_seconds = 120
        timeout_seconds       = 240
        period_seconds        = 10
        failure_threshold     = 3
        tcp_socket {
          port = var.cloud_run_container_port
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.encryption_key_secret_accessor,
    google_artifact_registry_repository.n8n_repo
  ]
}

# Grant public access to the Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "n8n_public_invoker" {
  project  = google_cloud_run_v2_service.n8n.project
  location = google_cloud_run_v2_service.n8n.location
  name     = google_cloud_run_v2_service.n8n.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}