#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MANIFEST=${1:?usage: company_production_service_check.sh SERVICE_MANIFEST DEPLOYMENT_GATE OUTPUT}
DEPLOYMENT=${2:?missing deployment gate}
OUTPUT=${3:?missing output path}
exec moon run --target native "$SCRIPT_DIR/../cmd/production_service_check" -- "$MANIFEST" "$DEPLOYMENT" "$OUTPUT"
