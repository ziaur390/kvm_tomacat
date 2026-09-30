#!/usr/bin/env bash
#
# Builds the lab web application into the WAR the tomcat role deploys.
#
# The WAR deploys as context /labapp, so the endpoints are /labapp/health and
# /labapp/work. A named context avoids fighting Tomcat's built-in ROOT app.

set -euo pipefail

cd "$(dirname "$0")/src"
WAR=../../roles/tomcat/files/labapp.war

mkdir -p "$(dirname "$WAR")"
rm -f "$WAR"
# -X drops zip's extra metadata (high-precision timestamps and friends). Without
# it the WAR differs byte-for-byte on every rebuild even when nothing changed,
# so the Ansible copy task reports changed and the idempotency proof breaks.
zip -q -X -r "$WAR" . -x '.*'

# Fail loudly rather than shipping a WAR that is missing its deployment
# descriptor - the symptom in Tomcat would otherwise be a confusing 404.
if ! unzip -l "$WAR" | grep -q 'WEB-INF/web.xml'; then
  echo "build failed: WEB-INF/web.xml is not in $WAR" >&2
  exit 1
fi

echo "built $WAR"
unzip -l "$WAR"
