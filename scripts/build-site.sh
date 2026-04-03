#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_PATH=${1:-"$ROOT_DIR/repositories.yml"}
SITE_DIR=${2:-"$ROOT_DIR/site"}
WORK_DIR=${3:-"$ROOT_DIR/.work"}
BASE_URL=${BASE_URL:-}

args=(
  --config "$CONFIG_PATH"
  --output "$SITE_DIR"
  --workspace "$WORK_DIR"
)

if [[ -n "$BASE_URL" ]]; then
  args+=(--base-url "$BASE_URL")
fi

exec python3 "$ROOT_DIR/tools/build_site.py" "${args[@]}"

