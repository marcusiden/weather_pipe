with source as (
    select * from {{ source('raw_weather', 'daily_weather') }}
),

deduplicated as (
    select *,
        row_number() over (
            partition by city, DATE(ingested_at)
            order by ingested_at desc
        ) as row_num
    from source
),

renamed as (
    select
        -- identity
        city,
        DATE(ingested_at)                       as weather_date,
        ingested_at,
        latitude,
        longitude,
        elevation,

        -- weather measurements
        daily.temperature_2m_max[0]             as temp_max_c,
        daily.temperature_2m_min[0]             as temp_min_c,
        ROUND((daily.temperature_2m_max[0] + daily.temperature_2m_min[0]) / 2, 1)
                                                as temp_avg_c,
        daily.precipitation_sum[0]              as precipitation_mm,
        daily.windspeed_10m_max[0]              as windspeed_max_kmh,
        daily.weathercode[0]                    as weathercode

    from deduplicated
    where row_num = 1
)

select * from renamed