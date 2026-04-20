#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SITE_TARGET=${1:-"$ROOT_DIR/site"}
CONFIG_PATH=${2:-"$ROOT_DIR/repositories.yml"}

repository_specs_output=$(
  python3 - "$SITE_TARGET" "$CONFIG_PATH" <<'PY'
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.request import urlopen
import yaml

site_target = sys.argv[1]
config_path = Path(sys.argv[2])


def read_manifest(target: str):
    if target.startswith(("http://", "https://")):
        try:
            with urlopen(f"{target.rstrip('/')}/manifest.json") as response:
                return json.loads(response.read().decode())
        except (HTTPError, URLError, json.JSONDecodeError):
            return None

    manifest_path = Path(target) / "manifest.json"
    if not manifest_path.exists():
        return None
    try:
        return json.loads(manifest_path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse {manifest_path}: {exc}") from exc


manifest = read_manifest(site_target)
if manifest is not None:
    channels = manifest.get("channels")
    if not isinstance(channels, list) or not channels:
        raise SystemExit("manifest.json must define a non-empty channels list")
    for channel in channels:
        repositories = channel.get("repositories") if isinstance(channel, dict) else None
        if not isinstance(repositories, list):
            raise SystemExit("manifest.json channel must define repositories")
        for entry in repositories:
            if not isinstance(entry, dict):
                raise SystemExit("manifest.json repository entries must be objects")
            name = str(entry.get("name") or "").strip()
            path = str(entry.get("path") or "").strip()
            if not name or not path:
                raise SystemExit("manifest.json repository entries must define name and path")
            print(f"{name}\t{path}")
    raise SystemExit(0)

try:
    config_text = config_path.read_text()
except OSError as exc:
    raise SystemExit(f"failed to read {config_path}: {exc}") from exc

try:
    config = yaml.safe_load(config_text)
except yaml.YAMLError as exc:
    raise SystemExit(f"failed to parse {config_path}: {exc}") from exc

if not isinstance(config, dict):
    raise SystemExit(f"{sys.argv[1]} must contain a YAML mapping")
repositories = config.get("repositories")
if not isinstance(repositories, list) or not repositories:
    raise SystemExit(f"{sys.argv[2]} must define a non-empty repositories list")
print("all\tall")
for entry in repositories:
    print(f"{entry['name']}\t{entry['name']}")
PY
)
mapfile -t repository_specs <<<"$repository_specs_output"
if [[ ${#repository_specs[@]} -eq 0 ]] || [[ -z ${repository_specs[0]} ]]; then
  printf 'failed to resolve repositories from %s\n' "$CONFIG_PATH" >&2
  exit 1
fi

for repository_spec in "${repository_specs[@]}"; do
  IFS=$'\t' read -r repository_name repository_path <<<"$repository_spec"
  bash "$ROOT_DIR/scripts/verify-in-ubuntu-docker.sh" "$SITE_TARGET" "$CONFIG_PATH" "$repository_name" "$repository_path"
done
