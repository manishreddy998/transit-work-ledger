-- The cleaned event log: one row per real delay event (exact repeats removed), with route, cause and the rule behind each.
select e.event_id, e.mode, e.event_date, e.event_time, e.route_id, e.line_text, e.line_rule, e.other_mode_vehicle,
       e.station_text, e.code, e.code_description, coalesce(e.cause_group, 'unknown') as cause_group, e.cause_rule, e.in_code_list,
       e.delay_minutes, e.gap_minutes, e.direction, e.vehicle_number, e.is_zero_delay, e.is_extreme,
       coalesce(g.counts_as_lost_time, true) as counts_as_lost_time, coalesce(g.within_ttc_control, false) as within_ttc_control,
       case when coalesce(g.counts_as_lost_time, true) then coalesce(e.delay_minutes, 0) else 0 end as lost_minutes
from {{ ref('int_events') }} e
left join {{ ref('cause_groups') }} g on g.cause_group = coalesce(e.cause_group, 'unknown')
where not e.is_duplicate
