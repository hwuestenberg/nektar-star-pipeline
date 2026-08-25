#!/usr/bin/env bash
# Shared Docker/Apptainer dispatch for the pinned full Nektar++ image.
#
# Internal helper sourced by nekmesh_docker.sh, fieldconvert_docker.sh and
# incnavierstokes_docker.sh. Not intended for direct invocation.
#
# Defines run_nektar_tool LABEL WORKDIR COMMAND...
#   LABEL    short name used in diagnostic stderr lines, e.g. "NekMesh"
#   WORKDIR  container-absolute working directory, e.g. /data or
#            /data/nektar/naca0012-periodic/run
#   COMMAND  argv to execute inside the container (already MPI-wrapped by
#            the caller when applicable)
#
# The caller must set project_dir and source container_images.sh first, and
# may export NEKTAR_CONTAINER_IMAGE, NEKTAR_CONTAINER_RUNTIME and
# APPTAINER_EXECUTABLE to override the defaults.

run_nektar_tool() {
    local label="$1" workdir="$2"
    shift 2
    local command=("$@")

    local nektar_image="${NEKTAR_CONTAINER_IMAGE:-$NEKTAR_IMAGE_DEFAULT}"
    local container_runtime="${NEKTAR_CONTAINER_RUNTIME:-auto}"

    if [[ "$nektar_image" == docker://* ]]; then
        echo "Image must not include docker://: $nektar_image" >&2
        exit 2
    fi

    local apptainer_executable="${APPTAINER_EXECUTABLE:-}"
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
            echo "$label runtime: Docker" >&2
            echo "Nektar++ image : $nektar_image" >&2
            exec docker run --rm \
                --user "$(id -u):$(id -g)" \
                --mount "type=bind,src=$project_dir,dst=/data" \
                --workdir "$workdir" \
                "$nektar_image" \
                "${command[@]}"
            ;;
        apptainer)
            [[ -x "$apptainer_executable" ]] || {
                echo "Apptainer is not available." >&2
                exit 127
            }
            echo "$label runtime: Apptainer ($apptainer_executable)" >&2
            echo "Nektar++ image : docker://$nektar_image" >&2
            exec "$apptainer_executable" exec \
                --cleanenv \
                --bind "$project_dir:/data" \
                --pwd "$workdir" \
                "docker://$nektar_image" \
                "${command[@]}"
            ;;
        *)
            echo "Unknown NEKTAR_CONTAINER_RUNTIME: $container_runtime" >&2
            exit 2
            ;;
    esac
}
