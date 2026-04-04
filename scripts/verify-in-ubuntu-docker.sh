#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=${SAFEAPTREPO_VERIFY_IMAGE:-${SAFEDEBREPO_VERIFY_IMAGE:-ubuntu:24.04}}
REPO_TARGET=${1:-"$ROOT_DIR/site"}
CONFIG_PATH=${2:-"$ROOT_DIR/repositories.yml"}

IFS=$'\t' read -r suite component key_name packages_csv <<EOF
$(python3 - "$CONFIG_PATH" <<'PY'
from pathlib import Path
import sys
import yaml

config = yaml.safe_load(Path(sys.argv[1]).read_text())
archive = config["archive"]
packages = []
for entry in config["repositories"]:
    packages.extend(entry.get("verify_packages", []))
print(
    "\t".join(
        [
            str(archive["suite"]),
            str(archive["component"]),
            str(archive["key_name"]),
            ",".join(dict.fromkeys(packages)),
        ]
    )
)
PY
)
EOF

if [[ -z "$packages_csv" ]]; then
  printf 'no verify_packages found in %s\n' "$CONFIG_PATH" >&2
  exit 1
fi

repo_uri=
madison_source=
setup_repo=
docker_args=()

if [[ -d "$REPO_TARGET" ]]; then
  site_dir=$(cd "$REPO_TARGET" && pwd)
  repo_uri='file:///repo'
  madison_source='file:/repo'
  docker_args+=(
    --mount
    "type=bind,src=$site_dir,dst=/repo,readonly"
  )
  setup_repo=$(cat <<EOF
install -D -m 0644 /repo/${key_name}.gpg /usr/share/keyrings/${key_name}.gpg
install -D -m 0644 /repo/${key_name}.pref /etc/apt/preferences.d/${key_name}.pref
cat >/etc/apt/sources.list.d/${key_name}.list <<LIST
deb [signed-by=/usr/share/keyrings/${key_name}.gpg] ${repo_uri} ${suite} ${component}
LIST
EOF
)
elif [[ "$REPO_TARGET" =~ ^https?:// ]]; then
  repo_uri=${REPO_TARGET%/}
  madison_source=$repo_uri
  setup_repo=$(cat <<EOF
curl -fsSL ${repo_uri}/${key_name}.gpg -o /usr/share/keyrings/${key_name}.gpg
curl -fsSL ${repo_uri}/${key_name}.pref -o /etc/apt/preferences.d/${key_name}.pref
cat >/etc/apt/sources.list.d/${key_name}.list <<LIST
deb [signed-by=/usr/share/keyrings/${key_name}.gpg] ${repo_uri} ${suite} ${component}
LIST
EOF
)
else
  printf 'expected site directory or http(s) base URL, got: %s\n' "$REPO_TARGET" >&2
  exit 1
fi

docker run --rm \
  "${docker_args[@]}" \
  -e SAFEAPTREPO_VERIFY_PACKAGES="$packages_csv" \
  -e SAFEDEBREPO_VERIFY_PACKAGES="$packages_csv" \
  -e SAFEAPTREPO_VERIFY_SETUP="$setup_repo" \
  -e SAFEDEBREPO_VERIFY_SETUP="$setup_repo" \
  -e SAFEAPTREPO_VERIFY_MADISON_SOURCE="$madison_source" \
  -e SAFEDEBREPO_VERIFY_MADISON_SOURCE="$madison_source" \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl
    install -d -m 0755 /usr/share/keyrings /etc/apt/preferences.d
    eval "${SAFEAPTREPO_VERIFY_SETUP:-${SAFEDEBREPO_VERIFY_SETUP:-}}"
    apt-get update
    IFS=, read -r -a packages <<<"${SAFEAPTREPO_VERIFY_PACKAGES:-${SAFEDEBREPO_VERIFY_PACKAGES:-}}"
    madison_source="${SAFEAPTREPO_VERIFY_MADISON_SOURCE:-${SAFEDEBREPO_VERIFY_MADISON_SOURCE:-}}"
    apt-get install -y --no-install-recommends --allow-downgrades "${packages[@]}"
    for package in "${packages[@]}"; do
      version="$(dpkg-query -W -f='\''${Version}'\'' "$package")"
      printf "%s\t%s\n" "$package" "$version"
      apt-cache madison "$package" | grep -F "| $version | ${madison_source} " >/dev/null
    done
    if command -v zstd >/dev/null 2>&1; then
      zstd --version | head -n 1
    fi
  '
