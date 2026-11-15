select route_id, route_short_name, route_long_name,
       case route_type when '0' then 'streetcar' when '1' then 'subway' when '3' then 'bus' else 'other' end as mode,
       -- significant words of the route name, used to check a logged line name against the timetable
       list_filter(string_split(upper(regexp_replace(route_long_name, '[^A-Za-z ]', ' ', 'g')), ' '),
                   lambda w: length(w) >= 3 and w not in ('ROAD', 'AVENUE', 'STREET', 'EXPRESS', 'WEST', 'EAST', 'NORTH', 'SOUTH',
                                                          'LINE', 'THE', 'AND', 'NIGHT', 'BLUE', 'SHUTTLE')) as name_words
from {{ source('raw_gtfs', 'routes') }}
