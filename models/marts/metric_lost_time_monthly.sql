-- Minutes lost per month by mode and cause group. Zero-minute events are incidents that cost no time.
select date_trunc('month', event_date)::date as month, mode, cause_group,
       bool_and(counts_as_lost_time) as counts_as_lost_time, bool_and(within_ttc_control) as within_ttc_control,
       count(*) as events, sum(delay_minutes) as logged_minutes, round(sum(lost_minutes) / 60.0, 1) as lost_hours
from {{ ref('fct_delay_event') }}
group by 1, 2, 3
