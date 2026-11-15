-- Real cases from the TTC logs, checked by hand. Each row returned is a case the rules now get wrong.
with checks as (
    -- the number says route 52 (Lawrence West), the name says Burnhamthorpe: leave it empty, do not pick
    select '52 BURNHAMTHORPE stays unplaced' as case_name,
           (select route_id is null and rule = 'number_name_conflict' from {{ ref('int_line_resolution') }} where mode = 'bus' and line_text = '52 BURNHAMTHORPE') as ok
    union all
    select 'LINE 1 SHUTTLE counts against Line 1',
           (select route_id = '1' from {{ ref('int_line_resolution') }} where mode = 'bus' and line_text = 'LINE 1 SHUTTLE')
    union all
    select 'bus on 504 King is a bus on a streetcar route',
           (select route_id = '504' and other_mode_vehicle from {{ ref('int_line_resolution') }} where mode = 'bus' and line_text = '504 KING')
    union all
    select 'two lines listed stays unplaced',
           (select route_id is null from {{ ref('int_line_resolution') }} where mode = 'bus' and line_text = '52 LAWRENCE WEST & 952')
    union all
    select 'no vehicle 0 exists', not exists (select 1 from {{ ref('fct_vehicle') }} where vehicle_number = '0')
    union all
    select 'diversion minutes are not lost time', not exists (select 1 from {{ ref('fct_delay_event') }} where cause_group = 'diversion' and lost_minutes > 0)
    union all
    select 'no-operator codes are staffing', (select cause_group = 'staffing' from {{ ref('int_causes') }} where mode = 'bus' and code = 'MFESA')
    union all
    select 'broken en dash repaired', not exists (select 1 from {{ ref('stg_delay_codes') }} where description like '%â%')
)
select case_name from checks where not coalesce(ok, false)
