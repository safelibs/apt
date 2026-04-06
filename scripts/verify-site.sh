#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SITE_TARGET=${1:-"$ROOT_DIR/site"}
CONFIG_PATH=${2:-"$ROOT_DIR/repositories.yml"}

mapfile -t repository_names < <(
  python3 - "$CONFIG_PATH" <<'PY'
from pathlib import Path
import sys
import yaml

config = yaml.safe_load(Path(sys.argv[1]).read_text())
print("all")
for entry in config["repositories"]:
    print(str(entry["name"]))
PY
)

for repository_name in "${repository_names[@]}"; do
  bash "$ROOT_DIR/scripts/verify-in-ubuntu-docker.sh" "$SITE_TARGET" "$CONFIG_PATH" "$repository_name"
done
