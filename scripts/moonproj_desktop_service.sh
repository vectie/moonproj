#!/bin/sh
set -eu

umask 077

APP_DATA_DIR=${LEPUSA_APP_DATA_DIR:-"$HOME/Library/Application Support/dev.vectie.moonproj"}
RESOURCE_DIR=${LEPUSA_RESOURCE_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/../Resources" && pwd)}
PUBLIC_DIR="$RESOURCE_DIR/public"

mkdir -p "$APP_DATA_DIR"

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    printf '%s' "$(uuidgen)-$(uuidgen)" | tr -d '-\n' | tr '[:upper:]' '[:lower:]'
  fi
}

if [ -z "${PSQL_BIN:-}" ]; then
  if command -v psql >/dev/null 2>&1; then
    PSQL_BIN=$(command -v psql)
  else
    for candidate in /Library/PostgreSQL/*/bin/psql /opt/homebrew/bin/psql /usr/local/bin/psql; do
      if [ -x "$candidate" ]; then
        PSQL_BIN=$candidate
      fi
    done
  fi
fi

if [ -n "${PSQL_BIN:-}" ]; then
  export PSQL_BIN
fi
if [ -f "$APP_DATA_DIR/pgpass" ]; then
  PGPASSFILE="$APP_DATA_DIR/pgpass"
  export PGPASSFILE
fi

MOONPROJ_SERVICE_TOKEN=$(random_secret)
MOONPROJ_ACTOR_SIGNING_SECRET=$(random_secret)
MOONPROJ_SESSION_SECRET=$(random_secret)
MOONPROJ_DEV_USER=desktop-owner
MOONPROJ_DEV_PASSWORD=$(random_secret)
MOONPROJ_DEV_ACTOR_ID=desktop-owner
MOONPROJ_DESKTOP_ACTOR=desktop-owner
COMPANY_GATEWAY_PUBLIC_DIR=$PUBLIC_DIR

export MOONPROJ_SERVICE_TOKEN MOONPROJ_ACTOR_SIGNING_SECRET
export MOONPROJ_SESSION_SECRET MOONPROJ_DEV_USER MOONPROJ_DEV_PASSWORD
export MOONPROJ_DEV_ACTOR_ID MOONPROJ_DESKTOP_ACTOR COMPANY_GATEWAY_PUBLIC_DIR

service_pid=
gateway_pid=

cleanup() {
  trap - INT TERM HUP EXIT
  if [ -n "$gateway_pid" ]; then
    kill "$gateway_pid" 2>/dev/null || true
  fi
  if [ -n "$service_pid" ]; then
    kill "$service_pid" 2>/dev/null || true
  fi
  wait "$gateway_pid" 2>/dev/null || true
  wait "$service_pid" 2>/dev/null || true
}

trap cleanup INT TERM HUP EXIT

moonproj-company-service --host 127.0.0.1 --port 4174 &
service_pid=$!

moonproj-company-gateway \
  --host 127.0.0.1 \
  --port 4173 \
  --service-host 127.0.0.1 \
  --service-port 4174 \
  --public-dir "$PUBLIC_DIR" &
gateway_pid=$!

wait "$gateway_pid"
