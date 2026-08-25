#!/usr/bin/env bash
# Stage the high-order mesh/restart and run a short Nektar++ validation case.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
# shellcheck source=scripts/workflow/lib/common.sh
source "$script_dir/lib/common.sh"
case_config="${STAR_NEKTAR_CASE_CONFIG:-cases/naca0012-periodic/case.env}"
if [[ "$case_config" != /* ]]; then
    case_config="$project_dir/$case_config"
fi
if [[ -f "$case_config" ]]; then
    # This is the same version-controlled case input consumed by execute.sh.
    # shellcheck disable=SC1090
    source "$case_config"
fi

mesh_file="nekmesh/naca0012_periodic_full_p4_bl8.xml"
restart_file="nekmesh/naca0012_periodic_full_rans_initial.fld"
session_file="nektar/naca0012-periodic/session.xml"
run_dir="nektar/naca0012-periodic/run"
steps=100
processes=1
wall_shear_processes=1
reynolds="${RANS_REYNOLDS:-684587.012}"
force=false
wall_shear=true
wing_boundary=0
wing_surface="${BL_SURFACE:-4}"

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_nektar_solver.sh [options]

Stage mesh.xml, restart.fld and session.xml in an isolated Nektar++ run
directory, then execute IncNavierStokesSolver from the pinned container.

Options:
  --mesh FILE       High-order mesh XML
  --restart FILE    Initial-condition FLD from the STAR interpolation
  --session FILE    Solver session template
  --run-dir DIR     Repository-relative run directory
  --steps N         Override NumSteps (default: 100)
  --reynolds RE     Override Reynolds; session uses U=1 and Kinvis=1/RE
                    (default: RANS_REYNOLDS from the case configuration)
  --np N            MPI ranks inside the container (default: 1)
  --wall-shear-np N WSS FieldConvert ranks (default: 1, validated)
                    Values >1 are experimental and rejected if non-finite
  --no-wall-shear   Skip mean-field WSS post-processing
  --wing-boundary N Nektar boundary ID for Wing (default: 0)
  --wing-surface N  NekMesh composite ID for Wing
                    (default: BL_SURFACE from case config, otherwise 4)
  --force           Replace an existing staged run
  -h, --help        Show this help

The committed session writes small wing-force and modal-energy validation
series plus a normal Nektar++ checkpoint; it contains no history-point probes.
EOF
}

while (($#)); do
    case "$1" in
        --mesh)
            require_arg --mesh "$#"
            mesh_file="$2"
            shift 2
            ;;
        --restart)
            require_arg --restart "$#"
            restart_file="$2"
            shift 2
            ;;
        --session)
            require_arg --session "$#"
            session_file="$2"
            shift 2
            ;;
        --run-dir)
            require_arg --run-dir "$#"
            run_dir="$2"
            shift 2
            ;;
        --steps)
            require_arg --steps "$#"
            steps="$2"
            shift 2
            ;;
        --reynolds)
            require_arg --reynolds "$#"
            reynolds="$2"
            shift 2
            ;;
        --np)
            require_arg --np "$#"
            processes="$2"
            shift 2
            ;;
        --wall-shear-np)
            require_arg --wall-shear-np "$#"
            wall_shear_processes="$2"
            shift 2
            ;;
        --no-wall-shear)
            wall_shear=false
            shift
            ;;
        --wing-boundary)
            require_arg --wing-boundary "$#"
            wing_boundary="$2"
            shift 2
            ;;
        --wing-surface)
            require_arg --wing-surface "$#"
            wing_surface="$2"
            shift 2
            ;;
        --force)
            force=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$project_dir"
for path in "$mesh_file" "$restart_file" "$session_file"; do
    require_repo_relative_path "Input must be a repository-relative path" "$path"
    [[ -s "$path" ]] || {
        echo "Input is missing or empty: $path" >&2
        exit 1
    }
done
require_repo_relative_path "--run-dir must stay inside the repository" "$run_dir"
[[ "$steps" =~ ^[1-9][0-9]*$ ]] || {
    echo "--steps must be a positive integer: $steps" >&2
    exit 2
}
[[ "$processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "--np must be a positive integer: $processes" >&2
    exit 2
}
[[ "$wall_shear_processes" =~ ^[1-9][0-9]*$ ]] || {
    echo "--wall-shear-np must be a positive integer: $wall_shear_processes" >&2
    exit 2
}
[[ "$wing_boundary" =~ ^[0-9]+$ && "$wing_surface" =~ ^[0-9]+$ ]] || {
    echo "Wing boundary/surface IDs must be non-negative integers." >&2
    exit 2
}
awk -v value="$reynolds" 'BEGIN { exit !(value > 0) }' || {
    echo "--reynolds must be positive: $reynolds" >&2
    exit 2
}
kinvis="$(awk -v re="$reynolds" 'BEGIN { printf "%.17g", 1.0/re }')"

if [[ -e "$run_dir" && "$force" != true ]]; then
    echo "Run directory exists (use --force): $run_dir" >&2
    exit 1
fi

mkdir -p -- "$run_dir"
if [[ "$force" == true ]]; then
    find "$run_dir" -mindepth 1 -maxdepth 1 -type f -delete
    find "$run_dir" -mindepth 1 -maxdepth 1 -type l -delete
    find "$run_dir" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} +
fi

relative_mesh="$(realpath --relative-to="$project_dir/$run_dir" "$project_dir/$mesh_file")"
relative_restart="$(realpath --relative-to="$project_dir/$run_dir" "$project_dir/$restart_file")"
relative_session="$(realpath --relative-to="$project_dir/$run_dir" "$project_dir/$session_file")"
ln -s -- "$relative_mesh" "$run_dir/mesh.xml"
ln -s -- "$relative_restart" "$run_dir/restart.fld"
ln -s -- "$relative_session" "$run_dir/session.xml"

echo "Nektar run directory : $run_dir"
echo "Mesh                 : $mesh_file"
echo "Restart              : $restart_file"
echo "Session              : $session_file"
echo "Steps                : $steps"
echo "Normalization        : U=1, rho=1, chord=1"
echo "Reynolds / Kinvis    : $reynolds / $kinvis"
echo "MPI ranks            : $processes"
[[ "$wall_shear" != true ]] || \
    echo "Wall-shear ranks     : $wall_shear_processes (serial is validated)"

solver_log="$run_dir/solver.log"
setsid env NEKTAR_SOLVER_WORKDIR="$run_dir" NEKTAR_SOLVER_NP="$processes" \
    "$project_dir/scripts/nektar/incnavierstokes_docker.sh" \
    -f -P "NumSteps=$steps" -P "Reynolds=$reynolds" \
    mesh.xml session.xml >"$solver_log" 2>&1 &
solver_pid=$!

stop_solver() {
    if kill -0 "$solver_pid" 2>/dev/null; then
        kill -TERM -- "-$solver_pid" 2>/dev/null || true
        wait "$solver_pid" 2>/dev/null || true
    fi
}
trap stop_solver HUP INT TERM

solver_status=0
while kill -0 "$solver_pid" 2>/dev/null; do
    if grep -Eqi 'error = -?nan|Exceeded maxIt|PETSC ERROR|Segmentation fault|ASSERTL|Fatal' \
        "$solver_log" 2>/dev/null; then
        echo "Solver health check found a fatal/non-finite marker." >&2
        stop_solver
        solver_status=1
        break
    fi
    sleep 2
done
if ((solver_status == 0)); then
    set +e
    wait "$solver_pid"
    solver_status=$?
    set -e
fi
trap - HUP INT TERM

if ((solver_status != 0)); then
    echo "IncNavierStokesSolver failed with status $solver_status." >&2
    echo "Log: $solver_log" >&2
    tail -n 60 -- "$solver_log" >&2 || true
    exit "$solver_status"
fi
if grep -Eq 'ASSERTL|Fatal|Segmentation fault|Error reading|Error in' "$solver_log"; then
    echo "Solver log contains a fatal/error marker: $solver_log" >&2
    tail -n 60 -- "$solver_log" >&2
    exit 1
fi
[[ -s "$run_dir/wing_forces.fce" ]] || {
    echo "Wing-force validation output is missing." >&2
    exit 1
}
[[ -s "$run_dir/modal_energy.mdl" ]] || {
    echo "Modal-energy validation output is missing." >&2
    exit 1
}
checkpoint_path="$(find "$run_dir" -maxdepth 1 \
    \( -type f -o -type d \) \
    \( -name 'checkpoint_*.chk' -o -name 'instantaneous_*.chk' \) \
    -print | sort -V | tail -n 1)"
[[ -n "$checkpoint_path" ]] || {
    echo "Checkpoint validation output is missing." >&2
    exit 1
}
mean_field_path="$run_dir/mean_fields_avg.fld"
[[ -e "$mean_field_path" ]] || {
    echo "Final AverageFields output is missing: $mean_field_path" >&2
    exit 1
}

echo "Nektar++ validation run completed."
echo "Solver log          : $solver_log"
echo "Wing forces         : $run_dir/wing_forces.fce"
echo "Modal energy        : $run_dir/modal_energy.mdl"
echo "Time-averaged field : $mean_field_path"
find "$run_dir" -maxdepth 1 \( -type f -o -type d \) \
    \( -name '*.chk' -o -name '*.fld' \) \
    -printf 'Checkpoint/restart  : %p\n' | sort

if [[ "$wall_shear" == true ]]; then
    echo "Computing mean wing wall shear stress."
    "$project_dir/scripts/workflow/postprocess_wall_shear.sh" \
        --mesh "$mesh_file" \
        --session "$session_file" \
        --field "$mean_field_path" \
        --output-dir "$run_dir" \
        --prefix mean_fields_wss \
        --boundary "$wing_boundary" \
        --surface "$wing_surface" \
        --reynolds "$reynolds" \
        --np "$wall_shear_processes" \
        --force
fi
