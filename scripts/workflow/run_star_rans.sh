#!/usr/bin/env bash
# Configure and run a steady SST RANS precursor from an existing STAR mesh.

set -euo pipefail

default_star_executable="${STAR_EXECUTABLE:-starccm+}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
nektar_script_dir="$project_dir/scripts/nektar"
# shellcheck source=scripts/workflow/lib/common.sh
source "$script_dir/lib/common.sh"

input_sim="star/naca0012_meshed.sim"
output_sim="star/naca0012_rans.sim"
raw_table="star/naca0012_rans_raw.csv"
output_csv="star/naca0012_rans_nektar.csv"
log_file="star/naca0012_rans.log"
provenance_file="star/naca0012_rans.provenance.txt"
star_executable="$default_star_executable"
configure_macro="$project_dir/scripts/star/ConfigureRans.java"
export_macro="$project_dir/scripts/star/ExportRansTable.java"
processes=1
force=false
dry_run=false
power_on_demand=false

region="Fluid"
continuum="RANS_SST"
wing_boundary="Wing"
upstream_boundary="Upstream"
downstream_boundary="Downstream"
top_boundary="FarfieldTop"
bottom_boundary="FarfieldBottom"
span_min_boundary="SpanMin"
span_max_boundary="SpanMax"
span_mode="symmetry"
periodic_interface="SpanwisePeriodic"
reynolds="684587.012"
angle_deg="0.0"
reference_pressure="0.0"
turb_intensity="0.01"
turb_visc_ratio="10.0"
max_steps=2000
min_steps=200
residual_tolerance="1.0e-5"
pressure_mode="keep"
allow_unconverged=false
velocity_only=false
single_session=false
extra_star_args=()

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_star_rans.sh [options] [-- STAR_OPTIONS...]

Starting from an existing meshed .sim file, configure a steady,
constant-density SST k-omega RANS case, run it headlessly, save the converged
simulation, and export cell-centred x,y,z,u,v,w,p for Nektar++ interpolation.

Files:
  --input-sim FILE       Existing meshed simulation
  --output-sim FILE      Solved simulation (default: star/naca0012_rans.sim)
  --raw-table FILE       Raw STAR XyzInternalTable CSV
  --output-csv FILE      Normalized Nektar point-data CSV
  --log FILE             STAR batch log
  --provenance FILE      Reproducibility metadata

Physics:
  --reynolds RE          Chord Reynolds number (default: 684587.012).
                         The STAR values are fixed to U=1, rho=1, chord=1,
                         and mu=nu=1/RE to match Nektar++ nondimensional data.
  --angle-deg A          Angle in the x-y plane (default: 0)
  --pressure P           Nondimensional downstream reference pressure
                         (default: 0)
  --turb-intensity I     Fraction, not percent (default: 0.01)
  --turb-visc-ratio R    Inlet turbulent/molecular viscosity ratio (default: 10)
  --max-steps N          Maximum steady iterations (default: 2000)
  --min-steps N          Minimum iterations before residual convergence may
                         stop the solve (default: 200)
  --residual-tol R       Require every active residual below R (default: 1e-5)
  --pressure-mode MODE   keep, subtract-first, or zero-mean (default: keep)
  --allow-unconverged    Permit export when the maximum-step cap is reached
                         before all residual criteria are satisfied
  --velocity-only        Export x,y,z,u,v,w without pressure. Use this when
                         the Nektar++ session initializes pressure separately.
  --single-session       Configure, solve and export in one STAR process.
                         This avoids a save/reload and is intended for a
                         validated production setup.

STAR object names:
  --region NAME          Region (default: Fluid)
  --continuum NAME       Created/reused physics continuum (default: RANS_SST)
  --wing-boundary NAME   No-slip wall (default: Wing)
  --upstream-boundary NAME
  --downstream-boundary NAME
  --top-boundary NAME
  --bottom-boundary NAME
  --span-min-boundary NAME
  --span-max-boundary NAME
  --span-mode MODE      symmetry or periodic (default: symmetry). Periodic
                        mode requires a validated periodic interface already
                        present in the input .sim template.
  --periodic-interface NAME
                        Required STAR interface in periodic mode
                        (default: SpanwisePeriodic)

