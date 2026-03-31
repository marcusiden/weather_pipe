with staging as (
    select * from {{ ref('stg_weather_daily') }}
),

final as (
    select
        -- identity
        city,
        weather_date,
        latitude,
        longitude,
        elevation,

        -- temperatures
        temp_max_c,
        temp_min_c,
        temp_avg_c,

        -- precipitation
        precipitation_mm,
        CASE
            WHEN precipitation_mm = 0    THEN 'None'
            WHEN precipitation_mm < 1    THEN 'Trace'
            WHEN precipitation_mm < 5    THEN 'Light'
            WHEN precipitation_mm < 20   THEN 'Moderate'
            ELSE                              'Heavy'
        END                                     as precipitation_category,

        -- wind
        windspeed_max_kmh,
        CASE
            WHEN windspeed_max_kmh < 20  THEN 'Calm'
            WHEN windspeed_max_kmh < 40  THEN 'Breezy'
            WHEN windspeed_max_kmh < 60  THEN 'Windy'
            ELSE                              'Storm'
        END                                     as wind_category,

        -- weather description from WMO weathercode
        weathercode,
        CASE
            WHEN weathercode = 0         THEN 'Clear sky'
            WHEN weathercode IN (1,2,3)  THEN 'Partly cloudy'
            WHEN weathercode IN (45,48)  THEN 'Foggy'
            WHEN weathercode IN (51,53,55) THEN 'Drizzle'
            WHEN weathercode IN (61,63,65) THEN 'Rain'
            WHEN weathercode IN (71,73,75) THEN 'Snow'
            WHEN weathercode IN (80,81,82) THEN 'Rain showers'
            WHEN weathercode IN (85,86)  THEN 'Snow showers'
            WHEN weathercode IN (95,96,99) THEN 'Thunderstorm'
            ELSE                              'Other'
        END                                     as weather_description,

        -- metadata
        ingested_at

    from staging
)

select * from final
order by weather_date desc, city