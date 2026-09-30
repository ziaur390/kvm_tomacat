#!/usr/bin/env bash
#
# Builds the study guide PDF from the chapter files in this directory.
#
#   bash docs/study-guide/build-pdf.sh
#   -> docs/kvm-tomcat-lab-study-guide.pdf
#
# Needs pandoc and weasyprint:
#   sudo apt-get install -y pandoc weasyprint fonts-dejavu-core
#
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out="$here/../kvm-tomcat-lab-study-guide.pdf"

chapters=(
  "$here/01-the-story.md"
  "$here/02-machines.md"
  "$here/03-app-and-web.md"
  "$here/04-automation.md"
  "$here/05-monitoring.md"
  "$here/06-what-broke.md"
  "$here/07-glossary.md"
)

for f in "${chapters[@]}"; do
  [ -f "$f" ] || { echo "missing chapter: $f" >&2; exit 1; }
done

echo "Building ${#chapters[@]} chapters..."

pandoc "${chapters[@]}" \
  --from markdown+pipe_tables \
  --to html5 \
  --standalone \
  --toc \
  --toc-depth=2 \
  --css "$here/style.css" \
  --metadata title="kvm-tomcat-lab: an illustrated study guide" \
  --metadata lang=en \
  -o "$here/.build.html"

weasyprint "$here/.build.html" "$out"
rm -f "$here/.build.html"

echo "Wrote $out ($(du -h "$out" | cut -f1))"
