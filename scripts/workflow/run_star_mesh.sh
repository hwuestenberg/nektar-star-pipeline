#!/usr/bin/env bash
# Rebuild the STAR volume mesh from a prepared .sim template and export CCM.

set -euo pipefail

default_star_executable="${STAR_EXECUTABLE:-starccm+}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"

template="star/naca0012_mesh_template.sim"
output_sim="star/naca0012_meshed.sim"
output_ccm="star/naca0012_linear.ccm"
log_file="star/naca0012_star_batch.log"
provenance_file="star/naca0012_linear.provenance.txt"
macro_file="$project_dir/scripts/star/ExportCcm.java"
configure_macro="$project_dir/scripts/star/ConfigureMesh.java"
star_executable="$default_star_executable"
processes=1
force=false
dry_run=false
power_on_demand=false
mesh_operation="NACA0012_AutomatedMesh"
wing_control="WingSurfaceControl"
volume_control="WingVolumeControl"
volume_part="WingRefinement"
base_size_m="1.0"
surface_target_pct="50.0"
surface_min_pct="1.0"
max_cell_pct="10000.0"
tet_growth_rate="1.2"
wing_target_pct="2.0"
wing_min_pct="0.25"
wing_curvature_points="36.0"
prism_height_m="0.03"
prism_layers="1"
prism_stretching="1.5"
volume_size_pct="5.0"
volume_x_min_m="-0.25"
volume_x_max_m="1.50"
volume_y_min_m="-0.30"
volume_y_max_m="0.30"
volume_z_min_m="-0.01"
volume_z_max_m="0.21"
extra_star_args=()

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_star_mesh.sh [options] [-- STAR_OPTIONS...]

Generate the configured STAR mesh headlessly from a prepared simulation,
export a mesh-only CCM file, and save the meshed simulation.

Options:
  --template FILE       Input .sim template
                        (default: star/naca0012_mesh_template.sim)
  --output-sim FILE     Saved meshed simulation
                        (default: star/naca0012_meshed.sim)
  --output-ccm FILE     Mesh-only CCM export
                        (default: star/naca0012_linear.ccm)
  --log FILE            STAR stdout/stderr log
                        (default: star/naca0012_star_batch.log)
  --provenance FILE     Reproducibility metadata
                        (default: star/naca0012_linear.provenance.txt)
  --np N                STAR process count (default: 1)
  --mesh-operation NAME Automated Mesh operation name
                        (default: NACA0012_AutomatedMesh)
  --wing-control NAME   Wing Surface Custom Mesh Control name
                        (default: WingSurfaceControl)
  --volume-control NAME Volumetric Custom Mesh Control name; created if absent
                        (default: WingVolumeControl)
  --volume-part NAME    Block shape-part name; created if absent
                        (default: WingRefinement)
  --base-size M         STAR base size in metres (default: 1.0)
  --surface-target-pct P
                        Global target surface size as % of base (default: 50)
  --surface-min-pct P   Global minimum surface size as % of base (default: 1)
  --max-cell-pct P      Maximum tet cell size as % of base (default: 10000)
  --tet-growth R        Tet volume growth rate, 1 < R <= 2 (default: 1.2)
  --wing-target-pct P   Wing target surface size as % of base (default: 2)
  --wing-min-pct P      Wing minimum surface size as % of base (default: 0.25)
  --wing-curvature-points N
                        Wing points around a full circle (default: 36)
  --prism-height M      Total STAR prism-stack height in metres (default: 0.03)
  --prism-layers N      STAR prism count through the stack (default: 1)
  --prism-stretching R  STAR prism stretching, R >= 1 (default: 1.5)
  --volume-size-pct P   Refinement size as % of base (default: 5)
  --volume-x-min M      Refinement-box minimum x in metres (default: -0.25)
  --volume-x-max M      Refinement-box maximum x in metres (default: 1.50)
  --volume-y-min M      Refinement-box minimum y in metres (default: -0.30)
  --volume-y-max M      Refinement-box maximum y in metres (default: 0.30)
  --volume-z-min M      Refinement-box minimum z in metres (default: -0.01)
  --volume-z-max M      Refinement-box maximum z in metres (default: 0.21)
  --star-executable FILE
                        STAR launcher command or path (default: STAR_EXECUTABLE
                        or starccm+ resolved through PATH)
  --power-on-demand     Use a STAR Power Session with the PoD key read from
                        STAR_POD_KEY (the key is never printed or recorded)
  --force               Replace existing output files after a successful run
  --dry-run             Validate and print the command without running STAR
  -h, --help            Show this help

