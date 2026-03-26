terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── GCS Bucket ──────────────────────────────────────────────────────────────

resource "google_storage_bucket" "raw_weather" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# ── BigQuery Datasets ────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "raw_weather" {
  dataset_id    = "raw_weather"
  friendly_name = "Raw Weather Data"
  description   = "Raw daily weather data ingested from Open-Meteo API"
  location      = var.region
}

resource "google_bigquery_dataset" "analytics_weather" {
  dataset_id    = "analytics_weather"
  friendly_name = "Analytics Weather Data"
  description   = "Transformed weather data models from dbt"
  location      = var.region
}

# ── Service Account ──────────────────────────────────────────────────────────

resource "google_service_account" "weather_pipeline" {
  account_id   = "weather-pipeline-sa"
  display_name = "Weather Pipeline Service Account"
  description  = "Service account for the weather data pipeline"
}

# ── IAM Roles ────────────────────────────────────────────────────────────────

resource "google_project_iam_member" "bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.weather_pipeline.email}"
}

resource "google_project_iam_member" "bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.weather_pipeline.email}"
}

resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.weather_pipeline.email}"
}