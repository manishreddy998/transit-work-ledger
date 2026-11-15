-- All three delay logs in one shape. Nothing is resolved yet: the raw line text, code and vehicle are kept as logged.
with u as (
    select 'bus' as mode, _id, Date, Time, Line, Station, Code, "Min Delay", "Min Gap", Bound, Vehicle from {{ source('raw_delays', 'bus') }}
    union all
    select 'streetcar', _id, Date, Time, Line, Station, Code, "Min Delay", "Min Gap", Bound, Vehicle from {{ source('raw_delays', 'streetcar') }}
    union all
    select 'subway', _id, Date, Time, Line, Station, Code, "Min Delay", "Min Gap", Bound, Vehicle from {{ source('raw_delays', 'subway') }}
)
select
    mode || ':' || _id                                                   as event_id,
    mode,
    cast(left(Date, 10) as date)                                         as event_date,
    try_cast(Time as time)                                               as event_time,
    upper(trim(Line))                                                    as line_text,
    upper(trim(Station))                                                 as station_text,
    upper(trim(Code))                                                    as code,
    try_cast("Min Delay" as integer)                                     as delay_minutes,
    try_cast("Min Gap" as integer)                                       as gap_minutes,
    nullif(upper(trim(Bound)), '')                                       as direction,
    -- a vehicle number of 0 means "not recorded": keep it empty rather than invent an asset called 0
    case when try_cast(Vehicle as integer) > 0 then cast(try_cast(Vehicle as integer) as varchar) end as vehicle_number
from u
