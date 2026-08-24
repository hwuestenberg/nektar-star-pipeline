#!/usr/bin/env bash
# Run FieldConvert from the full Nektar++ OCI image with Docker or Apptainer.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
source "$script_dir/container_images.sh"

nektar_image="${NEKTAR_CONTAINER_IMAGE:-$NEKTAR_IMAGE_DEFAULT}"
container_runtime="${NEKTAR_CONTAINER_RUNTIME:-auto}"

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
EOF
    exit 2
fi

if [[ "$nektar_image" == docker://* ]]; then
    echo "Image must not include the docker:// prefix: $nektar_image" >&2
    exit 2
fi

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

case "$container_runtime" in
    docker)
        command -v docker >/dev/null 2>&1 || {
            echo "Docker is not available." >&2
            exit 127
        }
        echo "FieldConvert runtime: Docker" >&2
        echo "Nektar++ image      : $nektar_image" >&2
        exec docker run --rm \
            --user "$(id -u):$(id -g)" \
            --mount "type=bind,src=$project_dir,dst=/data" \
            --workdir /data \
            "$nektar_image" \
            FieldConvert "$@"
        ;;
    apptainer)
        if [[ ! -x "$apptainer_executable" ]]; then
            echo "Apptainer is not available." >&2
            exit 127
        fi
        echo "FieldConvert runtime: Apptainer ($apptainer_executable)" >&2
        echo "Nektar++ image      : docker://$nektar_image" >&2
        exec "$apptainer_executable" exec \
            --cleanenv \
            --bind "$project_dir:/data" \
            --pwd /data \
            "docker://$nektar_image" \
            FieldConvert "$@"
        ;;
    *)
        echo "Unknown NEKTAR_CONTAINER_RUNTIME: $container_runtime" >&2
        exit 2
        ;;
esac
