#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec moon run --target native "$ROOT/cmd/workflow_assignment_plan" -- "$@"
