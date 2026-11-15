-- Cause group for every code that appears in the logs. A description rule wins over the code prefix.
-- Codes missing from the published code list still get a group from their prefix, marked as such.
with used as (select distinct mode, code from {{ ref('stg_delays') }} where code is not null),
described as (
    select u.mode, u.code, c.description,
        (select r.cause_group from {{ ref('cause_rules') }} r
          where c.description is not null and regexp_matches(c.description, r.pattern) order by r.priority limit 1) as rule_group,
        p.cause_group as prefix_group
    from used u
    left join {{ ref('stg_delay_codes') }} c on c.mode = u.mode and c.code = u.code
    left join {{ ref('cause_prefix') }} p on p.prefix = left(u.code, 1)
)
select mode, code, description,
    coalesce(rule_group, prefix_group, 'unknown') as cause_group,
    case when rule_group is not null then 'description_rule'
         when description is not null and prefix_group is not null then 'code_prefix'
         when prefix_group is not null then 'prefix_only_code_not_in_list'
         else 'unknown_code' end as cause_rule,
    description is not null as in_code_list
from described
