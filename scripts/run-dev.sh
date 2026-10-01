#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "$@"
open -n dist/Sumra.app
