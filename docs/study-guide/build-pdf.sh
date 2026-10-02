#!/usr/bin/env bash
#
# Builds the project's PDFs from the sources in this directory.
#
#   bash docs/study-guide/build-pdf.sh
#
# Produces:
#   docs/kvm-tomcat-lab-study-guide.pdf   the plain-English guide (7 chapters)
#   docs/kvm-tomcat-lab-complete.pdf      the guide + README + every doc + raw evidence
#
# Needs pandoc and weasyprint:
#   sudo apt-get install -y pandoc weasyprint fonts-dejavu-core
#
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
docs=$(cd "$here/.." && pwd)
root=$(cd "$docs/.." && pwd)

guide=(
  "$here/01-the-story.md"
  "$here/02-machines.md"
  "$here/03-app-and-web.md"
  "$here/04-automation.md"
  "$here/05-monitoring.md"
  "$here/06-what-broke.md"
  "$here/07-glossary.md"
)

tech_docs=(
  "$docs/host-setup.md"
  "$docs/snapshots-and-resize.md"
  "$docs/backup-and-restore.md"
  "$docs/capacity-planning.md"
  "$docs/hardening.md"
  "$docs/disaster-recovery.md"
  "$docs/interview-notes.md"
  "$docs/build-log.md"
)

for f in "${guide[@]}" "${tech_docs[@]}"; do
  [ -f "$f" ] || { echo "missing file: $f" >&2; exit 1; }
done

# render <output.pdf> <title> <input.md...>
render() {
  local out=$1 title=$2; shift 2
  local stem
  stem=$(mktemp -d)

  pandoc "$@" \
    --from markdown+pipe_tables \
    --to html5 \
    --standalone \
    --toc \
    --toc-depth=2 \
    --css "$here/style.css" \
    --metadata "title=$title" \
    --metadata lang=en \
    -o "$stem/doc.html"

  weasyprint "$stem/doc.html" "$out" 2>/dev/null
  rm -rf "$stem"
  echo "  $(basename "$out")  ($(du -h "$out" | cut -f1), $(pdfinfo "$out" 2>/dev/null | awk '/^Pages/{print $2}') pages)"
}

echo "1/2  study guide"
render "$docs/kvm-tomcat-lab-study-guide.pdf" \
  "kvm-tomcat-lab: a plain-English study guide" \
  "${guide[@]}"

echo "2/2  complete documentation"
#
# One markdown file assembled from everything, so a reader has the teaching
# guide, the README, the technical write-ups and the raw evidence in a single
# document. The evidence files are raw command output, so they go inside code
# fences and use four backticks to survive any backticks in the output itself.
tmp=$(mktemp -d)
complete="$tmp/complete.md"
{
  echo "# The complete project documentation"
  echo
  echo "Everything in this repository in one document: the plain-English study"
  echo "guide, the full README, every technical write-up, and the raw evidence"
  echo "behind the measured numbers."
  echo

  echo; echo "# Part one: the study guide"; echo
  for f in "${guide[@]}"; do cat "$f"; echo; done

  echo; echo "# Part two: the README"; echo
  cat "$root/README.md"

  echo; echo "# Part three: technical write-ups"; echo
  for f in "${tech_docs[@]}"; do echo; echo "---"; echo; cat "$f"; echo; done

  echo; echo "# Appendix: raw evidence"
  echo
  echo "Command output captured from the running lab. Regenerate with"
  echo "\`bash scripts/capture-evidence.sh\`."
  echo
  for f in "$docs"/evidence/*.txt; do
    echo "## $(basename "$f" .txt)"
    echo
    echo '````'
    cat "$f"
    echo '````'
    echo
  done
} > "$complete"

render "$docs/kvm-tomcat-lab-complete.pdf" \
  "kvm-tomcat-lab: complete documentation" \
  "$complete"

rm -rf "$tmp"
echo "Done."
