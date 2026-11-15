-- One row per check on the raw logs: how many events it touches and what the pipeline did about it.
with e as (select * from {{ ref('int_events') }}),
total as (select count(*) as n from e)
select check_name, events,
       case when check_name like 'code descriptions%' then null else round(100.0 * events / (select n from total), 2) end as pct_of_events, action from (
    select 'exact duplicate log lines' as check_name, count(*) filter (where is_duplicate) as events, 'kept once' as action from e
    union all select 'no vehicle number (0 or blank)', count(*) filter (where vehicle_number is null), 'vehicle left empty, not counted as an asset' from e
    union all select 'line value missing', count(*) filter (where line_text is null), 'route left empty' from e
    union all select 'line value not placed on a route', count(*) filter (where line_text is not null and route_id is null), 'route left empty, listed in review queue' from e
    union all select 'code not in the published code list', count(*) filter (where not coalesce(in_code_list, false)), 'cause taken from the code prefix and marked' from e
    union all select 'zero-minute events', count(*) filter (where is_zero_delay), 'kept as incidents, add no lost time' from e
    union all select 'single events over {{ var("extreme_delay_minutes") }} minutes', count(*) filter (where is_extreme), 'kept, listed in review queue' from e
    union all select 'bus or streetcar running another mode''s route', count(*) filter (where other_mode_vehicle), 'counted on the route it ran' from e
    union all select 'code descriptions with broken characters (count of codes, not events)', (select count(*) from {{ ref('stg_delay_codes') }} where description like '% - %'), 'repaired (en dash)'
)
