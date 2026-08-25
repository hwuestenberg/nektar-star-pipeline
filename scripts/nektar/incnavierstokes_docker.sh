#!/usr/bin/env bash
# Run IncNavierStokesSolver from the pinned full Nektar++ OCI image.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
source "$script_dir/container_images.sh"
source "$script_dir/run_nektar_tool.sh"

solver_executable="${NEKTAR_SOLVER_EXECUTABLE:-IncNavierStokesSolver}"
solver_processes="${NEKTAR_SOLVER_NP:-${MPI_NP:-1}}"
solver_workdir="${NEKTAR_SOLVER_WORKDIR:-.}"

if (($# == 0)); then
    cat <<'EOF'
Usage: scripts/nektar/incnavierstokes_docker.sh SOLVER_ARGUMENT...

Run IncNavierStokesSolver from the same pinned full Nektar++ image used by
FieldConvert. Paths are relative to the repository root, which is mounted at
/data. Set NEKTAR_SOLVER_WORKDIR to a repository-relative run directory when
session outputs should be isolated there. Set NEKTAR_SOLVER_NP for the MPI
rank count; it falls back to MPI_NP from the environment, then to 1.

Examples:
  scripts/nektar/incnavierstokes_docker.sh --help
  NEKTAR_SOLVER_WORKDIR=nektar/naca0012-periodic/run \
    scripts/nektar/incnavierstokes_docker.sh -f mesh.xml session.xml
EOF
    exit 2
fi

[[ "$solver_processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "NEKTAR_SOLVER_NP must be a positive integer: $solver_processes" >&2
    exit 2
}
solver_command=("$solver_executable" "$@")
if ((solver_processes > 1)); then
    solver_command=(mpirun -np "$solver_processes" "${solver_command[@]}")
fi
if [[ "$solver_workdir" == /* || "$solver_workdir" == *:* ||
    "$solver_workdir" == .. || "$solver_workdir" == ../* ||
    "$solver_workdir" == */../* || "$solver_workdir" == */.. ]]; then
    echo "NEKTAR_SOLVER_WORKDIR must stay inside the repository: $solver_workdir" >&2
    exit 2
fi
[[ -d "$project_dir/$solver_workdir" ]] || {
    echo "Solver work directory does not exist: $solver_workdir" >&2
    exit 1
}

container_workdir="/data"
[[ "$solver_workdir" == . ]] || container_workdir="/data/$solver_workdir"

echo "Nektar solver ranks : $solver_processes" >&2
run_nektar_tool "Nektar solver" "$container_workdir" "${solver_command[@]}"
