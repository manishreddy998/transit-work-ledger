"""Land the TTC files as published (all text) into the warehouse, with SHA-256, size and row count per file.

The delay logs come from three different teams (bus, streetcar, subway). They share columns but not column order,
and the code lists mix line endings, so every file is read with a lenient parser and nothing is fixed here.
All fixes happen in SQL, where they are versioned, tested and visible.
"""
import hashlib, os
from datetime import datetime, timezone
import duckdb

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RAW = os.path.join(ROOT, "data", "raw")
con = duckdb.connect(os.environ.get("DUCKDB_PATH", os.path.join(ROOT, "warehouse.duckdb")))
now = datetime.now(timezone.utc).isoformat()
csv = "read_csv(?, all_varchar=true, strict_mode=false, header=true)"
FILES = [("raw_delays", m, f"delays/{m}.csv", csv) for m in ("bus", "streetcar", "subway")] + \
        [("raw_delays", f"{m}_codes", f"delays/{m}_codes.csv", csv) for m in ("bus", "streetcar", "subway")] + \
        [("raw_gtfs", t, f"gtfs/{t}.txt", "read_csv(?, all_varchar=true, header=true)")
         for t in ("agency", "routes", "trips", "stop_times", "stops", "calendar", "calendar_dates")]


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


con.execute("create schema if not exists raw_meta")
con.execute("create or replace table raw_meta.source_files (schema_name varchar, table_name varchar, file varchar, "
            "sha256 varchar, bytes bigint, row_count bigint, loaded_at varchar)")
for schema, table, rel, reader in FILES:
    path = os.path.join(RAW, rel)
    con.execute(f"create schema if not exists {schema}")
    con.execute(f"create or replace table {schema}.{table} as select *, ? as _source_file from {reader}", [rel, path])
    n = con.execute(f"select count(*) from {schema}.{table}").fetchall()[0][0]
    con.execute("insert into raw_meta.source_files values (?, ?, ?, ?, ?, ?, ?)", [schema, table, rel, sha256(path), os.path.getsize(path), n, now])
    print(f"{schema}.{table:16s} {n:>11,} rows  <- {rel}")
