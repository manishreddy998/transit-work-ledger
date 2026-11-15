-- One row per scheduled trip with its scheduled duration. Day type comes from the GTFS calendar.
with times as (
    select trip_id, min({{ gtfs_seconds('departure_time') }}) as start_s, max({{ gtfs_seconds('arrival_time') }}) as end_s
    from {{ source('raw_gtfs', 'stop_times') }} group by 1
)
select t.trip_id, t.route_id, t.service_id,
       case when c.monday = '1' then 'weekday' when c.saturday = '1' then 'saturday' when c.sunday = '1' then 'sunday' end as day_type,
       (s.end_s - s.start_s) / 3600.0 as scheduled_hours
from {{ source('raw_gtfs', 'trips') }} t
join times s using (trip_id)
left join {{ source('raw_gtfs', 'calendar') }} c using (service_id)
