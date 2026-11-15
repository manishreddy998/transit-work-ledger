-- Every delay event with its route, cause group and quality flags. Exact repeats of the same log line are marked.
with e as (select * from {{ ref('stg_delays') }}),
dups as (
    select event_id,
        row_number() over (partition by mode, event_date, event_time, line_text, station_text, code, delay_minutes, gap_minutes, direction, vehicle_number
                           order by event_id) as copy_number
    from e
)
select
    e.*, l.route_id, l.rule as line_rule, l.other_mode_vehicle,
    c.cause_group, c.cause_rule, c.description as code_description, c.in_code_list,
    d.copy_number > 1                                              as is_duplicate,
    coalesce(e.delay_minutes, 0) = 0                               as is_zero_delay,
    e.delay_minutes > {{ var('extreme_delay_minutes') }}          as is_extreme
from e
join dups d using (event_id)
left join {{ ref('int_line_resolution') }} l on l.mode = e.mode and l.line_text is not distinct from e.line_text
left join {{ ref('int_causes') }} c on c.mode = e.mode and c.code = e.code