Execution:
  --np N                 STAR process count (default: 1)
  --star-executable FILE STAR launcher command or path (default:
                         STAR_EXECUTABLE or starccm+ resolved through PATH)
  --power-on-demand      Read the PoD key from STAR_POD_KEY without logging it
  --force                Replace canonical outputs after a successful run
  --dry-run              Validate inputs and print the STAR command only
  -h, --help             Show this help

The input simulation is never modified. Arguments after -- are inserted before
STAR's -batch option. The top and bottom boundaries are velocity inlets in this
first 0-degree tutorial.
EOF
}

while (($#)); do
    case "$1" in
        --input-sim)
            input_sim="$2"
            shift 2
            ;;
        --output-sim)
            output_sim="$2"
            shift 2
            ;;
        --raw-table)
            raw_table="$2"
            shift 2
            ;;
        --output-csv)
            output_csv="$2"
            shift 2
            ;;
        --log)
            log_file="$2"
            shift 2
            ;;
        --provenance)
            provenance_file="$2"
            shift 2
            ;;
        --np)
            processes="$2"
            shift 2
            ;;
        --star-executable)
            star_executable="$2"
            shift 2
            ;;
        --region)
            region="$2"
            shift 2
            ;;
        --continuum)
            continuum="$2"
            shift 2
            ;;
        --wing-boundary)
            wing_boundary="$2"
            shift 2
            ;;
        --upstream-boundary)
            upstream_boundary="$2"
            shift 2
            ;;
        --downstream-boundary)
            downstream_boundary="$2"
            shift 2
            ;;
        --top-boundary)
            top_boundary="$2"
            shift 2
            ;;
        --bottom-boundary)
            bottom_boundary="$2"
            shift 2
            ;;
        --span-min-boundary)
            span_min_boundary="$2"
            shift 2
            ;;
        --span-max-boundary)
            span_max_boundary="$2"
            shift 2
            ;;
        --span-mode)
            span_mode="$2"
            shift 2
            ;;
        --periodic-interface)
            periodic_interface="$2"
            shift 2
            ;;
        --reynolds)
            reynolds="$2"
            shift 2
            ;;
        --angle-deg)
            angle_deg="$2"
            shift 2
            ;;
        --pressure)
            reference_pressure="$2"
            shift 2
            ;;
        --turb-intensity)
            turb_intensity="$2"
            shift 2
            ;;
        --turb-visc-ratio)
            turb_visc_ratio="$2"
            shift 2
            ;;
        --max-steps)
            max_steps="$2"
            shift 2
            ;;
        --min-steps)
            min_steps="$2"
            shift 2
            ;;
        --residual-tol)
            residual_tolerance="$2"
            shift 2
            ;;
        --pressure-mode)
            pressure_mode="$2"
            shift 2
            ;;
        --allow-unconverged)
            allow_unconverged=true
            shift
            ;;
        --velocity-only)
            velocity_only=true
            shift
            ;;
        --single-session)
            single_session=true
            shift
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

input_sim="$(absolute_path "$input_sim" "$project_dir")"
output_sim="$(absolute_path "$output_sim" "$project_dir")"
raw_table="$(absolute_path "$raw_table" "$project_dir")"
output_csv="$(absolute_path "$output_csv" "$project_dir")"
log_file="$(absolute_path "$log_file" "$project_dir")"
provenance_file="$(absolute_path "$provenance_file" "$project_dir")"
resolve_star_executable star_executable "$project_dir"

