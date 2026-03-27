variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west4"
}

variable "bucket_name" {
  description = "GCS bucket name for raw weather data"
  type        = string
}

variable "cities" {
  description = "List of cities to collect weather data for"
  type        = list(string)
  default     = [
    "London",
    "Oslo",
    "Paris",
    "Berlin",
    "Amsterdam"
  ]
}