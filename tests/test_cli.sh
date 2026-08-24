#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
    "$project_dir/execute.sh" \
    "$project_dir"/scripts/nektar/*.sh \
    "$project_dir"/scripts/workflow/*.sh \
    "$project_dir"/scripts/site/*.sh

commands=(
    scripts/workflow/run_remote_pipeline.sh
    scripts/workflow/run_star_mesh.sh
    scripts/workflow/run_star_bootstrap.sh
    scripts/workflow/run_star_rans.sh
    scripts/workflow/run_nektar_solver.sh
    scripts/workflow/clean_generated.sh
    scripts/workflow/run_resolution_study.sh
    scripts/workflow/cleanup_pipeline_outputs.sh
    scripts/site/sync_to_remote.sh
    scripts/site/sync_from_remote.sh
)

for command in "${commands[@]}"; do
    "$project_dir/$command" --help >/dev/null
done

python3 "$project_dir/scripts/cad/create_naca0012_domain.py" --help >/dev/null

if find "$project_dir/scripts" -maxdepth 1 -type f | grep -q .; then
    echo "Uncategorised files remain directly under scripts/." >&2
    exit 1
fi
