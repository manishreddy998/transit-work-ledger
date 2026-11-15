-- What a person should look at, with the reason. Grouped so a value seen 849 times is one row, not 849.
select 'line_not_placed' as issue, mode, line_text as subject, rule as detail, n_events as events
from {{ ref('int_line_resolution') }}
where route_id is null and rule <> 'not_a_public_route'
union all
select 'code_not_in_code_list', mode, code, coalesce(cause_group, 'unknown') || ' (from prefix)', count(*)
from {{ ref('fct_delay_event') }} where not coalesce(in_code_list, false) and code is not null group by 1, 2, 3, 4
union all
select 'extreme_single_event', mode, event_id, coalesce(code_description, code) || ', ' || delay_minutes || ' min', 1
from {{ ref('fct_delay_event') }} where is_extreme and cause_group not in ('diversion', 'redeployed')
union all
select 'vehicle_repeat_faults', mode, vehicle_number, repeat_faults || ' equipment faults within {{ var("repeat_fault_days") }} days of the previous one', equipment_faults
from {{ ref('fct_vehicle') }} where repeat_faults >= 20
