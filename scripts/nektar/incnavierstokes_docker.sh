#!/usr/bin/env bash
# Run IncNavierStokesSolver from the pinned full Nektar++ OCI image.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
source "$script_dir/container_images.sh"

nektar_image="${NEKTAR_CONTAINER_IMAGE:-$NEKTAR_IMAGE_DEFAULT}"
solver_executable="${NEKTAR_SOLVER_EXECUTABLE:-IncNavierStokesSolver}"
solver_processes="${NEKTAR_SOLVER_NP:-1}"
container_runtime="${NEKTAR_CONTAINER_RUNTIME:-auto}"
solver_workdir="${NEKTAR_SOLVER_WORKDIR:-.}"

if (($# == 0)); then
    cat <<'EOF'
Usage: scripts/nektar/incnavierstokes_docker.sh SOLVER_ARGUMENT...

Run IncNavierStokesSolver from the same pinned full Nektar++ image used by
FieldConvert. Paths are relative to the repository root, which is mounted at
/data. Set NEKTAR_SOLVER_WORKDIR to a repository-relative run directory when
session outputs should be isolated there.

Examples:
  scripts/nektar/incnavierstokes_docker.sh --help
  NEKTAR_SOLVER_WORKDIR=nektar/naca0012-periodic/run \
    scripts/nektar/incnavierstokes_docker.sh -f mesh.xml session.xml
EOF
    exit 2
fi

if [[ "$nektar_image" == docker://* ]]; then
    echo "Image must not include docker://: $nektar_image" >&2
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

apptainer_executable="${APPTAINER_EXECUTABLE:-}"
if [[ -n "$apptainer_executable" && "$apptainer_executable" != */* ]]; then
    apptainer_executable="$(command -v -- "$apptainer_executable" || true)"
elif [[ -z "$apptainer_executable" ]]; then
    apptainer_executable="$(command -v apptainer || true)"
fi

if [[ "$container_runtime" == auto ]]; then
    if command -v docker >/dev/null 2>&1; then
        container_runtime=docker
    elif [[ -x "$apptainer_executable" ]]; then
        container_runtime=apptainer
    else
        echo "Neither Docker nor Apptainer is available." >&2
        exit 127
    fi
fi

container_workdir="/data"
[[ "$solver_workdir" == . ]] || container_workdir="/data/$solver_workdir"

case "$container_runtime" in
    docker)
        command -v docker >/dev/null 2>&1 || {
            echo "Docker is not available." >&2
            exit 127
        }
        echo "Nektar solver runtime: Docker" >&2
        echo "Nektar++ image       : $nektar_image" >&2
        echo "Nektar solver ranks  : $solver_processes" >&2
        exec docker run --rm \
            --user "$(id -u):$(id -g)" \
            --mount "type=bind,src=$project_dir,dst=/data" \
            --workdir "$container_workdir" \
            "$nektar_image" \
            "${solver_command[@]}"
        ;;
    apptainer)
        [[ -x "$apptainer_executable" ]] || {
            echo "Apptainer is not available." >&2
            exit 127
        }
        echo "Nektar solver runtime: Apptainer ($apptainer_executable)" >&2
        echo "Nektar++ image       : docker://$nektar_image" >&2
        echo "Nektar solver ranks  : $solver_processes" >&2
        exec "$apptainer_executable" exec \
            --cleanenv \
            --bind "$project_dir:/data" \
            --pwd "$container_workdir" \
            "docker://$nektar_image" \
            "${solver_command[@]}"
        ;;
    *)
        echo "Unknown NEKTAR_CONTAINER_RUNTIME: $container_runtime" >&2
        exit 2
        ;;
esac
