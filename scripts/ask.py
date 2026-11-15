"""Ask the ledger a question in plain English. Claude answers only through read-only, parameterized SQL tools.

    python scripts/ask.py "Which streetcar route lost the most service in 2025, and why?"
    python scripts/ask.py --tools-only      # run every tool once without calling the model (no cost)

The AI layer sits on the deterministic one, it does not replace it:
  * Claude cannot write SQL. It can only call the six functions below, each a fixed query with typed parameters.
  * Every number in the final answer is checked against the numbers the tools returned. Any number that did not
    come from a tool is listed under "UNVERIFIED" instead of being passed off as fact.

Credentials: ANTHROPIC_API_KEY, or a profile from `ant auth login`. Model: claude-opus-5-5.
"""
import json, os, re, sys
import duckdb

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
con = duckdb.connect(os.environ.get("DUCKDB_PATH", os.path.join(ROOT, "warehouse.duckdb")), read_only=True)


def rows(sql, params=()):
    cur = con.execute(sql, list(params))
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, [v.isoformat() if hasattr(v, "isoformat") else v for v in r])) for r in cur.fetchall()]


def month_clause(month):
    if month and not re.fullmatch(r"\d{4}-\d{2}", month):
        raise ValueError("month must look like 2025-07")
    return ("and strftime(service_date, '%Y-%m') = ?", [month]) if month else ("", [])


# ---------------------------------------------------------------- the only things the model can do
def lost_time_by_route(mode: str = "", month: str = "", top_n: int = 10) -> str:
    """Routes ranked by service hours lost to delays, with planned hours and the share lost.

    Args:
        mode: "bus", "streetcar" or "subway". Empty for all modes.
        month: A month like "2025-07". Empty for the whole period (Jan 2025 to Sep 2026).
        top_n: How many routes to return (1 to 25).
    """
    mc, mp = month_clause(month)
    mode_c, mode_p = ("and mode = ?", [mode]) if mode else ("", [])
    return json.dumps(rows(f"""
        select route_short_name as route, route_long_name as name, mode,
               round(sum(lost_minutes) / 60.0, 1) as lost_hours,
               round(sum(planned_vehicle_hours), 0) as planned_vehicle_hours,
               round(100 * sum(lost_minutes) / 60.0 / nullif(sum(planned_vehicle_hours), 0), 2) as pct_of_planned_lost,
               round(100.0 * sum(lost_minutes_ttc_control) / nullif(sum(lost_minutes), 0), 0) as pct_within_ttc_control
        from marts.fct_route_day where 1=1 {mc} {mode_c}
        group by 1, 2, 3 order by lost_hours desc limit ?""", mp + mode_p + [max(1, min(int(top_n), 25))]))


def causes_for_route(route: str, month: str = "") -> str:
    """What caused the lost time on one route: hours and events by cause group, biggest first.

    Args:
        route: Route number as written on the vehicle, e.g. "504" or "52". Subway lines are "1", "2", "4".
        month: A month like "2025-07". Empty for the whole period.
    """
    mc, mp = month_clause(month)
    return json.dumps(rows(f"""
        select e.cause_group, count(*) as events, round(sum(e.lost_minutes) / 60.0, 1) as lost_hours,
               any_value(g.within_ttc_control) as within_ttc_control
        from marts.fct_delay_event e join marts.dim_route r using (route_id)
        left join rules.cause_groups g on g.cause_group = e.cause_group
        where r.route_short_name = ? {mc.replace('service_date', 'e.event_date')}
        group by 1 order by lost_hours desc""", [route] + mp))


def vehicle_history(vehicle_number: str, mode: str) -> str:
    """One vehicle's record: total delays, its own equipment faults, repeat faults, and its last 10 events.

    Args:
        vehicle_number: Fleet number as logged, e.g. "1233".
        mode: "bus", "streetcar" or "subway".
    """
    summary = rows("select * from marts.fct_vehicle where vehicle_number = ? and mode = ?", [vehicle_number, mode])
    recent = rows("""select event_date, line_text, code_description, cause_group, delay_minutes
                     from marts.fct_delay_event where vehicle_number = ? and mode = ?
                     order by event_date desc, event_time desc limit 10""", [vehicle_number, mode])
    return json.dumps({"summary": summary, "recent_events": recent})


