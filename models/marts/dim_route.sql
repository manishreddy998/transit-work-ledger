-- One row per timetable route with its planned service, from the Nov 2026 GTFS timetable.
with plan as (
    select route_id,
        count(*) filter (where day_type = 'weekday')                 as weekday_trips,
        sum(scheduled_hours) filter (where day_type = 'weekday')     as weekday_vehicle_hours,
        sum(scheduled_hours) filter (where day_type = 'saturday')    as saturday_vehicle_hours,
        sum(scheduled_hours) filter (where day_type = 'sunday')      as sunday_vehicle_hours
    from {{ ref('stg_trips') }} group by 1
)
select r.route_id, r.route_short_name, r.route_long_name, r.mode,
       coalesce(p.weekday_trips, 0) as weekday_trips,
       round(coalesce(p.weekday_vehicle_hours, 0), 1)  as weekday_vehicle_hours,
       round(coalesce(p.saturday_vehicle_hours, 0), 1) as saturday_vehicle_hours,
       round(coalesce(p.sunday_vehicle_hours, 0), 1)   as sunday_vehicle_hours
from {{ ref('stg_routes') }} r left join plan p using (route_id)
