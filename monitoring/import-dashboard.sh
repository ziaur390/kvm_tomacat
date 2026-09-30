#!/usr/bin/env bash
#
# Imports the Node Exporter Full dashboard (grafana.com ID 1860) into Grafana.
#
# Done through the API rather than the UI so the lab is reproducible: no step in
# this project depends on someone remembering to click something.
#
# Reads the latest revision from grafana.com, strips the __inputs/__requires
# wrapper that only the UI import understands, and pins the dashboard to the
# provisioned datasource.
#
#   bash monitoring/import-dashboard.sh
#
set -euo pipefail

GRAFANA=${GRAFANA:-http://localhost:3000}
AUTH=${AUTH:-admin:admin}
DASH_ID=${DASH_ID:-1860}
DATASOURCE=${DATASOURCE:-Prometheus}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading dashboard $DASH_ID from grafana.com..."
curl -sf "https://grafana.com/api/dashboards/$DASH_ID/revisions/latest/download" \
  -o "$tmp/dashboard.json"
echo "  $(wc -c < "$tmp/dashboard.json") bytes"

python3 - "$tmp/dashboard.json" "$DATASOURCE" > "$tmp/import.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
# __inputs/__requires describe the UI import form; the API rejects them.
d.pop("__inputs", None)
d.pop("__requires", None)
print(json.dumps({
    "dashboard": d,
    "overwrite": True,
    "inputs": [{
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "pluginId": "prometheus",
        "value": sys.argv[2],
    }],
}))
PY

echo "Importing into $GRAFANA..."
curl -sf -u "$AUTH" -H "Content-Type: application/json" \
  -X POST "$GRAFANA/api/dashboards/import" -d @"$tmp/import.json"
echo
echo "Done. Open $GRAFANA/dashboards"
