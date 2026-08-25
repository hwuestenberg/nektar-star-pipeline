#!/usr/bin/env bash
# Run FieldConvert from the full Nektar++ OCI image with Docker or Apptainer.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
source "$script_dir/container_images.sh"
source "$script_dir/run_nektar_tool.sh"

fieldconvert_processes="${NEKTAR_FIELDCONVERT_NP:-1}"

if (($# == 0)); then
    cat <<'EOF'
Usage: scripts/nektar/fieldconvert_docker.sh FIELDCONVERT_ARGUMENT...

Examples:
  scripts/nektar/fieldconvert_docker.sh -h
  scripts/nektar/fieldconvert_docker.sh -l
  scripts/nektar/fieldconvert_docker.sh mesh.xml solution.fld solution.vtu

Paths passed to FieldConvert must be relative to the tutorial root. The root
is mounted at /data inside the container. Docker is preferred when installed;
otherwise Apptainer is used. Override the runtime with
NEKTAR_CONTAINER_RUNTIME and the pinned full image with
NEKTAR_CONTAINER_IMAGE:

  NEKTAR_CONTAINER_IMAGE=nektarpp/nektar:latest \
    scripts/nektar/fieldconvert_docker.sh -h

Set NEKTAR_FIELDCONVERT_NP to run FieldConvert with MPI, for example:

  NEKTAR_FIELDCONVERT_NP=16 \
    scripts/nektar/fieldconvert_docker.sh -m wss:bnd=0 session.xml field.fld wss.fld
EOF
    exit 2
fi

[[ "$fieldconvert_processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "NEKTAR_FIELDCONVERT_NP must be a positive integer: $fieldconvert_processes" >&2
    exit 2
}
fieldconvert_command=(FieldConvert "$@")
if ((fieldconvert_processes > 1)); then
    fieldconvert_command=(mpirun -np "$fieldconvert_processes" "${fieldconvert_command[@]}")
fi

echo "FieldConvert ranks : $fieldconvert_processes" >&2
run_nektar_tool FieldConvert /data "${fieldconvert_command[@]}"
