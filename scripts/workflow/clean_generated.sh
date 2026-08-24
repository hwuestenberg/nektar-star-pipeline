#!/usr/bin/env bash
# Remove reproducible run products while preserving source and site config.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
execute=false

usage() {
    cat <<'EOF'
Usage: scripts/workflow/clean_generated.sh [--execute]

Prepare the repository for a fresh ./execute.sh run. The default is a dry run
that prints ignored generated files and directories without deleting them.

Options:
  --execute  Delete the displayed generated artifacts
  -h, --help Show this help

The cleanup uses an explicit list of generated paths and works in both a Git
clone and a Git-less rsync copy. It preserves source files, config/site.env,
config/*.local.env and .env. It removes STAR, NekMesh and Nektar run products,
logs, retained STAR staging directories and local test/tool caches.
EOF
}

while (($#)); do
    case "$1" in
        --execute)
            execute=true
            shift
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

[[ -f "$project_dir/execute.sh" && -d "$project_dir/scripts/workflow" ]] || {
    echo "Repository layout is not recognized: $project_dir" >&2
    exit 1
}

shopt -s nullglob globstar
candidates=(
    "$project_dir"/star/*.sim
    "$project_dir"/star/*.ccm
    "$project_dir"/star/*.log
    "$project_dir"/star/*.provenance.txt
    "$project_dir"/star/*_rans_raw.csv
    "$project_dir"/star/*_rans_nektar.csv
    "$project_dir"/star/.star-stage.*
    "$project_dir"/star/.star-bootstrap.*
    "$project_dir"/star/.star-rans-stage.*
    "$project_dir"/nekmesh/*.xml
    "$project_dir"/nekmesh/*.fld
    "$project_dir"/nekmesh/*.vtu
    "$project_dir"/nekmesh/*.vtk
    "$project_dir"/nekmesh/.*.swp
    "$project_dir"/nekmesh/.*_*
    "$project_dir"/logs
    "$project_dir"/work
    "$project_dir"/results
    "$project_dir"/nektar/*/run
    "$project_dir"/.pytest_cache
    "$project_dir"/.ruff_cache
    "$project_dir"/scripts/**/__pycache__
    "$project_dir"/tests/**/__pycache__
)
shopt -u nullglob globstar

declare -A seen=()
unique_candidates=()
for candidate in "${candidates[@]}"; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    [[ -z "${seen[$candidate]:-}" ]] || continue
    seen[$candidate]=1
    unique_candidates+=("$candidate")
done

print_candidates() {
    local candidate relative
    for candidate in "${unique_candidates[@]}"; do
        relative="${candidate#"$project_dir"/}"
        printf 'REMOVE %s\n' "$relative"
    done
}

if [[ "$execute" == true ]]; then
    echo "Removing generated artifacts; preserving source and local configuration."
    print_candidates
    for candidate in "${unique_candidates[@]}"; do
        rm -rf -- "$candidate"
    done
    printf 'Generated-artifact cleanup complete: %d paths removed.\n' \
        "${#unique_candidates[@]}"
else
    echo "Dry run: generated artifacts that would be removed:"
    print_candidates
    echo
    echo "No files were removed. Run again with --execute after review."
fi
