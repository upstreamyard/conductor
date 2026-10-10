#!/usr/bin/env bash
# Smoke test for the Conductor image against PostgreSQL, used by CI and locally:
#   ./scripts/smoke-test.sh <image>
# Checks the API health endpoint, runs a workflow end to end, and checks the UI and its /api proxy.
set -euo pipefail

IMAGE=${1:?usage: smoke-test.sh <image>}
PG_IMAGE=${PG_IMAGE:-postgres:16}
NET=conductor-smoke
API=http://localhost:8080
UI=http://localhost:5000

cleanup() {
  echo "--- conductor logs (tail)"
  docker logs conductor-smoke 2>&1 | tail -40 || true
  docker rm -f conductor-smoke conductor-smoke-pg >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$NET" >/dev/null

# Same database settings as config-postgres.properties from the Conductor project (host postgresdb, user/password conductor).
docker run -d --name conductor-smoke-pg --network "$NET" --network-alias postgresdb \
  -e POSTGRES_USER=conductor -e POSTGRES_PASSWORD=conductor -e POSTGRES_DB=postgres \
  "$PG_IMAGE" >/dev/null
for _ in $(seq 1 30); do
  docker exec conductor-smoke-pg pg_isready -U conductor -d postgres >/dev/null 2>&1 && break
  sleep 2
done

docker run -d --name conductor-smoke --network "$NET" -p 8080:8080 -p 5000:5000 \
  -e CONFIG_PROP=config-postgres.properties \
  "$IMAGE" >/dev/null

echo "--- waiting for $API/health"
for i in $(seq 1 90); do
  if curl -sf "$API/health" >/dev/null; then echo "healthy after ~$((i * 2))s"; break; fi
  if [ "$i" = 90 ]; then echo "server did not become healthy"; exit 1; fi
  sleep 2
done

echo "--- registering and running a workflow"
# ${workflow...} is Conductor's expression syntax, not a shell variable.
# shellcheck disable=SC2016
curl -sf -X POST "$API/api/metadata/workflow" -H 'Content-Type: application/json' -d '{
  "name": "smoke_test", "version": 1, "schemaVersion": 2, "ownerEmail": "smoke@example.com",
  "tasks": [{"name": "set_greeting", "taskReferenceName": "set_greeting", "type": "SET_VARIABLE",
             "inputParameters": {"greeting": "hello ${workflow.input.name}"}}],
  "outputParameters": {"greeting": "${workflow.variables.greeting}"}
}' >/dev/null
id=$(curl -sf -X POST "$API/api/workflow/smoke_test" -H 'Content-Type: application/json' -d '{"name": "upstreamyard"}')
echo "workflow id: $id"
for i in $(seq 1 30); do
  wf=$(curl -sf "$API/api/workflow/$id?includeTasks=false")
  status=$(echo "$wf" | jq -r .status)
  [ "$status" = COMPLETED ] && break
  if [ "$i" = 30 ]; then echo "workflow not completed, status: $status"; exit 1; fi
  sleep 1
done
greeting=$(echo "$wf" | jq -r .output.greeting)
[ "$greeting" = "hello upstreamyard" ] || { echo "unexpected output: $greeting"; exit 1; }
echo "workflow COMPLETED with output: $greeting"

echo "--- checking the UI and its /api proxy on port 5000"
# Read the whole page first: piping curl into "grep -q" can fail randomly under pipefail,
# because grep exits at the first match and curl then gets a broken pipe.
page=$(curl -sf "$UI/") || { echo "UI request failed"; exit 1; }
grep -qi '<html' <<<"$page" || { echo "UI did not return HTML"; exit 1; }
curl -sf "$UI/api/metadata/workflow/smoke_test" | jq -e '.name == "smoke_test"' >/dev/null \
  || { echo "UI /api proxy failed"; exit 1; }
echo "UI and /api proxy OK"

echo "--- checking that a missing CONFIG_PROP file stops the container"
rc=0
out=$(timeout 60 docker run --rm -e CONFIG_PROP=missing.properties "$IMAGE" 2>&1) || rc=$?
if [ "$rc" -ne 1 ] || ! grep -q "does not exist" <<<"$out"; then
  echo "expected exit code 1 with an error message, got $rc: $out"; exit 1
fi
echo "missing config file rejected"

echo "--- smoke test passed"
