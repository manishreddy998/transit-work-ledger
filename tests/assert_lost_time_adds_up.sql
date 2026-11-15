-- The route-day ledger must account for every lost minute on a placed route, no more, no less.
select (select sum(lost_minutes) from {{ ref('fct_delay_event') }} where route_id is not null) as events_total,
       (select sum(lost_minutes) from {{ ref('fct_route_day') }}) as ledger_total
where events_total <> ledger_total
