#!/usr/bin/env bash
# Synchronise generated tutorial outputs from the remote STAR-CCM+ host.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
site_config="${STAR_NEKTAR_SITE_CONFIG:-$project_dir/config/site.env}"
if [[ -f "$site_config" ]]; then
    # shellcheck disable=SC1090
    source "$site_config"
fi

remote_host="${REMOTE_HOST:-}"
remote_dir="${REMOTE_DIR:-nektar-star-pipeline}"
execute=false

usage() {
    cat <<'EOF'
Usage: scripts/site/sync_from_remote.sh [options]

Preview or execute an rsync download of generated tutorial outputs.

Options:
  --execute             Perform the download (default: rsync dry run)
  --host HOST           SSH target (default: REMOTE_HOST)
  --remote-dir DIR      Destination relative to the remote home directory
                        (default: REMOTE_DIR or nektar-star-pipeline)
  -h, --help            Show this help

The download deliberately excludes Git internals, Python caches, STAR .sim/.ccm
files and generated NekMesh XML meshes. It never passes --delete.
EOF
}

while (($#)); do
    case "$1" in
        --execute)
            execute=true
            shift
            ;;
        --host)
            [[ $# -ge 2 ]] || {
                echo "--host requires a value" >&2
                exit 2
            }
            remote_host="$2"
            shift 2
            ;;
        --remote-dir)
            [[ $# -ge 2 ]] || {
                echo "--remote-dir requires a value" >&2
                exit 2
            }
            remote_dir="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$remote_host" ]]; then
    echo "Set REMOTE_HOST in config/site.env or pass --host." >&2
    exit 2
fi
if [[ -z "$remote_dir" ]]; then
    echo "The remote directory must not be empty." >&2
    exit 2
fi
if [[ "$remote_dir" == /* || "$remote_dir" == *:* || "$remote_dir" == *$'\n'* ]]; then
    echo "--remote-dir must be a safe path relative to the remote home directory." >&2
    exit 2
fi

rsync_args=(
    --archive
    --compress
    --human-readable
    --itemize-changes
    --exclude=.git/
    --exclude=.pytest_cache/
    --exclude=.ruff_cache/
    --exclude=.env
    --exclude=star_pod_key
    --exclude='config/site.env'
    --exclude='config/*.local.env'
    --exclude=__pycache__/
    --exclude='*.py[cod]'
    --exclude='star/*.sim'
    --exclude='star/*.ccm'
    --exclude='nekmesh/*.xml'
    --include='nekmesh/*.vtu'
    --exclude='nekmesh/*.vtk'
)

if [[ "$execute" != true ]]; then
    rsync_args+=(--dry-run)
    echo "Preview only; pass --execute to transfer files."
else
    echo "Downloading tutorial outputs."
fi

echo "Destination : $project_dir/"
echo "Source      : $remote_host:$remote_dir/"

rsync "${rsync_args[@]}" "$remote_host:$remote_dir/" "$project_dir/"
