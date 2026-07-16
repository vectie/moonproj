#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_DIR=${1:?usage: company_business_acceptance_check.sh WORK_DIR MANIFEST OUTPUT}
MANIFEST=${2:?missing acceptance manifest}
OUTPUT=${3:?missing output path}
exec moon run --target native "$SCRIPT_DIR/../cmd/business_acceptance_check" -- "$WORK_DIR" "$MANIFEST" "$OUTPUT"