Relative paths are resolved from the tutorial root, not the caller's current
directory. Arguments after -- are inserted before STAR's -batch option.

The input template is never modified. Outputs are first written to a private
staging directory and are published only after STAR exits successfully and the
CCM file passes basic validation.
EOF
}

while (($#)); do
    case "$1" in
        --template)
            [[ $# -ge 2 ]] || {
                echo "--template requires a value" >&2
                exit 2
            }
            template="$2"
            shift 2
            ;;
        --output-sim)
            [[ $# -ge 2 ]] || {
                echo "--output-sim requires a value" >&2
                exit 2
            }
            output_sim="$2"
            shift 2
            ;;
        --output-ccm)
            [[ $# -ge 2 ]] || {
                echo "--output-ccm requires a value" >&2
                exit 2
            }
            output_ccm="$2"
            shift 2
            ;;
        --log)
            [[ $# -ge 2 ]] || {
                echo "--log requires a value" >&2
                exit 2
            }
            log_file="$2"
            shift 2
            ;;
        --provenance)
            [[ $# -ge 2 ]] || {
                echo "--provenance requires a value" >&2
                exit 2
            }
            provenance_file="$2"
            shift 2
            ;;
        --np)
            [[ $# -ge 2 ]] || {
                echo "--np requires a value" >&2
                exit 2
            }
            processes="$2"
            shift 2
            ;;
        --mesh-operation)
            [[ $# -ge 2 ]] || {
                echo "--mesh-operation requires a value" >&2
                exit 2
            }
            mesh_operation="$2"
            shift 2
            ;;
        --wing-control)
            [[ $# -ge 2 ]] || {
                echo "--wing-control requires a value" >&2
                exit 2
            }
            wing_control="$2"
            shift 2
            ;;
        --volume-control)
            [[ $# -ge 2 ]] || {
                echo "--volume-control requires a value" >&2
                exit 2
            }
            volume_control="$2"
            shift 2
            ;;
        --volume-part)
            [[ $# -ge 2 ]] || {
                echo "--volume-part requires a value" >&2
                exit 2
            }
            volume_part="$2"
            shift 2
            ;;
        --base-size)
            [[ $# -ge 2 ]] || {
                echo "--base-size requires a value" >&2
                exit 2
            }
            base_size_m="$2"
            shift 2
            ;;
        --surface-target-pct)
            [[ $# -ge 2 ]] || {
                echo "--surface-target-pct requires a value" >&2
                exit 2
            }
            surface_target_pct="$2"
            shift 2
            ;;
        --surface-min-pct)
            [[ $# -ge 2 ]] || {
                echo "--surface-min-pct requires a value" >&2
                exit 2
            }
            surface_min_pct="$2"
            shift 2
            ;;
        --max-cell-pct)
            [[ $# -ge 2 ]] || {
                echo "--max-cell-pct requires a value" >&2
                exit 2
            }
            max_cell_pct="$2"
            shift 2
            ;;
        --tet-growth)
            [[ $# -ge 2 ]] || {
                echo "--tet-growth requires a value" >&2
                exit 2
            }
            tet_growth_rate="$2"
            shift 2
            ;;
        --wing-target-pct)
            [[ $# -ge 2 ]] || {
                echo "--wing-target-pct requires a value" >&2
                exit 2
            }
            wing_target_pct="$2"
            shift 2
            ;;
        --wing-min-pct)
            [[ $# -ge 2 ]] || {
                echo "--wing-min-pct requires a value" >&2
                exit 2
            }
            wing_min_pct="$2"
            shift 2
            ;;
        --wing-curvature-points)
            [[ $# -ge 2 ]] || {
                echo "--wing-curvature-points requires a value" >&2
                exit 2
            }
            wing_curvature_points="$2"
            shift 2
            ;;
        --prism-height)
            [[ $# -ge 2 ]] || {
                echo "--prism-height requires a value" >&2
                exit 2
            }
            prism_height_m="$2"
            shift 2
            ;;
        --prism-layers)
            [[ $# -ge 2 ]] || {
                echo "--prism-layers requires a value" >&2
                exit 2
            }
            prism_layers="$2"
            shift 2
            ;;
        --prism-stretching)
            [[ $# -ge 2 ]] || {
                echo "--prism-stretching requires a value" >&2
                exit 2
            }
            prism_stretching="$2"
            shift 2
            ;;
        --volume-size-pct)
            [[ $# -ge 2 ]] || {
                echo "--volume-size-pct requires a value" >&2
                exit 2
            }
            volume_size_pct="$2"
            shift 2
            ;;
        --volume-x-min)
            [[ $# -ge 2 ]] || {
                echo "--volume-x-min requires a value" >&2
                exit 2
            }
            volume_x_min_m="$2"
            shift 2
            ;;
        --volume-x-max)
            [[ $# -ge 2 ]] || {
                echo "--volume-x-max requires a value" >&2
                exit 2
            }
            volume_x_max_m="$2"
            shift 2
            ;;
        --volume-y-min)
            [[ $# -ge 2 ]] || {
                echo "--volume-y-min requires a value" >&2
                exit 2
            }
            volume_y_min_m="$2"
            shift 2
            ;;
        --volume-y-max)
            [[ $# -ge 2 ]] || {
                echo "--volume-y-max requires a value" >&2
                exit 2
            }
            volume_y_max_m="$2"
            shift 2
            ;;
        --volume-z-min)
            [[ $# -ge 2 ]] || {
                echo "--volume-z-min requires a value" >&2
                exit 2
            }
            volume_z_min_m="$2"
            shift 2
            ;;
        --volume-z-max)
            [[ $# -ge 2 ]] || {
                echo "--volume-z-max requires a value" >&2
                exit 2
            }
            volume_z_max_m="$2"
            shift 2
            ;;
        --star-executable)
            [[ $# -ge 2 ]] || {
                echo "--star-executable requires a value" >&2
                exit 2
            }
            star_executable="$2"
            shift 2
            ;;
        --force)
            force=true
            shift
            ;;
        --power-on-demand)
            power_on_demand=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            extra_star_args=("$@")
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for star_arg in "${extra_star_args[@]}"; do
    if [[ "$star_arg" == -podkey || "$star_arg" == -podkey=* ]]; then
        echo "Do not pass a PoD key on the command line." >&2
        echo "Use --power-on-demand with the STAR_POD_KEY environment variable." >&2
        exit 2
    fi
