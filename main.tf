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

# ── Cloud Function ───────────────────────────────────────────────────────────

# enable required APIs
resource "google_project_service" "cloudfunctions" {
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# zip the function code
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

# upload zip to GCS
resource "google_storage_bucket_object" "function_zip" {
  name   = "function/ingest_weather_${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.raw_weather.name
  source = data.archive_file.function_zip.output_path

  depends_on = [data.archive_file.function_zip]
}

# deploy the cloud function
resource "google_cloudfunctions_function" "ingest_weather" {
  name        = "ingest-weather"
  description = "Fetches daily weather data for Norwegian cities and loads to GCS"
  runtime     = "python311"
  region      = var.function_region

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.raw_weather.name
  source_archive_object = google_storage_bucket_object.function_zip.name
  trigger_http          = true
  entry_point           = "ingest_weather"
  timeout               = 120

  environment_variables = {
    BUCKET_NAME = var.bucket_name
  }

  service_account_email = google_service_account.weather_pipeline.email

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run
  ]
}

# allow the function to be invoked
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.function_region
  cloud_function = google_cloudfunctions_function.ingest_weather.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.weather_pipeline.email}"
}

# ── Cloud Scheduler ──────────────────────────────────────────────────────────

resource "google_project_service" "scheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_cloud_scheduler_job" "daily_weather" {
  name        = "daily-weather-ingest"
  description = "Triggers weather ingestion function every day at 6am UTC"
  schedule    = "0 6 * * *"
  time_zone   = "UTC"
  region      = var.function_region

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.ingest_weather.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.weather_pipeline.email
    }
  }

  depends_on = [google_project_service.scheduler]
}