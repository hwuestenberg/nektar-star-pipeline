#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case_config="${STAR_NEKTAR_CASE_CONFIG:-cases/naca0012-periodic/case.env}"
site_config="${STAR_NEKTAR_SITE_CONFIG:-config/site.env}"

cd "$project_dir"

if [[ ! -f "$case_config" ]]; then
    echo "Case configuration does not exist: $case_config" >&2
    exit 1
fi
# The case file is version-controlled as part of this repository.
# shellcheck source=cases/naca0012-periodic/case.env
source "$case_config"

if [[ -f "$site_config" ]]; then
    # The site file is user-owned and deliberately ignored by Git.
    # shellcheck disable=SC1090
    source "$site_config"
else
    echo "Site configuration not found: $site_config" >&2
    echo "Copy config/site.env.example to config/site.env and edit it." >&2
    exit 1
fi

for environment_variable in \
    NEKTAR_CONTAINER_RUNTIME APPTAINER_EXECUTABLE \
    NEKTAR_CONTAINER_IMAGE; do
    if [[ -n "${!environment_variable:-}" ]]; then
        export "$environment_variable"
    fi
done

required_variables=(
    CASE_NAME STAR_TEMPLATE MPI_NP STAR_LICENSE_MODE
    PERIODIC_SURF1 PERIODIC_SURF2 PERIODIC_DIR
    PERIODIC_TRANSLATION_X PERIODIC_TRANSLATION_Y PERIODIC_TRANSLATION_Z
    STAR_PERIODIC_INTERFACE
    RANS_REYNOLDS RANS_MAX_STEPS RANS_MIN_STEPS RANS_RESIDUAL_TOL
    RANS_ALLOW_UNCONVERGED RANS_NUM_MODES
    CAD_ORDER BL_SURFACE BL_LAYERS BL_RATIO
)
for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required configuration variable is unset: $variable_name" >&2
        exit 1
    fi
done

processes="$MPI_NP"
if [[ ! "$processes" =~ ^[1-9][0-9]*$ ]]; then
    echo "MPI_NP must be a positive integer: $processes" >&2
    exit 2
fi

pipeline_args=(
    --force
    --star-template "$STAR_TEMPLATE"
    --name "$CASE_NAME"
    --ccm-file "star/${CASE_NAME}_linear.ccm"
    --star-np "$processes"
    --rans-np "$processes"
    --periodic-span
    --periodic-surf1 "$PERIODIC_SURF1"
    --periodic-surf2 "$PERIODIC_SURF2"
    --periodic-dir "$PERIODIC_DIR"
    --periodic-translation-x "$PERIODIC_TRANSLATION_X"
    --periodic-translation-y "$PERIODIC_TRANSLATION_Y"
    --periodic-translation-z "$PERIODIC_TRANSLATION_Z"
    --star-periodic-interface "$STAR_PERIODIC_INTERFACE"
    --run-rans
    --rans-reynolds "$RANS_REYNOLDS"
    --rans-max-steps "$RANS_MAX_STEPS"
    --rans-min-steps "$RANS_MIN_STEPS"
    --rans-residual-tol "$RANS_RESIDUAL_TOL"
    --rans-session auto
    --rans-num-modes "$RANS_NUM_MODES"
    --cad-order "$CAD_ORDER"
    --bl-surface "$BL_SURFACE"
    --bl-layers "$BL_LAYERS"
    --bl-ratio "$BL_RATIO"
)

case "$RANS_ALLOW_UNCONVERGED" in
true)
    pipeline_args+=(--rans-allow-unconverged)
    ;;
false) ;;
*)
    echo "RANS_ALLOW_UNCONVERGED must be true or false." >&2
    exit 2
    ;;
esac

if [[ -n "${STAR_STEP:-}" ]]; then
    if [[ -s "$STAR_TEMPLATE" ]]; then
        printf '[execute] reusing validated STAR template: %s\n' "$STAR_TEMPLATE"
    else
        printf '[execute] STAR template is absent; bootstrapping it from STEP\n'
        pipeline_args+=(--star-step "$STAR_STEP")
    fi
fi

if [[ -n "${STAR_EXECUTABLE:-}" ]]; then
    pipeline_args+=(--star-executable "$STAR_EXECUTABLE")
fi

# Forward explicit workflow overrides after the configured defaults. In
# particular, ./execute.sh --diagnostic restores all tutorial checkpoints.
pipeline_args+=("$@")

case "$STAR_LICENSE_MODE" in
default)
    ./scripts/workflow/run_remote_pipeline.sh "${pipeline_args[@]}"
    ;;
power-on-demand)
    read -rsp 'STAR PoD key: ' star_pod_key
    printf '\n'
    trap 'unset star_pod_key' EXIT
    STAR_POD_KEY="$star_pod_key" \
        ./scripts/workflow/run_remote_pipeline.sh \
        "${pipeline_args[@]}" --power-on-demand
    ;;
*)
    echo "Unsupported STAR_LICENSE_MODE: $STAR_LICENSE_MODE" >&2
    echo "Expected 'default' or 'power-on-demand'." >&2
    exit 2
    ;;
esac

solver_steps="${NEKTAR_SOLVER_STEPS:-100}"
wing_boundary="${NEKTAR_WING_BOUNDARY:-0}"
solver_session="${NEKTAR_SESSION:-nektar/naca0012-periodic/session.xml}"
solver_run_dir="${NEKTAR_RUN_DIR:-nektar/naca0012-periodic/run}"
if [[ ! "$solver_steps" =~ ^[1-9][0-9]*$ ]]; then
    echo "NEKTAR_SOLVER_STEPS must be a positive integer: $solver_steps" >&2
    exit 2
fi
if [[ ! "$wing_boundary" =~ ^[0-9]+$ ]]; then
    echo "NEKTAR_WING_BOUNDARY must be a non-negative integer: $wing_boundary" >&2
    exit 2
fi
for path in "$solver_session" "$solver_run_dir"; do
    [[ "$path" != /* && "$path" != *:* && "$path" != .. &&
        "$path" != ../* && "$path" != */../* && "$path" != */.. ]] || {
        echo "Nektar solver paths must be repository-relative: $path" >&2
        exit 2
    }
done
final_mesh="nekmesh/${CASE_NAME}_p${CAD_ORDER}_bl${BL_LAYERS}.xml"
restart_field="nekmesh/${CASE_NAME}_rans_initial.fld"

printf '\n[execute] mesh/restart pipeline completed; starting Nektar++ solver\n'
./scripts/workflow/run_nektar_solver.sh \
    --force \
    --mesh "$final_mesh" \
    --restart "$restart_field" \
    --session "$solver_session" \
    --run-dir "$solver_run_dir" \
    --steps "$solver_steps" \
    --reynolds "$RANS_REYNOLDS" \
    --np "$processes"

printf '\n[execute] complete: Nektar++ solver\n'
printf '[execute] run directory: %s\n' "$solver_run_dir"

printf '\n[execute] postprocessing wall quantities: wall shear stress and pressure\n'
./scripts/workflow/run_nektar_postprocess.sh \
    --mesh "$final_mesh" \
    --session "$solver_run_dir/session.xml" \
    --field "$solver_run_dir/mean_fields_avg.fld" \
    --output-dir "$solver_run_dir" \
    --prefix mean_fields_wss \
    --boundary "$wing_boundary" \
    --surface "$BL_SURFACE" \
    --np "$processes" \
    --force

printf '\n[execute] complete: mesh, restart, solver, WSS and pressure outputs validated\n'
printf '[execute] run directory: %s\n' "$solver_run_dir"