done

license_mode="default"
pod_key=""
if [[ "$power_on_demand" == true ]]; then
    if [[ -z "${STAR_POD_KEY:-}" ]]; then
        echo "--power-on-demand requires the STAR_POD_KEY environment variable." >&2
        exit 2
    fi
    for star_arg in "${extra_star_args[@]}"; do
        if [[ "$star_arg" == -power || "$star_arg" == -powerpre ]]; then
            echo "Do not combine --power-on-demand with $star_arg." >&2
            exit 2
        fi
    done
    license_mode="power-on-demand"
    pod_key="$STAR_POD_KEY"
    unset STAR_POD_KEY
    extra_star_args=(-power "${extra_star_args[@]}")
fi

absolute_path() {
    if [[ "$1" == /* ]]; then
        realpath -m -- "$1"
    else
        realpath -m -- "$project_dir/$1"
    fi
}

template="$(absolute_path "$template")"
output_sim="$(absolute_path "$output_sim")"
output_ccm="$(absolute_path "$output_ccm")"
log_file="$(absolute_path "$log_file")"
provenance_file="$(absolute_path "$provenance_file")"
if [[ "$star_executable" == */* ]]; then
    star_executable="$(absolute_path "$star_executable")"
else
    resolved_star_executable="$(command -v -- "$star_executable" || true)"
    if [[ -n "$resolved_star_executable" ]]; then
        star_executable="$resolved_star_executable"
    fi
fi

if [[ ! -f "$template" ]]; then
    echo "STAR template does not exist: $template" >&2
    exit 1
fi
if [[ ! -f "$macro_file" ]]; then
    echo "STAR export macro does not exist: $macro_file" >&2
    exit 1
fi
if [[ ! -f "$configure_macro" ]]; then
    echo "STAR configuration macro does not exist: $configure_macro" >&2
    exit 1
fi
if { [[ "$star_executable" == */* ]] && [[ ! -x "$star_executable" ]]; } ||
    { [[ "$star_executable" != */* ]] && ! command -v -- "$star_executable" >/dev/null 2>&1; }; then
    if [[ "$dry_run" == true ]]; then
        :
    else
        echo "STAR executable is missing or not executable: $star_executable" >&2
        exit 1
    fi
fi
if [[ ! "$processes" =~ ^[1-9][0-9]*$ ]]; then
    echo "--np must be a positive integer: $processes" >&2
    exit 2
fi
if [[ ! "$prism_layers" =~ ^[1-9][0-9]*$ ]]; then
    echo "--prism-layers must be a positive integer: $prism_layers" >&2
    exit 2
fi

validate_number() {
    local option="$1"
    local value="$2"
    local predicate="$3"
    if ! awk -v value="$value" "BEGIN { exit !($predicate) }"; then
        echo "$option has an invalid value: $value" >&2
        exit 2
    fi
}

validate_real_number() {
    local option="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$ ]]; then
        echo "$option must be a finite number: $value" >&2
        exit 2
    fi
}

validate_number --base-size "$base_size_m" 'value > 0'
validate_number --surface-target-pct "$surface_target_pct" 'value > 0'
validate_number --surface-min-pct "$surface_min_pct" 'value > 0'
validate_number --max-cell-pct "$max_cell_pct" 'value > 0'
validate_number --tet-growth "$tet_growth_rate" 'value > 1 && value <= 2'
validate_number --wing-target-pct "$wing_target_pct" 'value > 0'
validate_number --wing-min-pct "$wing_min_pct" 'value > 0'
validate_number --wing-curvature-points "$wing_curvature_points" 'value >= 3'
validate_number --prism-height "$prism_height_m" 'value > 0'
validate_number --prism-stretching "$prism_stretching" 'value >= 1'
validate_number --volume-size-pct "$volume_size_pct" 'value > 0'
validate_real_number --volume-x-min "$volume_x_min_m"
validate_real_number --volume-x-max "$volume_x_max_m"
validate_real_number --volume-y-min "$volume_y_min_m"
validate_real_number --volume-y-max "$volume_y_max_m"
validate_real_number --volume-z-min "$volume_z_min_m"
validate_real_number --volume-z-max "$volume_z_max_m"

if ! awk -v minimum="$surface_min_pct" -v target="$surface_target_pct" \
    'BEGIN { exit !(minimum <= target) }'; then
    echo "--surface-min-pct must not exceed --surface-target-pct." >&2
    exit 2
fi
if ! awk -v minimum="$wing_min_pct" -v target="$wing_target_pct" \
    'BEGIN { exit !(minimum <= target) }'; then
    echo "--wing-min-pct must not exceed --wing-target-pct." >&2
    exit 2
fi
if ! awk -v lo="$volume_x_min_m" -v hi="$volume_x_max_m" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--volume-x-min must be less than --volume-x-max." >&2
    exit 2
fi
if ! awk -v lo="$volume_y_min_m" -v hi="$volume_y_max_m" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--volume-y-min must be less than --volume-y-max." >&2
    exit 2
fi
if ! awk -v lo="$volume_z_min_m" -v hi="$volume_z_max_m" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--volume-z-min must be less than --volume-z-max." >&2
    exit 2
fi

surface_target_m="$(awk -v b="$base_size_m" -v p="$surface_target_pct" 'BEGIN { printf "%.17g", b*p/100 }')"
surface_min_m="$(awk -v b="$base_size_m" -v p="$surface_min_pct" 'BEGIN { printf "%.17g", b*p/100 }')"
wing_target_m="$(awk -v b="$base_size_m" -v p="$wing_target_pct" 'BEGIN { printf "%.17g", b*p/100 }')"
wing_min_m="$(awk -v b="$base_size_m" -v p="$wing_min_pct" 'BEGIN { printf "%.17g", b*p/100 }')"
volume_size_m="$(awk -v b="$base_size_m" -v p="$volume_size_pct" 'BEGIN { printf "%.17g", b*p/100 }')"
prism_height_pct="$(awk -v b="$base_size_m" -v h="$prism_height_m" 'BEGIN { printf "%.17g", 100*h/b }')"
if [[ "$template" == "$output_sim" ]]; then
    echo "The input template and output simulation must be different files." >&2
    exit 2
fi

outputs=("$output_sim" "$output_ccm" "$log_file" "$provenance_file")
if [[ "$force" != true ]]; then
    for output in "${outputs[@]}"; do
        if [[ -e "$output" ]]; then
            echo "Output already exists (use --force to replace it): $output" >&2
            exit 1
        fi
    done
fi

mkdir -p -- \
    "$(dirname -- "$output_sim")" \
    "$(dirname -- "$output_ccm")" \
    "$(dirname -- "$log_file")" \
    "$(dirname -- "$provenance_file")"

stage_dir="$(mktemp -d "$(dirname -- "$output_sim")/.star-stage.XXXXXX")"
staged_sim="$stage_dir/$(basename -- "$output_sim")"
staged_ccm="$stage_dir/$(basename -- "$output_ccm")"
cp --preserve=mode,timestamps -- "$template" "$staged_sim"

batch_spec="$configure_macro,mesh,$macro_file"
command=(
    "$star_executable"
    -np "$processes"
    "${extra_star_args[@]}"
    -batch "$batch_spec"
    "$staged_sim"
)

echo "Template      : $template"
echo "Staged SIM    : $staged_sim"
echo "Output SIM    : $output_sim"
echo "Output CCM    : $output_ccm"
echo "Batch log     : $log_file"
echo "License mode  : $license_mode"
echo "Base size     : $base_size_m m"
echo "Wing target   : $wing_target_pct % of base"
echo "Volume refine : $volume_size_pct % of base ($volume_size_m m)"
echo "Volume box    : ($volume_x_min_m, $volume_y_min_m, $volume_z_min_m) -> ($volume_x_max_m, $volume_y_max_m, $volume_z_max_m) m"
echo "Prism stack   : $prism_height_m m, $prism_layers STAR layer(s)"
printf 'Command       :'
printf ' %q' "${command[@]}"
printf '\n'

if [[ "$dry_run" == true ]]; then
    echo "Dry run only; STAR was not executed."
    rm -f -- "$staged_sim"
    rmdir -- "$stage_dir" 2>/dev/null || true
    exit 0
fi

set +e
if [[ "$power_on_demand" == true ]]; then
    LM_PROJECT="$pod_key" \
        STAR_MESH_OPERATION="$mesh_operation" \
        STAR_WING_CONTROL="$wing_control" \
        STAR_VOLUME_CONTROL="$volume_control" \
        STAR_VOLUME_PART="$volume_part" \
        STAR_BASE_SIZE_M="$base_size_m" \
        STAR_SURFACE_TARGET_PCT="$surface_target_pct" \
        STAR_SURFACE_MIN_PCT="$surface_min_pct" \
        STAR_MAX_CELL_PCT="$max_cell_pct" \
        STAR_TET_GROWTH_RATE="$tet_growth_rate" \
        STAR_WING_TARGET_PCT="$wing_target_pct" \
        STAR_WING_MIN_PCT="$wing_min_pct" \
        STAR_WING_CURVATURE_POINTS="$wing_curvature_points" \
        STAR_PRISM_HEIGHT_M="$prism_height_m" \
        STAR_PRISM_LAYERS="$prism_layers" \
        STAR_PRISM_STRETCHING="$prism_stretching" \
        STAR_VOLUME_SIZE_PCT="$volume_size_pct" \
        STAR_VOLUME_X_MIN_M="$volume_x_min_m" \
        STAR_VOLUME_X_MAX_M="$volume_x_max_m" \
        STAR_VOLUME_Y_MIN_M="$volume_y_min_m" \
        STAR_VOLUME_Y_MAX_M="$volume_y_max_m" \
        STAR_VOLUME_Z_MIN_M="$volume_z_min_m" \
        STAR_VOLUME_Z_MAX_M="$volume_z_max_m" \
        STAR_SIM_OUTPUT="$staged_sim" \
        STAR_CCM_OUTPUT="$staged_ccm" \
        "${command[@]}" >"$log_file" 2>&1
else
    STAR_MESH_OPERATION="$mesh_operation" \
        STAR_WING_CONTROL="$wing_control" \
        STAR_VOLUME_CONTROL="$volume_control" \
        STAR_VOLUME_PART="$volume_part" \
        STAR_BASE_SIZE_M="$base_size_m" \
        STAR_SURFACE_TARGET_PCT="$surface_target_pct" \
        STAR_SURFACE_MIN_PCT="$surface_min_pct" \
        STAR_MAX_CELL_PCT="$max_cell_pct" \
        STAR_TET_GROWTH_RATE="$tet_growth_rate" \
        STAR_WING_TARGET_PCT="$wing_target_pct" \
        STAR_WING_MIN_PCT="$wing_min_pct" \
        STAR_WING_CURVATURE_POINTS="$wing_curvature_points" \
        STAR_PRISM_HEIGHT_M="$prism_height_m" \
        STAR_PRISM_LAYERS="$prism_layers" \
        STAR_PRISM_STRETCHING="$prism_stretching" \
        STAR_VOLUME_SIZE_PCT="$volume_size_pct" \
        STAR_VOLUME_X_MIN_M="$volume_x_min_m" \
        STAR_VOLUME_X_MAX_M="$volume_x_max_m" \
        STAR_VOLUME_Y_MIN_M="$volume_y_min_m" \
        STAR_VOLUME_Y_MAX_M="$volume_y_max_m" \
        STAR_VOLUME_Z_MIN_M="$volume_z_min_m" \
        STAR_VOLUME_Z_MAX_M="$volume_z_max_m" \
        STAR_SIM_OUTPUT="$staged_sim" \
        STAR_CCM_OUTPUT="$staged_ccm" \
        "${command[@]}" >"$log_file" 2>&1
fi
star_status=$?
pod_key=""
set -e

if ((star_status != 0)); then
    if grep -q 'Server process exited with code : 0' "$log_file" &&
        ! grep -q 'STAR_BATCH_MESH_CONFIGURED' "$log_file"; then
        echo "STAR's server exited normally, but a batch macro failed (launcher status $star_status)." >&2
        echo "The required STAR_BATCH_MESH_CONFIGURED marker is absent, so the" >&2
        echo "subsequent mesh/export may have used stale settings from the template." >&2
        echo "The staged outputs will not be published." >&2
    else
        echo "STAR failed with exit status $star_status." >&2
    fi
    echo "Log: $log_file" >&2
    echo "Staged files were retained for diagnosis: $stage_dir" >&2
    tail -n 40 -- "$log_file" >&2 || true
    exit "$star_status"
fi

if [[ ! -s "$staged_sim" ]]; then
    echo "STAR completed without producing a non-empty staged .sim file." >&2
    echo "Staged files were retained: $stage_dir" >&2
    exit 1
fi
if [[ ! -s "$staged_ccm" ]]; then
    echo "STAR completed without producing a non-empty staged .ccm file." >&2
    echo "Staged files were retained: $stage_dir" >&2
    exit 1
fi
if ! grep -q 'STAR_BATCH_EXPORT_COMPLETE' "$log_file"; then
    echo "STAR log does not contain the export completion marker." >&2
    echo "Staged files were retained: $stage_dir" >&2
    exit 1
fi
if ! grep -q 'STAR_BATCH_MESH_CONFIGURED' "$log_file"; then
    echo "STAR log does not contain the mesh configuration marker." >&2
    echo "Staged files were retained: $stage_dir" >&2
    exit 1
fi

mv -f -- "$staged_sim" "$output_sim"
mv -f -- "$staged_ccm" "$output_ccm"
# STAR may create a backup beside a simulation that was saved more than once.
# It is private staging data, never a published pipeline result.
rm -f -- "${staged_sim}~"
if ! rmdir -- "$stage_dir" 2>/dev/null; then
    echo "STAR left auxiliary files in the staging directory: $stage_dir"
fi

# Avoid starting another STAR process solely for provenance. Every normal
# batch log already contains the exact product/build line.
star_version="$(awk '/^Simcenter STAR-CCM\+/ {print; exit}' "$log_file")"
star_version="${star_version:-unknown}"
{
    printf 'generated_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'host=%s\n' "$(hostname)"
    printf 'star_executable=%s\n' "$star_executable"
    printf 'star_version=%s\n' "${star_version//$'\n'/ }"
    printf 'license_mode=%s\n' "$license_mode"
    printf 'processes=%s\n' "$processes"
    printf 'template=%s\n' "$template"
    printf 'template_sha256=%s\n' "$(sha256sum "$template" | awk '{print $1}')"
    printf 'macro=%s\n' "$macro_file"
    printf 'macro_sha256=%s\n' "$(sha256sum "$macro_file" | awk '{print $1}')"
    printf 'configure_macro=%s\n' "$configure_macro"
    printf 'configure_macro_sha256=%s\n' "$(sha256sum "$configure_macro" | awk '{print $1}')"
    printf 'mesh_operation=%s\n' "$mesh_operation"
    printf 'wing_control=%s\n' "$wing_control"
    printf 'volume_control=%s\n' "$volume_control"
    printf 'volume_part=%s\n' "$volume_part"
    printf 'base_size_m=%s\n' "$base_size_m"
    printf 'surface_target_pct=%s\n' "$surface_target_pct"
    printf 'surface_target_m=%s\n' "$surface_target_m"
    printf 'surface_min_pct=%s\n' "$surface_min_pct"
    printf 'surface_min_m=%s\n' "$surface_min_m"
    printf 'max_cell_pct=%s\n' "$max_cell_pct"
    printf 'tet_growth_rate=%s\n' "$tet_growth_rate"
    printf 'wing_target_pct=%s\n' "$wing_target_pct"
    printf 'wing_target_m=%s\n' "$wing_target_m"
    printf 'wing_min_pct=%s\n' "$wing_min_pct"
    printf 'wing_min_m=%s\n' "$wing_min_m"
    printf 'wing_curvature_points=%s\n' "$wing_curvature_points"
    printf 'volume_size_pct=%s\n' "$volume_size_pct"
    printf 'volume_size_m=%s\n' "$volume_size_m"
    printf 'volume_x_min_m=%s\n' "$volume_x_min_m"
    printf 'volume_x_max_m=%s\n' "$volume_x_max_m"
    printf 'volume_y_min_m=%s\n' "$volume_y_min_m"
    printf 'volume_y_max_m=%s\n' "$volume_y_max_m"
    printf 'volume_z_min_m=%s\n' "$volume_z_min_m"
    printf 'volume_z_max_m=%s\n' "$volume_z_max_m"
    printf 'prism_height_m=%s\n' "$prism_height_m"
    printf 'prism_height_pct=%s\n' "$prism_height_pct"
    printf 'prism_layers=%s\n' "$prism_layers"
    printf 'prism_stretching=%s\n' "$prism_stretching"
    printf 'output_sim=%s\n' "$output_sim"
    printf 'output_sim_sha256=%s\n' "$(sha256sum "$output_sim" | awk '{print $1}')"
    printf 'output_ccm=%s\n' "$output_ccm"
    printf 'output_ccm_sha256=%s\n' "$(sha256sum "$output_ccm" | awk '{print $1}')"
    printf 'batch_log=%s\n' "$log_file"
    printf 'batch_command='
    printf '%q ' "${command[@]}"
    printf '\n'
} >"$provenance_file"

echo "STAR mesh and CCM export completed."
echo "SIM bytes      : $(stat -c %s -- "$output_sim")"
echo "CCM bytes      : $(stat -c %s -- "$output_ccm")"
echo "Provenance     : $provenance_file"
