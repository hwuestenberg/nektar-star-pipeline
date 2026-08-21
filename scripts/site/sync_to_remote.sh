#!/usr/bin/env bash
# Synchronise the reproducible tutorial inputs to the remote STAR-CCM+ host.

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
Usage: scripts/site/sync_to_remote.sh [options]

Preview or execute an rsync upload of the tutorial inputs.

Options:
  --execute             Perform the upload (the default is an rsync dry run)
  --host HOST           SSH target (default: REMOTE_HOST)
  --remote-dir DIR      Destination relative to the remote home directory
                        (default: REMOTE_DIR or nektar-star-pipeline)
  -h, --help            Show this help

The upload deliberately excludes Git internals, Python caches, STAR .sim/.ccm
and generated RANS tables, plus generated NekMesh meshes/fields. It never
passes --delete, so remote results are not removed by a later upload.
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
    --exclude=.env
    --exclude=star_pod_key
    --exclude='config/site.env'
    --exclude='config/*.local.env'
    --exclude=__pycache__/
    --exclude='*.py[cod]'
    --exclude='star/*.sim'
    --exclude='star/*.sim~'
    --exclude='star/*.ccm'
    --exclude='star/*.log'
    --exclude='star/*.provenance.txt'
    --exclude='star/*_rans_raw.csv'
    --exclude='star/*_rans_nektar.csv'
    --exclude='logs/'
    --exclude='nekmesh/*.xml'
    --exclude='nekmesh/*.fld'
    --exclude='nekmesh/*.vtu'
    --exclude='nekmesh/*.vtk'
    --exclude='nekmesh/*_jac_under_*.txt'
    --exclude='nekmesh/.*'
)

if [[ "$execute" != true ]]; then
    rsync_args+=(--dry-run)
    echo "Preview only; pass --execute to transfer files."
else
    echo "Uploading tutorial inputs."
fi

echo "Source      : $project_dir/"
echo "Destination : $remote_host:$remote_dir/"

rsync "${rsync_args[@]}" "$project_dir/" "$remote_host:$remote_dir/"
