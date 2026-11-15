PY := .venv/bin/python -I
DBT := DBT_PROFILES_DIR=. .venv/bin/dbt
.PHONY: all setup download load build tools clean
all: load build
setup:
	python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt
download:
	./scripts/download.sh
load:
	$(PY) scripts/load.py
build:
	$(DBT) seed -q && $(DBT) build
tools:
	$(PY) scripts/ask.py --tools-only
clean:
	rm -rf target logs warehouse.duckdb*
