import functions_framework
import requests
import json
import os
from datetime import datetime, timezone
from google.cloud import storage

# cities with their coordinates for Open-Meteo API
CITIES = {
    "Oslo":          {"latitude": 59.9139, "longitude": 10.7522},
    "Bergen":        {"latitude": 60.3913, "longitude": 5.3221},
    "Trondheim":     {"latitude": 63.4305, "longitude": 10.3951},
    "Stavanger":     {"latitude": 58.9700, "longitude": 5.7331},
    "Tromsø":        {"latitude": 69.6489, "longitude": 18.9551},
}

BUCKET_NAME = os.environ.get("BUCKET_NAME", "weather-pipeline-raw-marcus")

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
        json.dumps(data, indent=2),
        content_type="application/json"
    )
    print(f"Uploaded {blob_path} to GCS")

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
            
            upload_to_gcs(weather_data, city, today)
            results.append({"city": city, "status": "success"})

        except Exception as e:
            print(f"Error fetching weather for {city}: {e}")
            results.append({"city": city, "status": "error", "error": str(e)})

    return json.dumps({"date": today, "results": results}), 200