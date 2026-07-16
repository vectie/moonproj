#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
moon run --target native "$ROOT/cmd/access_plan" -- "$@"
