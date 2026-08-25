#!/usr/bin/env bash
# Run NekMesh from the pinned full Nektar++ OCI image.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
source "$script_dir/container_images.sh"
source "$script_dir/run_nektar_tool.sh"

if (($# == 0)); then
    cat <<'EOF'
Usage: scripts/nektar/nekmesh_docker.sh NEKMESH_ARGUMENT...

Examples:
  scripts/nektar/nekmesh_docker.sh -l
  scripts/nektar/nekmesh_docker.sh -v \
      star/naca0012_linear.ccm nekmesh/naca0012_linear.xml

Paths passed to NekMesh must be relative to the tutorial root. The root is
mounted at /data inside the container. Docker is preferred when installed;
otherwise Apptainer is used.

Override the runtime with NEKTAR_CONTAINER_RUNTIME=docker or apptainer, and
the Apptainer command/path with APPTAINER_EXECUTABLE. Override
the pinned full image with NEKTAR_CONTAINER_IMAGE. The same image is used for
NekMesh, FieldConvert and IncNavierStokesSolver. Image values must be registry
references without docker://.
EOF
    exit 2
fi

run_nektar_tool NekMesh /data NekMesh "$@"