[[ -s "$input_sim" ]] || {
    echo "Input STAR simulation is missing or empty: $input_sim" >&2
    exit 1
}
[[ -f "$configure_macro" ]] || {
    echo "Missing macro: $configure_macro" >&2
    exit 1
}
[[ -f "$export_macro" ]] || {
    echo "Missing macro: $export_macro" >&2
    exit 1
}
if { [[ "$star_executable" == */* ]] && [[ ! -x "$star_executable" ]]; } ||
    { [[ "$star_executable" != */* ]] && ! command -v -- "$star_executable" >/dev/null 2>&1; }; then
    if [[ "$dry_run" != true ]]; then
        echo "STAR executable is unavailable: $star_executable" >&2
        exit 1
    fi
fi
[[ "$input_sim" != "$output_sim" ]] || {
    echo "Input and output SIM files must differ." >&2
    exit 2
}
[[ "$processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "--np must be a positive integer." >&2
    exit 2
}
[[ "$max_steps" =~ ^[1-9][0-9]*$ ]] || {
    echo "--max-steps must be a positive integer." >&2
    exit 2
}
[[ "$min_steps" =~ ^[0-9]+$ ]] || {
    echo "--min-steps must be a non-negative integer." >&2
    exit 2
}
[[ "$pressure_mode" =~ ^(keep|subtract-first|zero-mean)$ ]] || {
    echo "Invalid --pressure-mode: $pressure_mode" >&2
    exit 2
}
[[ "$span_mode" =~ ^(symmetry|periodic)$ ]] || {
    echo "Invalid --span-mode: $span_mode" >&2
    exit 2
}
[[ -n "$periodic_interface" ]] || {
    echo "--periodic-interface must not be empty." >&2
    exit 2
}

for numeric_pair in \
    "--reynolds:$reynolds" \
    "--angle-deg:$angle_deg" \
    "--pressure:$reference_pressure" \
    "--turb-intensity:$turb_intensity" \
    "--turb-visc-ratio:$turb_visc_ratio"; do
    validate_real_number "${numeric_pair%%:*}" "${numeric_pair#*:}"
done
validate_real_number --residual-tol "$residual_tolerance"
validate_number --reynolds "$reynolds" 'value > 0'
validate_number --angle-deg "$angle_deg" 'value == value'
validate_number --pressure "$reference_pressure" 'value == value'
validate_number --turb-intensity "$turb_intensity" 'value > 0 && value < 1'
validate_number --turb-visc-ratio "$turb_visc_ratio" 'value > 0'
validate_number --residual-tol "$residual_tolerance" 'value > 0'

guard_pod_key_on_cli "${extra_star_args[@]}"
if [[ "$power_on_demand" == true ]]; then
    guard_pod_power_flag_conflict "${extra_star_args[@]}"
fi

license_mode=default
pod_key=""
if [[ "$power_on_demand" == true ]]; then
    require_pod_key
    pod_key="$STAR_POD_KEY"
    unset STAR_POD_KEY
    extra_star_args=(-power "${extra_star_args[@]}")
    license_mode=power-on-demand
fi

outputs=("$output_sim" "$raw_table" "$output_csv" "$log_file" "$provenance_file")
if [[ "$force" != true ]]; then
    for output in "${outputs[@]}"; do
        [[ ! -e "$output" ]] || {
            echo "Output exists (use --force): $output" >&2
            exit 1
        }
    done
fi
mkdir -p -- "$(dirname -- "$output_sim")" "$(dirname -- "$raw_table")" \
    "$(dirname -- "$output_csv")" "$(dirname -- "$log_file")" \
    "$(dirname -- "$provenance_file")"

stage_dir="$(mktemp -d "$(dirname -- "$output_sim")/.star-rans-stage.XXXXXX")"
staged_sim="$stage_dir/$(basename -- "$output_sim")"
staged_raw="$stage_dir/$(basename -- "$raw_table")"
staged_csv="$stage_dir/$(basename -- "$output_csv")"
cp --preserve=mode,timestamps -- "$input_sim" "$staged_sim"

configure_command=("$star_executable" -np "$processes" "${extra_star_args[@]}"
    -batch "$configure_macro" "$staged_sim")
solve_command=("$star_executable" -np "$processes" "${extra_star_args[@]}"
    -batch "run,$export_macro" "$staged_sim")
if [[ "$single_session" == true ]]; then
    configure_command=("$star_executable" -np "$processes" "${extra_star_args[@]}"
        -batch "$configure_macro,run,$export_macro" "$staged_sim")
fi
velocity_mps="1.0"
density_kgm3="1.0"
viscosity_pas="$(awk -v re="$reynolds" 'BEGIN { printf "%.17g", 1.0/re }')"

echo "Input SIM      : $input_sim"
echo "Output SIM     : $output_sim"
echo "Raw STAR table : $raw_table"
echo "Nektar CSV     : $output_csv"
echo "Batch log      : $log_file"
echo "License mode   : $license_mode"
echo "Normalization  : U=1, rho=1, chord=1"
echo "Freestream     : U=1 at $angle_deg deg"
echo "Re             : $reynolds"
echo "mu = nu = 1/Re: $viscosity_pas"
echo "Maximum steps  : $max_steps"
echo "Minimum steps  : $min_steps"
echo "Residual tol.  : $residual_tolerance (all active residuals)"
echo "Span mode      : $span_mode"
if [[ "$span_mode" == periodic ]]; then
    echo "Periodic input : requires STAR interface $periodic_interface"
fi
if [[ "$single_session" == true ]]; then
    printf 'Combined cmd    :'
    printf ' %q' "${configure_command[@]}"
    printf '\n'
else
    printf 'Configure cmd   :'
    printf ' %q' "${configure_command[@]}"
    printf '\n'
    printf 'Solve/export cmd:'
    printf ' %q' "${solve_command[@]}"
    printf '\n'
fi

if [[ "$dry_run" == true ]]; then
    echo "Dry run only; STAR was not executed."
    rm -f -- "$staged_sim"
    rmdir -- "$stage_dir" 2>/dev/null || true
    exit 0
fi

export STAR_RANS_REGION="$region"
export STAR_RANS_CONTINUUM="$continuum"
export STAR_RANS_WING_BOUNDARY="$wing_boundary"
export STAR_RANS_UPSTREAM_BOUNDARY="$upstream_boundary"
export STAR_RANS_DOWNSTREAM_BOUNDARY="$downstream_boundary"
export STAR_RANS_TOP_BOUNDARY="$top_boundary"
export STAR_RANS_BOTTOM_BOUNDARY="$bottom_boundary"
export STAR_RANS_SPAN_MIN_BOUNDARY="$span_min_boundary"
export STAR_RANS_SPAN_MAX_BOUNDARY="$span_max_boundary"
export STAR_RANS_SPAN_MODE="$span_mode"
export STAR_RANS_PERIODIC_INTERFACE="$periodic_interface"
export STAR_RANS_REYNOLDS="$reynolds"
export STAR_RANS_ANGLE_DEG="$angle_deg"
export STAR_RANS_REFERENCE_PRESSURE="$reference_pressure"
export STAR_RANS_TURB_INTENSITY="$turb_intensity"
export STAR_RANS_TURB_VISC_RATIO="$turb_visc_ratio"
export STAR_RANS_MAX_STEPS="$max_steps"
export STAR_RANS_MIN_STEPS="$min_steps"
export STAR_RANS_RESIDUAL_TOL="$residual_tolerance"
export STAR_RANS_SIM_OUTPUT="$staged_sim"
export STAR_RANS_TABLE_OUTPUT="$staged_raw"
export STAR_RANS_EXPORT_PRESSURE="$([[ "$velocity_only" == true ]] && printf false || printf true)"
if [[ "$power_on_demand" == true ]]; then export LM_PROJECT="$pod_key"; fi

set +e
"${configure_command[@]}" >"$log_file" 2>&1
configure_status=$?
set -e

configuration_ok=false
grep -q 'STAR_BATCH_RANS_CONFIGURED' "$log_file" && configuration_ok=true
configure_server_code="$(awk '/Server process exited with code :/ { code=$NF } END { print code }' "$log_file")"

if [[ "$configure_server_code" != 0 || "$configuration_ok" != true || ! -s "$staged_sim" ]]; then
    unset LM_PROJECT 2>/dev/null || true
    pod_key=""
    echo "Last STAR configuration log lines:" >&2
    tail -n 40 -- "$log_file" >&2 || true
    echo >&2
    echo "STAR RANS configuration validation: FAILED" >&2
    printf '  launcher exit status : %s\n' "$configure_status" >&2
    printf '  server exit code     : %s\n' "${configure_server_code:-missing}" >&2
    printf '  configuration marker : %s\n' "$configuration_ok" >&2
    printf '  configured SIM       : %s\n' "$([[ -s "$staged_sim" ]] && echo true || echo false)" >&2
    echo "The solver/export phase was NOT started." >&2
    echo "Staging retained: $stage_dir" >&2
    echo "Log: $log_file" >&2
    exit 1
fi

if ((configure_status != 0)); then
    echo "Warning: STAR configure launcher returned $configure_status, but configuration was independently validated." >&2
fi

if [[ "$single_session" == true ]]; then
    solve_status=$configure_status
else
    printf '\n===== STAR RANS SOLVE/EXPORT PHASE =====\n' >>"$log_file"
    set +e
    "${solve_command[@]}" >>"$log_file" 2>&1
    solve_status=$?
    set -e
fi
unset LM_PROJECT 2>/dev/null || true
pod_key=""

export_ok=false
artifacts_ok=false
residuals_converged=false
grep -q 'STAR_BATCH_RANS_EXPORT_COMPLETE' "$log_file" && export_ok=true
grep -q 'STAR_BATCH_RANS_RESIDUAL_CONVERGED=true' "$log_file" &&
    residuals_converged=true
[[ -s "$staged_sim" && -s "$staged_raw" ]] && artifacts_ok=true
solve_server_code="$(awk '/Server process exited with code :/ { code=$NF } END { print code }' "$log_file")"

if [[ "$solve_server_code" != 0 || "$export_ok" != true || "$artifacts_ok" != true ]]; then
    echo "Last STAR solve/export log lines:" >&2
    tail -n 40 -- "$log_file" >&2 || true
    echo >&2
    echo "STAR RANS solve/export validation: FAILED" >&2
    printf '  launcher exit status : %s\n' "$solve_status" >&2
    printf '  server exit code     : %s\n' "${solve_server_code:-missing}" >&2
    printf '  export marker        : %s\n' "$export_ok" >&2
    printf '  staged SIM/table     : %s\n' "$artifacts_ok" >&2
    echo "Staging retained: $stage_dir" >&2
    echo "Log: $log_file" >&2
    exit 1
fi

if ((solve_status != 0)); then
    echo "Warning: STAR solve/export launcher returned $solve_status, but outputs were independently validated." >&2
fi

if [[ "$residuals_converged" != true ]]; then
    final_residual_row="$(awk '
        NF == 7 && $1 ~ /^[0-9]+$/ {
            row=$0
        }
        END {
            sub(/^[[:space:]]+/, "", row)
            print row
        }
    ' "$log_file")"
    if [[ "$allow_unconverged" == true ]]; then
        echo "Warning: RANS reached its stopping cap before all residual criteria converged." >&2
        if [[ -n "$final_residual_row" ]]; then
            echo "Final residual row: $final_residual_row" >&2
        fi
        echo "Continuing only because --allow-unconverged was requested." >&2
    else
        echo "STAR RANS convergence validation: FAILED" >&2
        echo "  all residual criteria satisfied: false" >&2
        if [[ -n "$final_residual_row" ]]; then
            echo "  final residual row: $final_residual_row" >&2
        fi
        echo "The solve/export completed, but the field is rejected because it reached" >&2
        echo "a stopping cap before satisfying the requested residual tolerance." >&2
        echo "Inspect the residual history before increasing --max-steps: a plateau will" >&2
        echo "not improve with more iterations. Use a physically justified tolerance," >&2
        echo "improve the RANS donor mesh/setup, or use" >&2
        echo "--allow-unconverged only for an interoperability smoke test." >&2
        echo "Staging retained: $stage_dir" >&2
        echo "Log: $log_file" >&2
        exit 1
    fi
fi

normalizer_args=("$staged_raw" "$staged_csv" --pressure-mode "$pressure_mode")
if [[ "$velocity_only" == true ]]; then
    normalizer_args+=(--velocity-only)
fi
if ! python3 "$nektar_script_dir/normalize_star_rans_csv.py" \
    "${normalizer_args[@]}"; then
    echo "STAR table normalization failed; staging retained: $stage_dir" >&2
    exit 1
fi
[[ -s "$staged_csv" ]] || {
    echo "Normalized RANS CSV is empty." >&2
    exit 1
}

publish_file "$staged_sim" "$output_sim"
publish_file "$staged_raw" "$raw_table"
mv -f -- "$staged_csv" "$output_csv"
rmdir -- "$stage_dir" 2>/dev/null || true

# The batch banner is authoritative and avoids an extra STAR launcher startup.
star_version="$(awk '/^Simcenter STAR-CCM\+/ {print; exit}' "$log_file")"
star_version="${star_version:-unknown}"
final_iteration="$(awk -F: '/STAR batch final iteration/ {gsub(/[[:space:]]/, "", $2); value=$2} END {print value}' "$log_file")"
{
    provenance_kv generated_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    provenance_kv host "$(hostname)"
    provenance_kv star_version "${star_version//$'\n'/ }"
    provenance_kv license_mode "$license_mode"
    provenance_kv processes "$processes"
    provenance_kv input_sim "$input_sim"
    provenance_sha256_field input_sim "$input_sim"
    provenance_sha256_field configure_macro "$configure_macro"
    provenance_sha256_field export_macro "$export_macro"
    printf 'nondimensional_velocity=%s\nangle_deg=%s\nnondimensional_density=%s\n' \
        "$velocity_mps" "$angle_deg" "$density_kgm3"
    printf 'reynolds=%s\nnondimensional_kinematic_viscosity=%s\nreference_pressure=%s\n' \
        "$reynolds" "$viscosity_pas" "$reference_pressure"
    printf 'turbulence_intensity=%s\nturbulent_viscosity_ratio=%s\n' "$turb_intensity" "$turb_visc_ratio"
    printf 'maximum_steps=%s\nminimum_steps=%s\nresidual_tolerance=%s\npressure_mode=%s\n' \
        "$max_steps" "$min_steps" "$residual_tolerance" "$pressure_mode"
    provenance_kv final_iteration "${final_iteration:-unknown}"
    provenance_kv residuals_converged "$residuals_converged"
    provenance_kv allow_unconverged "$allow_unconverged"
    provenance_kv velocity_only "$velocity_only"
    provenance_kv single_session "$single_session"
    printf 'region=%s\ncontinuum=%s\n' "$region" "$continuum"
    provenance_kv span_mode "$span_mode"
    provenance_kv periodic_interface "$periodic_interface"
    provenance_sha256_field output_sim "$output_sim"
    provenance_sha256_field raw_table "$raw_table"
    provenance_sha256_field output_csv "$output_csv"
} >"$provenance_file"

echo "STAR RANS precursor completed."
echo "Final iteration  : ${final_iteration:-unknown}"
echo "Solved SIM bytes : $(stat -c %s -- "$output_sim")"
echo "Sample rows      : $(($(wc -l <"$output_csv") - 1))"
echo "Provenance       : $provenance_file"
