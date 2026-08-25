#!/usr/bin/env bash
# Create a reusable STAR .sim directly from the canonical STEP fluid domain.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
# shellcheck source=scripts/workflow/lib/common.sh
source "$script_dir/lib/common.sh"

step_file="cad/naca0012_domain.step"
output_sim="star/naca0012_periodic_template.sim"
log_file="star/naca0012_bootstrap.log"
provenance_file="star/naca0012_bootstrap.provenance.txt"
star_executable="${STAR_EXECUTABLE:-starccm+}"
processes=1
periodic_span=true
periodic_translation_x_m=0.0
periodic_translation_y_m=0.0
periodic_translation_z_m=0.2
power_on_demand=false
force=false
dry_run=false
extra_star_args=()

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_star_bootstrap.sh [options] [-- STAR_OPTIONS...]

Create a new STAR simulation directly from the CAD-backed STEP BRep. The
result contains the imported Geometry Part, Fluid region, seven named physical
boundaries, automated tet/prism mesh operation, wing/farfield controls and an
optional spanwise translational-periodic interface. No prepared .sim is read.

Options:
  --step FILE          Input STEP fluid solid
                       (default: cad/naca0012_domain.step)
  --output-sim FILE    Output STAR simulation
                       (default: star/naca0012_periodic_template.sim)
  --log FILE           STAR bootstrap log
                       (default: star/naca0012_bootstrap.log)
  --provenance FILE    Bootstrap metadata
  --np N               STAR launcher process count (default: 1)
  --periodic-span      Create SpanMin/SpanMax periodic interface (default)
  --no-periodic-span   Leave SpanMin and SpanMax as ordinary boundaries
  --periodic-translation-x M
  --periodic-translation-y M
  --periodic-translation-z M
                       Translation from SpanMin to SpanMax in metres
                       (default: 0, 0, 0.2)
  --star-executable FILE
                       STAR launcher command/path (default: STAR_EXECUTABLE or
                       starccm+ resolved through PATH)
  --power-on-demand    Read the PoD key from STAR_POD_KEY without logging it
  --force              Replace an existing output after a successful run
  --dry-run            Validate and print the command without starting STAR
  -h, --help           Show this help

The canonical STEP is expected to contain one solid and nine CAD faces as
written by scripts/cad/create_naca0012_domain.py. STAR reads the STEP's
millimetre unit declaration, stores the simulation geometry in SI metres and
classifies generic imported surfaces from their coordinate bounds.
EOF
}

while (($#)); do
    case "$1" in
        --step)
            require_arg --step "$#"
            step_file="$2"
            shift 2
            ;;
        --output-sim)
            require_arg --output-sim "$#"
            output_sim="$2"
            shift 2
            ;;
        --log)
            require_arg --log "$#"
            log_file="$2"
            shift 2
            ;;
        --provenance)
            require_arg --provenance "$#"
            provenance_file="$2"
            shift 2
            ;;
        --np)
            require_arg --np "$#"
            processes="$2"
            shift 2
            ;;
        --periodic-span)
            periodic_span=true
            shift
            ;;
        --no-periodic-span)
            periodic_span=false
            shift
            ;;
        --periodic-translation-x)
            require_arg --periodic-translation-x "$#"
            periodic_translation_x_m="$2"
            shift 2
            ;;
        --periodic-translation-y)
            require_arg --periodic-translation-y "$#"
            periodic_translation_y_m="$2"
            shift 2
            ;;
        --periodic-translation-z)
            require_arg --periodic-translation-z "$#"
            periodic_translation_z_m="$2"
            shift 2
            ;;
        --star-executable)
            require_arg --star-executable "$#"
            star_executable="$2"
            shift 2
            ;;
        --power-on-demand)
            power_on_demand=true
            shift
            ;;
        --force)
            force=true
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

step_file="$(absolute_path "$step_file" "$project_dir")"
output_sim="$(absolute_path "$output_sim" "$project_dir")"
log_file="$(absolute_path "$log_file" "$project_dir")"
provenance_file="$(absolute_path "$provenance_file" "$project_dir")"
macro_file="$project_dir/scripts/star/BootstrapCase.java"

resolve_star_executable star_executable "$project_dir"

