#!/usr/bin/env bash
#
# Renders docs/architecture.svg to a PNG for the README.
#
# The SVG is the source of truth. The PNG exists because every markdown viewer
# renders PNG, and not every one renders SVG.
#
#   sudo apt-get install -y librsvg2-bin
#   bash docs/render-diagram.sh
#
set -euo pipefail

cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found. Install it with:" >&2
  echo "  sudo apt-get install -y librsvg2-bin" >&2
  exit 1
}

# 2x the SVG's natural size, so it stays sharp on high-DPI screens.
rsvg-convert --zoom 2 --background-color white architecture.svg -o architecture.png

echo "Wrote docs/architecture.png ($(du -h architecture.png | cut -f1))"
