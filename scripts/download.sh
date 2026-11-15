#!/usr/bin/env bash
# Toronto Open Data (open.toronto.ca): TTC schedules (GTFS) and TTC delay logs since 2025. About 45 MB.
set -euo pipefail
mkdir -p "$(dirname "$0")/../data/raw" && cd "$(dirname "$0")/../data/raw"
mkdir -p gtfs delays
B=https://ckan0.cf.opendata.inter.prod-toronto.ca
curl -fsSL -o gtfs/opendata_ttc_schedules.zip "$B/dataset/7795b45e-e65a-4465-81fc-c36b9dfff169/resource/cfb6b2b8-6191-41e3-bda1-b175c51148cb/download/opendata_ttc_schedules.zip"
curl -fsSL -o delays/bus.csv "$B/dataset/e271cdae-8788-4980-96ce-6a5c95bc6618/resource/b5725365-9252-4bfe-b6f4-cda7ddf74341/download/ttc-bus-delay-data-since-2025.csv"
curl -fsSL -o delays/streetcar.csv "$B/dataset/b68cb71b-44a7-4394-97e2-5d2f41462a5d/resource/cf2fdd12-6f0e-4644-aae7-0bbfc31df031/download/ttc-streetcar-delay-data-since-2025.csv"
curl -fsSL -o delays/subway.csv "$B/dataset/996cfe8d-fb35-40ce-b569-698d51fc683b/resource/0b6e5c52-e993-46d6-8d74-8602ee224457/download/ttc-subway-delay-data-since-2025.csv"
curl -fsSL -o delays/bus_codes.csv "$B/datastore/dump/816f2214-97e2-4c4b-820e-24b425ed08e0"
curl -fsSL -o delays/streetcar_codes.csv "$B/datastore/dump/b1fc714c-c533-424c-8ce4-4994e9c6fb1d"
curl -fsSL -o delays/subway_codes.csv "$B/datastore/dump/9e9efbb6-3a2f-4934-ac94-9150ecaeb548"
unzip -o -q gtfs/opendata_ttc_schedules.zip -d gtfs
echo "downloaded: $(du -sh . | cut -f1)"
