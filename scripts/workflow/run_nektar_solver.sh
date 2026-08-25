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
processes="${MPI_NP:-1}"
reynolds="${RANS_REYNOLDS:-684587.012}"
force=false
uniform_inflow=false
restart_explicit=false

# materialize_session SRC DEST NUM_STEPS REYNOLDS
# Writes a session XML with NumSteps and Reynolds replaced by their concrete
# run-time values, instead of relying on the solver's -P command-line
# overrides. This makes DEST a self-contained, reproducible record of the
# exact parameters used for this run. run_nektar_postprocess.sh reads this
# same file by default afterward, so it needs no separate override either.
# Kinvis remains the formula "1.0/Reynolds", so it stays consistent
# automatically wherever DEST is used.
materialize_session() {
    local src="$1" dest="$2" num_steps="$3" reynolds_value="$4"
    awk -v num_steps="$num_steps" -v reynolds_value="$reynolds_value" '
        /<P>[[:space:]]*NumSteps[[:space:]]*=/ {
            sub(/=.*/, "= " num_steps " </P>")
            found_steps = 1
        }
        /<P>[[:space:]]*Reynolds[[:space:]]*=/ {
            sub(/=.*/, "= " reynolds_value " </P>")
            found_reynolds = 1
        }
        { print }
        END {
            if (!found_steps) {
                print "NumSteps parameter not found" > "/dev/stderr"
                exit 3
            }
            if (!found_reynolds) {
                print "Reynolds parameter not found" > "/dev/stderr"
                exit 4
            }
        }
    ' "$src" >"$dest"
}

# materialize_uniform_inflow SRC DEST
# Rewrites the InitialConditions FUNCTION's file-based u,v,w restart entry
# into a uniform inflow (u=1, v=0, w=0), for runs that skip the STAR RANS
# solve and CSV-to-FLD interpolation entirely. Pressure keeps its existing
# zero initial condition, unaffected by this substitution.
materialize_uniform_inflow() {
    local src="$1" dest="$2"
    awk '
        /<F[[:space:]]+VAR="u,v,w"/ {
            print "            <E VAR=\"u\" VALUE=\"1\" />"
            print "            <E VAR=\"v\" VALUE=\"0\" />"
            print "            <E VAR=\"w\" VALUE=\"0\" />"
            found = 1
            next
        }
        { print }
        END {
            if (!found) {
                print "u,v,w restart FUNCTION entry not found" > "/dev/stderr"
                exit 5
            }
        }
    ' "$src" >"$dest"
}

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_nektar_solver.sh [options]

Stage mesh.xml, restart.fld and session.xml in an isolated Nektar++ run
directory, then execute IncNavierStokesSolver from the pinned container.
Run scripts/workflow/run_nektar_postprocess.sh afterward to compute wall
shear stress and mean pressure from this run directory.

Options:
  --mesh FILE       High-order mesh XML
  --restart FILE    Initial-condition FLD from the STAR interpolation
                    (mutually exclusive with --uniform-inflow)
  --uniform-inflow  Skip the restart FLD and initialize velocity with a
                    uniform inflow instead: u=1, v=0, w=0. Use this to run
                    without a STAR RANS solve/interpolation at all.
  --session FILE    Solver session template
  --run-dir DIR     Repository-relative run directory
  --steps N         Override NumSteps (default: 100)
  --reynolds RE     Override Reynolds; session uses U=1 and Kinvis=1/RE
                    (default: RANS_REYNOLDS from the case configuration)
  --np N            MPI ranks inside the container
                    (default: MPI_NP from the environment, or 1)
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
            restart_explicit=true
            shift 2
            ;;
        --uniform-inflow)
            uniform_inflow=true
            shift
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
if [[ "$uniform_inflow" == true ]]; then
    [[ "$restart_explicit" != true ]] || {
        echo "--restart and --uniform-inflow are mutually exclusive." >&2
        exit 2
    }
    required_inputs=("$mesh_file" "$session_file")
else
    required_inputs=("$mesh_file" "$restart_file" "$session_file")
fi
for path in "${required_inputs[@]}"; do
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
ln -s -- "$relative_mesh" "$run_dir/mesh.xml"
if [[ "$uniform_inflow" != true ]]; then
    relative_restart="$(realpath --relative-to="$project_dir/$run_dir" "$project_dir/$restart_file")"
    ln -s -- "$relative_restart" "$run_dir/restart.fld"
fi
materialize_session "$project_dir/$session_file" "$run_dir/session.xml" "$steps" "$reynolds" || {
    echo "Could not materialize NumSteps/Reynolds into the session: $session_file" >&2
    exit 1
}
if [[ "$uniform_inflow" == true ]]; then
    materialize_uniform_inflow "$run_dir/session.xml" "$run_dir/session.xml.next" || {
        echo "Could not materialize the uniform inflow into the session: $session_file" >&2
        exit 1
    }
    mv -f -- "$run_dir/session.xml.next" "$run_dir/session.xml"
fi

echo "Nektar run directory : $run_dir"
echo "Mesh                 : $mesh_file"
if [[ "$uniform_inflow" == true ]]; then
    echo "Initial condition    : uniform inflow (u=1, v=0, w=0)"
else
    echo "Restart              : $restart_file"
fi
echo "Session template     : $session_file"
echo "Materialized session : $run_dir/session.xml"
echo "Steps                : $steps"
echo "Normalization        : U=1, rho=1, chord=1"
echo "Reynolds / Kinvis    : $reynolds / $kinvis"
echo "MPI ranks            : $processes"

solver_log="$run_dir/solver.log"
setsid env NEKTAR_SOLVER_WORKDIR="$run_dir" NEKTAR_SOLVER_NP="$processes" \
    "$project_dir/scripts/nektar/incnavierstokes_docker.sh" \
    -f mesh.xml session.xml >"$solver_log" 2>&1 &
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
