{# GTFS times can pass midnight (25:10:00 is 1:10 AM the next service day), so parse to seconds, not to a clock time. #}
{% macro gtfs_seconds(col) %}(cast(split_part({{ col }}, ':', 1) as integer) * 3600 + cast(split_part({{ col }}, ':', 2) as integer) * 60 + cast(split_part({{ col }}, ':', 3) as integer)){% endmacro %}

{# The published code descriptions contain broken UTF-8 ("ILL CUSTOMER â TRANSPORTED" was an en dash). Repair, do not drop. #}
{% macro fix_mojibake(col) %}trim(regexp_replace(regexp_replace({{ col }}, 'â[\x80-\x9f]*', '-', 'g'), '\s+', ' ', 'g')){% endmacro %}
