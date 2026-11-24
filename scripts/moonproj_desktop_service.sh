#!/bin/sh
set -eu

umask 077

APP_DATA_DIR=${LEPUSA_APP_DATA_DIR:-"$HOME/Library/Application Support/dev.vectie.moonproj"}
RESOURCE_DIR=${LEPUSA_RESOURCE_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/../Resources" && pwd)}
PUBLIC_DIR="$RESOURCE_DIR/public"
# Bundled catalog/PRDs do not depend on the working directory or company DB.
MOONPROJ_PRODUCT_CATALOG=${MOONPROJ_PRODUCT_CATALOG:-"$RESOURCE_DIR/config/moonsuite-engineering.json"}
MOONPROJ_PRODUCT_DOCUMENT_ROOT=${MOONPROJ_PRODUCT_DOCUMENT_ROOT:-"$RESOURCE_DIR/product-documents"}
# A source/audit workspace is an independent, operator-configured location.
MOONSUITE_WORKSPACE_ROOT=${MOONSUITE_WORKSPACE_ROOT:-"$APP_DATA_DIR/workspaces"}
export MOONPROJ_PRODUCT_CATALOG MOONPROJ_PRODUCT_DOCUMENT_ROOT MOONSUITE_WORKSPACE_ROOT

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
    for candidate in /Library/PostgreSQL/*/bin/psql /opt/homebrew/bin/psql /usr/local/bin/psql /opt/homebrew/opt/postgresql@*/bin/psql /usr/local/opt/postgresql@*/bin/psql; do
      if [ -x "$candidate" ]; then
        PSQL_BIN=$candidate
      fi
    done
  fi
fi

if [ -n "${PSQL_BIN:-}" ]; then
  export PSQL_BIN
fi
# Use only an explicitly provisioned app-local cluster, never a system cluster.
if [ -f "$APP_DATA_DIR/postgres/data/PG_VERSION" ]; then
  PGHOST=${PGHOST:-"$APP_DATA_DIR/postgres"}
  PGPORT=${PGPORT:-55433}
  PGUSER=${PGUSER:-$(id -un)}
  PGDATABASE=${PGDATABASE:-moonproj}
  export PGHOST PGPORT PGUSER PGDATABASE
fi

MOONDESK_ORIGIN=${MOONDESK_ORIGIN:-http://127.0.0.1:4201}
export MOONDESK_ORIGIN

# Reuse a single existing Desk pairing; ambiguous installations stay explicit.
if [ -z "${MOONDESK_EXECUTION_SANDBOX_CONFIG:-}" ]; then
  pairing_file=
  pairing_count=0
  for candidate in "$HOME/Library/Application Support/app.vectie.moondesk.lepusa.live/control/execution-sandbox/"*.json; do
    if [ -f "$candidate" ]; then
      pairing_file=$candidate
      pairing_count=$((pairing_count + 1))
    fi
  done
  if [ "$pairing_count" -eq 1 ]; then
    MOONDESK_EXECUTION_SANDBOX_CONFIG=$pairing_file
    export MOONDESK_EXECUTION_SANDBOX_CONFIG
  fi
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
