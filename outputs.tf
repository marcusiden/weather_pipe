output "bucket_url" {
  description = "GCS bucket URL for raw weather data"
  value       = google_storage_bucket.raw_weather.url
}

output "raw_dataset_id" {
  description = "BigQuery raw dataset ID"
  value       = google_bigquery_dataset.raw_weather.dataset_id
}

output "analytics_dataset_id" {
  description = "BigQuery analytics dataset ID"
  value       = google_bigquery_dataset.analytics_weather.dataset_id
}

output "service_account_email" {
  description = "Service account email for the pipeline"
  value       = google_service_account.weather_pipeline.email
}