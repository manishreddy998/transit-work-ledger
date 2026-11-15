-- Which timetable route does each logged line value mean? One row per distinct (mode, line text), with the rule used.
-- A value that cannot be placed keeps an empty route and a reason. Nothing is guessed.
{% set generic = "('ROAD','AVENUE','STREET','EXPRESS','WEST','EAST','NORTH','SOUTH','LINE','THE','AND','NIGHT','BLUE','SHUTTLE','STATION','BRANCH')" %}
with lines as (
    select mode, line_text, count(*) as n_events from {{ ref('stg_delays') }} group by 1, 2
),
routes as (select * from {{ ref('stg_routes') }}),
parsed as (
    select l.*,
        regexp_extract(line_text, '^([0-9]+)[A-Z]?\b', 1)                                       as num,
        list_filter(string_split(regexp_replace(regexp_replace(coalesce(line_text, ''), '^[0-9]+[A-Z]?\b', ''), '[^A-Z ]', ' ', 'g'), ' '),
                    lambda w: length(w) >= 3 and w not in {{ generic }})                          as words,
        regexp_matches(coalesce(line_text, ''), '&|/| AND [0-9]')                                as lists_several
    from lines l
),
name_hits as (   -- which routes of the same mode share a significant word with the logged text
    select p.mode, p.line_text, r.route_id, r.route_short_name
    from parsed p join routes r on len(list_intersect(p.words, r.name_words)) > 0
),
decided as (
    select p.*,
        r.route_id as num_route_id, r.mode as num_route_mode,
        sl.route_short_name as subway_num,
        npr.reason as not_public_reason,
        regexp_extract(p.line_text, '^LINE ([0-9]) SHUTTLE', 1) as shuttle_line,
        (select count(*) from name_hits h where h.mode = p.mode and h.line_text = p.line_text and h.route_id = r.route_id) > 0 as name_agrees,
        (select count(distinct h.route_id) from name_hits h join routes rr on rr.route_id = h.route_id
          where h.mode = p.mode and h.line_text = p.line_text and rr.mode = p.mode) as name_route_count,
        (select min(h.route_id) from name_hits h join routes rr on rr.route_id = h.route_id
          where h.mode = p.mode and h.line_text = p.line_text and rr.mode = p.mode) as name_route_id
    from parsed p
    left join routes r on r.route_short_name = p.num
    left join {{ ref('subway_lines') }} sl on p.mode = 'subway' and sl.line_code = p.line_text
    left join {{ ref('not_public_routes') }} npr on npr.line_text = p.line_text or npr.line_text = p.num
),

select
    mode, line_text, n_events,
    case
        when line_text is null                                    then null
        when subway_num is not null                               then (select route_id from routes where route_short_name = subway_num)
        when shuttle_line <> ''                                   then (select route_id from routes where route_short_name = shuttle_line)
        when not_public_reason is not null                        then null
        when num_route_id is not null and lists_several           then null
        when num_route_id is not null and len(words) = 0          then num_route_id
        when num_route_id is not null and name_agrees             then num_route_id
        when num_route_id is not null and name_route_count = 1    then null      -- the number says one route, the name another
        when num_route_id is not null                             then num_route_id
        when num = '' and name_route_count = 1                    then name_route_id
    end as route_id,
    case
        when line_text is null                                    then 'missing'
        when subway_num is not null                               then 'subway_line_code'
        when mode = 'subway' and line_text like '%/%'             then 'several_routes_listed'
        when shuttle_line <> ''                                   then 'shuttle_replacing_subway'
        when not_public_reason is not null                        then 'not_a_public_route'
        when num_route_id is not null and lists_several           then 'several_routes_listed'
        when num_route_id is not null and len(words) = 0          then 'number_only'
        when num_route_id is not null and name_agrees             then 'number_and_name'
        when num_route_id is not null and name_route_count = 1    then 'number_name_conflict'
        when num_route_id is not null                             then 'number_with_unmatched_name'
        when num = '' and name_route_count = 1                    then 'name_only'
        when num <> ''                                            then 'number_not_in_timetable'
        else 'unresolved'
    end as rule,
    num_route_mode is not null and num_route_mode <> mode and subway_num is null and shuttle_line = '' as other_mode_vehicle,
    not_public_reason
from decided
