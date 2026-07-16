#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MANIFEST=${1:?usage: company_production_deployment_check.sh MANIFEST OUTPUT}
OUTPUT=${2:?missing output path}
exec moon run --target native "$SCRIPT_DIR/../cmd/production_deployment_check" -- "$MANIFEST" "$OUTPUT"
