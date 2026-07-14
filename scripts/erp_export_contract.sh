#!/bin/sh
set -eu

# MoonBit-only export contract entry point. Shell owns orchestration; the
# validator and all source-data policy live in cmd/export_contract.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
moon run --target native "$ROOT/cmd/export_contract" -- "$@"