def repeat_fault_vehicles(mode: str = "", top_n: int = 10) -> str:
    """Vehicles whose equipment failed again within 30 days of the last failure, most repeats first.

    Args:
        mode: "bus", "streetcar" or "subway". Empty for all modes.
        top_n: How many vehicles to return (1 to 25).
    """
    mode_c, mode_p = ("where mode = ?", [mode]) if mode else ("", [])
    return json.dumps(rows(f"""select mode, vehicle_number, repeat_faults, equipment_faults, round(equipment_minutes / 60.0, 1) as equipment_hours,
                                      routes_served, first_seen, last_seen
                               from marts.fct_vehicle {mode_c} order by repeat_faults desc, equipment_faults desc limit ?""",
                           mode_p + [max(1, min(int(top_n), 25))]))


def data_quality() -> str:
    """Checks run on the raw delay logs: how many events each touches and what the pipeline did about it."""
    return json.dumps(rows("select * from reports.rpt_data_quality"))


def counting_rules() -> str:
    """Which cause groups count as lost time and which are within the TTC's control, with the reason for each."""
    return json.dumps(rows("select * from rules.cause_groups"))


TOOLS = [lost_time_by_route, causes_for_route, vehicle_history, repeat_fault_vehicles, data_quality, counting_rules]
SYSTEM = (
    "You answer questions about TTC service lost to delays, using only the tools provided. "
    "Every number you state must come from a tool result in this conversation. Never estimate or compute new figures "
    "except a simple share of two tool numbers, and show both numbers when you do. "
    "If the tools cannot answer, say what is missing. "
    "Planned hours come from the current (Nov 2026) timetable applied by day type, so call them a baseline. "
    "Diversions and shuttle redeployments are not counted as lost time. "
    "Answer in plain sentences a manager can read, under 150 words."
)


def numbers_in(text):
    return {float(n.replace(",", "")) for n in re.findall(r"(?<![\w.])\d[\d,]*(?:\.\d+)?", text)}


def audit(answer, tool_outputs):
    """Flag any number in the answer that no tool returned (allowing rounding to whole numbers and one decimal)."""
    seen = set()
    for out in tool_outputs:
        for v in numbers_in(out):
            seen |= {v, round(v), round(v, 1)}
    return sorted(n for n in numbers_in(answer) if n not in seen and n not in (1, 2, 4) and not 2000 <= n <= 2030)


def main():
    if "--tools-only" in sys.argv:
        for f, args in [(lost_time_by_route, ("streetcar", "", 3)), (causes_for_route, ("504",)),
                        (repeat_fault_vehicles, ("bus", 3)), (vehicle_history, ("1233", "bus")), (data_quality, ()), (counting_rules, ())]:
            print(f"--- {f.__name__}{args}\n{f(*args)[:600]}\n")
        return
    question = " ".join(a for a in sys.argv[1:] if not a.startswith("--"))
    if not question:
        sys.exit(__doc__)

    import anthropic
    from anthropic import beta_tool

    client = anthropic.Anthropic()
    tool_outputs = []

    def recorded(f):
        def wrapper(*a, **k):
            out = f(*a, **k)
            tool_outputs.append(out)
            return out
        wrapper.__name__, wrapper.__doc__, wrapper.__annotations__ = f.__name__, f.__doc__, f.__annotations__
        wrapper.__wrapped__ = f
        return beta_tool(wrapper)

    try:
        runner = client.beta.messages.tool_runner(
            model="claude-opus-5-5",
            max_tokens=16000,
            output_config={"effort": "medium"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",   # if the model declines, the API retries on a fallback model in the same call
            system=SYSTEM,
            tools=[recorded(f) for f in TOOLS],
            messages=[{"role": "user", "content": question}],
        )
        final = None
        for message in runner:
            final = message
    except anthropic.AuthenticationError:
        sys.exit("No Claude credentials. Set ANTHROPIC_API_KEY or run `ant auth login`.")
    except anthropic.RateLimitError:
        sys.exit("Rate limited. Try again shortly.")
    except anthropic.APIStatusError as e:
        sys.exit(f"API error {e.status_code}: {e.message}")
    except anthropic.APIConnectionError:
        sys.exit("Network error reaching the API.")

    if final.stop_reason == "refusal":
        sys.exit("The model declined to answer.")
    answer = "".join(b.text for b in final.content if b.type == "text").strip()
    print(answer)
    print(f"\n[{len(tool_outputs)} tool calls, every figure above came from them]" if not audit(answer, tool_outputs)
          else f"\nUNVERIFIED (not returned by any tool): {audit(answer, tool_outputs)}")


if __name__ == "__main__":
    main()
