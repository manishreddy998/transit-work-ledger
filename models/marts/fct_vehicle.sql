-- One row per vehicle that appears in the logs: how much time it cost, and how much of that was its own equipment.
-- Events with no vehicle number are not here. They are counted in the data quality report instead of a fake vehicle 0.
with e as (select * from {{ ref('fct_delay_event') }} where vehicle_number is not null),
eq as (
    select mode, vehicle_number, event_date,
           event_date - lag(event_date) over (partition by mode, vehicle_number order by event_date, event_time) as days_since_last_fault
    from e where cause_group = 'vehicle_equipment' and not is_zero_delay
)
select e.mode, e.vehicle_number,
       count(*) as delay_events,
       sum(e.lost_minutes) as lost_minutes,
       count(*) filter (where e.cause_group = 'vehicle_equipment' and not e.is_zero_delay) as equipment_faults,
       sum(e.delay_minutes) filter (where e.cause_group = 'vehicle_equipment') as equipment_minutes,
       (select count(*) from eq where eq.mode = e.mode and eq.vehicle_number = e.vehicle_number
          and eq.days_since_last_fault <= {{ var('repeat_fault_days') }}) as repeat_faults,
       count(distinct e.route_id) as routes_served,
       min(e.event_date) as first_seen, max(e.event_date) as last_seen
from e group by 1, 2
