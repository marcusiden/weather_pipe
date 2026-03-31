# Weather Data Pipeline

An end-to-end data pipeline that ingests daily weather data for five Norwegian cities, stores it in BigQuery, and transforms it with dbt — with all GCP infrastructure provisioned via Terraform.

Built as a learning project to develop production-level data engineering skills across infrastructure as code, serverless compute, and the modern data stack.

---

## Pipeline Architecture
```
Open-Meteo API (free, no auth)
        ↓
Cloud Function (Python)     ← triggered daily at 6am UTC by Cloud Scheduler
        ↓
GCS Bucket                  ← raw JSON files organised by date
        ↓
BigQuery (raw_weather)      ← raw daily weather table
        ↓
dbt Cloud
├── staging/stg_weather_daily    → clean, deduplicate, extract STRUCT fields
└── marts/fct_weather_daily      → enrich with weather descriptions and categories
        ↓
BigQuery (analytics_weather)     ← final analytics table
```

---

## Cities

| City | Country | Latitude | Longitude |
|------|---------|----------|-----------|
| Oslo | Norway | 59.91 | 10.75 |
| Bergen | Norway | 60.39 | 5.32 |
| Trondheim | Norway | 63.43 | 10.40 |
| Stavanger | Norway | 58.97 | 5.73 |
| Tromsø | Norway | 69.65 | 18.96 |

---

## Tech Stack

| Layer | Tool |
|-------|------|
| Infrastructure as Code | Terraform |
| Cloud Platform | GCP |
| Raw Storage | Google Cloud Storage |
| Data Warehouse | BigQuery |
| Serverless Compute | Cloud Functions (Python 3.11) |
| Scheduling | Cloud Scheduler |
| Transformation | dbt Cloud |
| Version Control | GitHub |

---

## Infrastructure (Terraform)

All GCP resources are provisioned via Terraform — nothing is created manually through the GCP Console.

**Resources provisioned:**
- GCS bucket (`weather-pipeline-raw-marcus`) with 90-day lifecycle rule
- BigQuery datasets (`raw_weather`, `analytics_weather`) in `europe-west4`
- Service account (`weather-pipeline-sa`) with least-privilege IAM roles
- Cloud Function (`ingest-weather`) deployed to `europe-west1`
- Cloud Scheduler job (`daily-weather-ingest`) — triggers at `0 6 * * *` UTC
- GCP API enablements (Cloud Functions, Cloud Build, Cloud Run, Cloud Scheduler)

**To provision from scratch:**
```bash
terraform init
terraform plan
terraform apply
```

**To tear everything down:**
```bash
terraform destroy
```

---

## Data Flow

**1. Ingestion (Cloud Function)**

The Cloud Function calls the [Open-Meteo API](https://open-meteo.com/) for each city, fetches today's forecast, adds city metadata and an ingestion timestamp, writes the raw JSON to GCS, and loads it directly into BigQuery.

Files are stored in GCS as:
```
gs://weather-pipeline-raw-marcus/raw/YYYY-MM-DD/city.json
```

**2. Staging (dbt)**

`stg_weather_daily` cleans the raw data:
- Deduplicates rows using `ROW_NUMBER()` — keeps the most recent ingestion per city per day
- Extracts values from BigQuery STRUCT arrays using `[0]` indexing
- Calculates `temp_avg_c` from max and min temperatures
- Renames columns to snake_case

**3. Marts (dbt)**

`fct_weather_daily` enriches the data:
- Adds `weather_description` from WMO weathercodes (e.g. code 61 → "Rain")
- Adds `precipitation_category` (None / Trace / Light / Moderate / Heavy)
- Adds `wind_category` (Calm / Breezy / Windy / Storm)

---

## Sample Output

| city | weather_date | temp_max_c | temp_min_c | precipitation_mm | precipitation_category | wind_category | weather_description |
|------|-------------|------------|------------|-----------------|----------------------|---------------|-------------------|
| Bergen | 2026-03-31 | 7.9 | 4.6 | 3.9 | Light | Breezy | Rain |
| Oslo | 2026-03-31 | 12.8 | 1.7 | 0.0 | None | Calm | Partly cloudy |
| Stavanger | 2026-03-31 | 8.2 | 4.5 | 0.4 | Trace | Breezy | Drizzle |
| Tromsø | 2026-03-31 | 6.1 | 1.1 | 2.5 | Light | Breezy | Drizzle |
| Trondheim | 2026-03-31 | 9.8 | 1.2 | 4.3 | Light | Breezy | Rain |

---

## Repository Structure
```
weather-pipe/
├── README.md
├── main.tf                 ← all GCP resources
├── variables.tf            ← variable declarations
├── outputs.tf              ← output values after apply
├── terraform.tfvars        ← variable values (gitignored)
├── .gitignore
├── function/
│   ├── main.py             ← Cloud Function Python code
│   └── requirements.txt    ← Python dependencies
└── models/
    ├── staging/
    │   ├── sources.yml
    │   └── stg_weather_daily.sql
    └── marts/
        └── fct_weather_daily.sql
```

---

## Setup

### Prerequisites
- GCP project with billing enabled
- Terraform v1.0+
- Google Cloud SDK (`gcloud`) installed and authenticated
- dbt Cloud account

### Steps

**1. Authenticate with GCP**
```bash
gcloud auth application-default login
```

**2. Configure variables**

Create `terraform.tfvars`:
```hcl
project_id  = "your-gcp-project-id"
region      = "europe-west4"
bucket_name = "your-bucket-name"
```

**3. Provision infrastructure**
```bash
terraform init
terraform plan
terraform apply
```

**4. Test the Cloud Function**
```bash
gcloud functions call ingest-weather --region=europe-west1
```

**5. Connect dbt Cloud**
- Create a new dbt Cloud project
- Connect to BigQuery using the `weather-pipeline-sa` service account
- Set dataset to `analytics_weather`
- Run `dbt run`

---

## Key Learnings

**Terraform state** — Terraform tracks every resource it manages in a state file. This is how it knows what already exists and what needs to be created, updated, or destroyed. Always run `terraform plan` before `terraform apply`.

**Serverless vs always-on** — Cloud Functions costs nothing when idle and handles our single daily invocation for effectively free. A VM running 24/7 would cost ~$15-30/month for the same job.

**Region constraints** — Not all GCP services are available in all regions. Cloud Functions isn't available in `europe-west4` due to org policy, so the function and scheduler use `europe-west1` while storage and BigQuery remain in `europe-west4`. Mixing regions within a project is a real-world pattern.

**STRUCT vs JSON** — BigQuery autodetected the nested `daily` object as a STRUCT type rather than a raw JSON string. STRUCT fields are accessed with dot notation (`daily.temperature_2m_max[0]`) rather than `JSON_VALUE()`.

**Deduplication** — With `WRITE_APPEND` load mode, re-running the function on the same day creates duplicate rows. The staging model handles this with `ROW_NUMBER()` keeping only the latest ingestion per city per date.

---

## Author

Marcus Iden — Data Engineer at Sopra Steria
[github.com/marcusiden](https://github.com/marcusiden)