import functions_framework
import requests
import json
import os
from datetime import datetime, timezone
from google.cloud import storage
from google.cloud import bigquery

# cities with their coordinates for Open-Meteo API
CITIES = {
    "Oslo":      {"latitude": 59.9139, "longitude": 10.7522},
    "Bergen":    {"latitude": 60.3913, "longitude": 5.3221},
    "Trondheim": {"latitude": 63.4305, "longitude": 10.3951},
    "Stavanger": {"latitude": 58.9700, "longitude": 5.7331},
    "Tromsø":    {"latitude": 69.6489, "longitude": 18.9551},
}

BUCKET_NAME = os.environ.get("BUCKET_NAME", "weather-pipeline-raw-marcus")
PROJECT_ID  = os.environ.get("PROJECT_ID", "no-ssg-gcp-miden-isnd")
DATASET_ID  = os.environ.get("DATASET_ID", "raw_weather")
TABLE_ID    = os.environ.get("TABLE_ID", "daily_weather")

def fetch_weather(city, lat, lon):
    """Fetch daily weather data for a city from Open-Meteo API."""
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": lat,
        "longitude": lon,
        "daily": [
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "windspeed_10m_max",
            "weathercode"
        ],
        "timezone": "Europe/London",
        "forecast_days": 1
    }
    response = requests.get(url, params=params, timeout=10)
    response.raise_for_status()
    return response.json()

def upload_to_gcs(data, city, date_str):
    """Upload weather data as JSON to GCS."""
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blob_path = f"raw/{date_str}/{city.lower()}.json"
    blob = bucket.blob(blob_path)
    blob.upload_from_string(
        json.dumps(data),
        content_type="application/json"
    )
    print(f"Uploaded {blob_path} to GCS")
    return f"gs://{BUCKET_NAME}/{blob_path}"

def load_to_bigquery(gcs_uri):
    """Load JSON file from GCS into BigQuery."""
    client = bigquery.Client(project=PROJECT_ID)
    table_ref = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        schema_update_options=[
            bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION
        ]
    )

    load_job = client.load_table_from_uri(
        gcs_uri, table_ref, job_config=job_config
    )
    load_job.result()
    print(f"Loaded {gcs_uri} into {table_ref}")

@functions_framework.http
def ingest_weather(request):
    """Main Cloud Function entry point — triggered by HTTP request."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    results = []

    for city, coords in CITIES.items():
        try:
            print(f"Fetching weather for {city}...")
            weather_data = fetch_weather(city, coords["latitude"], coords["longitude"])

            # add metadata
            weather_data["city"] = city
            weather_data["ingested_at"] = datetime.now(timezone.utc).isoformat()

            # write to GCS
            gcs_uri = upload_to_gcs(weather_data, city, today)

            # load to BigQuery
            load_to_bigquery(gcs_uri)

            results.append({"city": city, "status": "success"})

        except Exception as e:
            print(f"Error processing {city}: {e}")
            results.append({"city": city, "status": "error", "error": str(e)})

    return json.dumps({"date": today, "results": results}), 200
