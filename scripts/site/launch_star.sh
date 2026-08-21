#!/usr/bin/env bash
# Launch the configured STAR-CCM+ installation, forwarding extra options.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
site_config="${STAR_NEKTAR_SITE_CONFIG:-$project_dir/config/site.env}"
if [[ -f "$site_config" ]]; then
    # shellcheck disable=SC1090
    source "$site_config"
fi

star_executable="${STAR_EXECUTABLE:-starccm+}"
if [[ "$star_executable" != */* ]]; then
    star_executable="$(command -v -- "$star_executable" || true)"
fi

if [[ -z "$star_executable" || ! -x "$star_executable" ]]; then
    echo "STAR-CCM+ executable is missing or not executable:" >&2
    echo "  ${STAR_EXECUTABLE:-starccm+}" >&2
    echo "Set STAR_EXECUTABLE in config/site.env or load the site module." >&2
    exit 1
fi

exec "$star_executable" "$@"