[[ -s "$step_file" ]] || {
    echo "STEP input is missing or empty: $step_file" >&2
    exit 1
}
[[ -s "$macro_file" ]] || {
    echo "Bootstrap macro is missing: $macro_file" >&2
    exit 1
}
[[ "$processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "--np must be positive: $processes" >&2
    exit 2
}
require_finite_components "Periodic translation components" \
    "$periodic_translation_x_m" \
    "$periodic_translation_y_m" \
    "$periodic_translation_z_m"

if [[ "$force" != true ]]; then
    for output in "$output_sim" "$log_file" "$provenance_file"; do
        [[ ! -e "$output" ]] || {
            echo "Output exists (use --force): $output" >&2
            exit 1
        }
    done
fi

require_star_executable "$star_executable" "$dry_run"

guard_pod_key_on_cli "${extra_star_args[@]}"
license_mode=default
pod_key=""
if [[ "$power_on_demand" == true ]]; then
    guard_pod_power_flag_conflict "${extra_star_args[@]}"
    require_pod_key
    pod_key="$STAR_POD_KEY"
    unset STAR_POD_KEY
    license_mode=power-on-demand
    extra_star_args=(-power "${extra_star_args[@]}")
fi

mkdir -p -- "$(dirname -- "$output_sim")" "$(dirname -- "$log_file")" \
    "$(dirname -- "$provenance_file")"
stage_dir="$(mktemp -d "$(dirname -- "$output_sim")/.star-bootstrap.XXXXXX")"
staged_sim="$stage_dir/$(basename -- "$output_sim")"
command=(
    "$star_executable"
    -np "$processes"
    "${extra_star_args[@]}"
    -new
    -batch "$macro_file"
    "$staged_sim"
)

echo "STEP input    : $step_file"
echo "Output SIM    : $output_sim"
echo "Batch log     : $log_file"
echo "Periodic span : $periodic_span"
echo "Translation  : ($periodic_translation_x_m, $periodic_translation_y_m, $periodic_translation_z_m) m"
echo "License mode  : $license_mode"
printf 'Command       :'
printf ' %q' "${command[@]}"
printf '\n'

if [[ "$dry_run" == true ]]; then
    rmdir -- "$stage_dir"
    exit 0
fi

set +e
if [[ "$power_on_demand" == true ]]; then
    LM_PROJECT="$pod_key" \
        STAR_STEP_INPUT="$step_file" \
        STAR_SIM_OUTPUT="$staged_sim" \
        STAR_PERIODIC_SPAN="$periodic_span" \
        STAR_PERIODIC_TRANSLATION_X_M="$periodic_translation_x_m" \
        STAR_PERIODIC_TRANSLATION_Y_M="$periodic_translation_y_m" \
        STAR_PERIODIC_TRANSLATION_Z_M="$periodic_translation_z_m" \
        "${command[@]}" >"$log_file" 2>&1
else
    STAR_STEP_INPUT="$step_file" \
        STAR_SIM_OUTPUT="$staged_sim" \
        STAR_PERIODIC_SPAN="$periodic_span" \
        STAR_PERIODIC_TRANSLATION_X_M="$periodic_translation_x_m" \
        STAR_PERIODIC_TRANSLATION_Y_M="$periodic_translation_y_m" \
        STAR_PERIODIC_TRANSLATION_Z_M="$periodic_translation_z_m" \
        "${command[@]}" >"$log_file" 2>&1
fi
star_status=$?
pod_key=""
set -e

if ((star_status != 0)) || ! grep -q 'STAR_BATCH_BOOTSTRAP_COMPLETE' "$log_file" ||
    [[ ! -s "$staged_sim" ]]; then
    echo "STAR STEP-to-SIM bootstrap failed (launcher status $star_status)." >&2
    echo "Log: $log_file" >&2
    echo "Staging retained: $stage_dir" >&2
    tail -n 50 -- "$log_file" >&2 || true
    exit "$([[ $star_status -eq 0 ]] && printf 1 || printf '%s' "$star_status")"
fi

publish_file "$staged_sim" "$output_sim"
rmdir -- "$stage_dir" 2>/dev/null || true

{
    provenance_kv generated_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    provenance_kv star_executable "$star_executable"
    provenance_kv license_mode "$license_mode"
    provenance_kv processes "$processes"
    provenance_kv step_file "$step_file"
    provenance_sha256_field step "$step_file"
    provenance_kv macro "$macro_file"
    provenance_sha256_field macro "$macro_file"
    provenance_kv periodic_span "$periodic_span"
    provenance_kv periodic_translation_x_m "$periodic_translation_x_m"
    provenance_kv periodic_translation_y_m "$periodic_translation_y_m"
    provenance_kv periodic_translation_z_m "$periodic_translation_z_m"
    provenance_kv output_sim "$output_sim"
    provenance_sha256_field output_sim "$output_sim"
} >"$provenance_file"

echo "STAR bootstrap completed."
echo "SIM bytes     : $(stat -c %s -- "$output_sim")"
echo "Provenance    : $provenance_file"
