-- Value versus waste per route per day: the service the timetable plans, and the minutes delays took from it.
-- lost_minutes leaves out diversions and shuttle redeployments (see rules.cause_groups for why).
-- Planned hours come from the current timetable by day type, so they are a baseline, not the exact plan of a past day.
with days as (
    select cast(range as date) as service_date
    from range((select min(event_date) from {{ ref('fct_delay_event') }}), (select max(event_date) from {{ ref('fct_delay_event') }}) + 1, interval 1 day)
),
lost as (
    select route_id, event_date, count(*) as delay_events,
           count(*) filter (where not is_zero_delay) as events_with_delay,
           sum(delay_minutes) as logged_minutes,
           sum(lost_minutes) as lost_minutes,
           sum(lost_minutes) filter (where within_ttc_control) as lost_minutes_ttc_control,
           sum(delay_minutes) filter (where cause_group = 'vehicle_equipment') as equipment_minutes,
           sum(delay_minutes) filter (where cause_group = 'staffing') as staffing_minutes
    from {{ ref('fct_delay_event') }} where route_id is not null group by 1, 2
)
select r.route_id, r.route_short_name, r.route_long_name, r.mode, d.service_date,
       case when dayofweek(d.service_date) = 0 then 'sunday' when dayofweek(d.service_date) = 6 then 'saturday' else 'weekday' end as day_type,
       case when dayofweek(d.service_date) = 0 then r.sunday_vehicle_hours when dayofweek(d.service_date) = 6 then r.saturday_vehicle_hours
            else r.weekday_vehicle_hours end                                       as planned_vehicle_hours,
       coalesce(l.delay_events, 0) as delay_events, coalesce(l.events_with_delay, 0) as events_with_delay,
       coalesce(l.logged_minutes, 0) as logged_minutes, coalesce(l.lost_minutes, 0) as lost_minutes,
       coalesce(l.lost_minutes_ttc_control, 0) as lost_minutes_ttc_control,
       coalesce(l.equipment_minutes, 0) as equipment_minutes, coalesce(l.staffing_minutes, 0) as staffing_minutes
from {{ ref('dim_route') }} r
cross join days d
left join lost l on l.route_id = r.route_id and l.event_date = d.service_date
where r.weekday_vehicle_hours > 0 or l.route_id is not null
