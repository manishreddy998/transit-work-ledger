select 'bus' as mode, upper(trim(CODE)) as code, {{ fix_mojibake('DESCRIPTION') }} as description from {{ source('raw_delays', 'bus_codes') }}
union all
select 'streetcar', upper(trim(CODE)), {{ fix_mojibake('DESCRIPTION') }} from {{ source('raw_delays', 'streetcar_codes') }}
union all
select 'subway', upper(trim(CODE)), {{ fix_mojibake('DESCRIPTION') }} from {{ source('raw_delays', 'subway_codes') }}
