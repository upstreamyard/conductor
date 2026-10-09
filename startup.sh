#!/bin/sh
# Startup script for the upstreamyard Conductor image, based on upstream's
# docker/server/bin/startup.sh: nginx serves the UI on 5000 in the background,
# the Conductor server runs on 8080.
# Differences: java is exec'd (stop signals reach it via tini), logs go to stdout only,
# and a missing CONFIG_PROP file is an error (upstream silently falls back to SQLite).
set -e

if [ -n "$CONFIG_PROP" ] && [ ! -r "/app/config/$CONFIG_PROP" ]; then
  echo "ERROR: CONFIG_PROP=$CONFIG_PROP, but /app/config/$CONFIG_PROP does not exist or is not readable." >&2
  echo "Mount your properties file into /app/config, or unset CONFIG_PROP to use the built-in SQLite defaults." >&2
  exit 1
fi

echo "Starting Conductor server"

echo "Running Nginx in background"
nginx -e /dev/stderr

cd /app/libs
echo "Using java options config: $JAVA_OPTS"

if [ -z "$CONFIG_PROP" ]; then
  echo "No CONFIG_PROP set - using built-in defaults (SQLite, no external dependencies required)"
  # shellcheck disable=SC2086
  exec java ${JAVA_OPTS} -jar conductor-server.jar
else
  echo "Using config: $CONFIG_PROP"
  # shellcheck disable=SC2086
  exec java ${JAVA_OPTS} -DCONDUCTOR_CONFIG_FILE="/app/config/$CONFIG_PROP" -jar conductor-server.jar
fi
