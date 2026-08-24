#!/usr/bin/env bash
# Run STAR -> NekMesh CAD projection/BL split -> FieldConvert end to end.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
nektar_script_dir="$project_dir/scripts/nektar"
source "$nektar_script_dir/container_images.sh"

force=false
skip_star=false
power_on_demand=false
star_processes=1
rans_processes=""
star_executable=""
star_template="star/naca0012_mesh_template.sim"
star_step=""
star_mesh_operation="NACA0012_AutomatedMesh"
star_wing_control="WingSurfaceControl"
star_volume_control="WingVolumeControl"
star_volume_part="WingRefinement"
case_name="naca0012"
cad_file="cad/naca0012_domain.step"
ccm_file=""
cad_order=4
bl_surface=4
bl_layers=6
bl_ratio="1.5"
bl_nq="auto"
jac_threshold="0.7"
periodic_span=false
periodic_surf1=6
periodic_surf2=8
periodic_dir="z"
periodic_translation_x="0.0"
periodic_translation_y="0.0"
periodic_translation_z="0.2"
periodic_tolfac="4"
periodic_abstol="0"
star_periodic_interface="SpanwisePeriodic"
run_rans=false
rans_reynolds="684587.012"
rans_angle_deg="0.0"
rans_pressure="0.0"
rans_turb_intensity="0.01"
rans_turb_visc_ratio="10.0"
rans_max_steps=2000
rans_min_steps=200
rans_residual_tolerance="1.0e-5"
rans_allow_unconverged=false
rans_pressure_mode="keep"
rans_session=""
rans_session_auto=false
rans_num_modes="auto"

# Explicit STAR defaults copied from the validated template.  They are passed
# to run_star_mesh.sh so a batch run is not silently controlled by stale GUI
# state in the .sim file.
star_base_size="1.0"
star_surface_target_pct="50.0"
star_surface_min_pct="1.0"
star_max_cell_pct="10000.0"
star_tet_growth="1.2"
star_wing_target_pct="2.0"
star_wing_min_pct="0.25"
star_wing_curvature_points="36.0"
star_prism_height="0.03"
star_prism_layers=1
star_prism_stretching="1.5"
star_volume_size_pct="5.0"
star_volume_x_min="-0.25"
star_volume_x_max="1.50"
star_volume_y_min="-0.30"
star_volume_y_max="0.30"
star_volume_z_min="-0.01"
star_volume_z_max="0.21"

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_remote_pipeline.sh [options]

Run the validated NACA0012 pipeline:
  STAR volume mesh + CCM export
  -> linear NekMesh import and VTU
  -> configurable CAD projection and native high-order VTU
  -> configurable prism split and native high-order VTU
  -> scaled-Jacobian validation and focused quality report

Options:
  --power-on-demand  Run STAR in Power-on-Demand mode. STAR_POD_KEY must be
                     present in the environment; it is not logged or passed
                     to the containers.
  --star-np N        Process count for every STAR stage (default: 1)
  --rans-np N        Override the process count for RANS only
                     (default: same as --star-np)
  --star-executable FILE       STAR-CCM+ launcher path
                               (default: site-specific wrapper default)
  --star-template FILE         Prepared STAR .sim template
  --star-step FILE             Bootstrap a fresh template from this STEP before
                               meshing; supersedes --star-template as input
  --star-mesh-operation NAME   Automated Mesh operation name
  --star-wing-control NAME     Wing Surface Custom Mesh Control name
  --star-volume-control NAME   Volumetric control name (created if absent)
  --star-volume-part NAME      Refinement block name (created if absent)
  --skip-star        Reuse --ccm-file instead of running STAR
  --name NAME        Output namespace (default: naca0012)
  --cad-file FILE    STEP CAD used by projectcad
  --ccm-file FILE    STAR CCM input/output (default: star/NAME_linear.ccm)
  --cad-order P      CAD projection polynomial order (default: 4)
  --bl-surface ID    NekMesh wing composite ID (default: 4)
  --bl-layers N      Final NekMesh layers per STAR macro prism (default: 6)
  --bl-ratio R       Outward geometric layer-thickness ratio (default: 1.5)
  --bl-nq N          BL module quadrature points (default: P+1)
  --jac-threshold J  Detailed final Jacobian histogram cutoff (default: 0.7)

Optional spanwise periodic alignment:
  --periodic-span    Require matching SpanMin/SpanMax meshes and run peralign
                     on the linear hybrid mesh before high-order operations
  --periodic-surf1 ID
                     First span composite (default: 6, SpanMin)
  --periodic-surf2 ID
                     Second span composite (default: 8, SpanMax)
  --periodic-dir AXIS
                     Translation direction x, y or z (default: z)
  --periodic-translation-x M
  --periodic-translation-y M
  --periodic-translation-z M
                     STAR translation from SpanMin to SpanMax in metres
                     (default: 0, 0, 0.2)
  --periodic-tolfac F Relative-tolerance factor, F >= 1 (default: 4)
  --periodic-abstol T Absolute matching tolerance, T >= 0 (default: 0)
  --star-periodic-interface NAME
                     STAR periodic interface required for periodic RANS
                     (default: SpanwisePeriodic)

Optional STAR RANS precursor:
  --run-rans         Solve steady constant-density SST after STAR meshing and
                     export x,y,z,u,v,w,p for Nektar++ interpolation
  --rans-reynolds RE  Chord Reynolds number (default: 684587.012). STAR uses
                     the Nektar++ nondimensional convention U=1, rho=1,
                     chord=1 and mu=nu=1/RE.
  --rans-angle-deg A Angle in the x-y plane (default: 0)
  --rans-pressure P  Nondimensional outlet reference pressure (default: 0)
  --rans-turb-intensity I
                     Inlet turbulence intensity as a fraction (default: .01)
  --rans-turb-visc-ratio R
                     Inlet eddy/molecular viscosity ratio (default: 10)
  --rans-max-steps N Maximum steady iterations (default: 2000)
  --rans-min-steps N Minimum iterations before residual convergence can stop
                     the solve (default: 200)
  --rans-residual-tol R
                     Require every active residual below R (default: 1e-5)
  --rans-allow-unconverged
                     Continue after reaching the maximum-step cap without
                     residual convergence (interoperability smoke tests only)
  --rans-pressure-mode MODE
                     keep, subtract-first, or zero-mean (default: keep)
  --rans-session FILE|auto
                     Interpolate RANS onto this Nektar++ session, or generate
                     one from the final mesh with auto. This also writes FLD
                     and native high-order VTU restart files.
  --rans-num-modes N Number of restart expansion modes (default: CAD order+1;
                     used only with --rans-session auto)

STAR mesh parameters:
  --star-base-size M          Base size in metres (default: 1.0)
  --star-surface-target-pct P Global surface target, % base (default: 50)
  --star-surface-min-pct P    Global surface minimum, % base (default: 1)
  --star-max-cell-pct P       Maximum tet size, % base (default: 10000)
  --star-tet-growth R         Tet growth rate (default: 1.2)
  --star-wing-target-pct P    Wing surface target, % base (default: 2)
  --star-wing-min-pct P       Wing surface minimum, % base (default: 0.25)
  --star-wing-curvature N     Wing points/circle (default: 36)
  --star-prism-height M       Macro-layer total height in metres (default: .03)
  --star-prism-layers N       Must be 1 for this NekMesh workflow
  --star-prism-stretching R   Relevant only if STAR layers > 1 (default: 1.5)
  --star-volume-size-pct P    Refinement size, % base (default: 5)
  --star-volume-x-min M       Refinement-box minimum x (default: -0.25 m)
  --star-volume-x-max M       Refinement-box maximum x (default: 1.50 m)
  --star-volume-y-min M       Refinement-box minimum y (default: -0.30 m)
  --star-volume-y-max M       Refinement-box maximum y (default: 0.30 m)
  --star-volume-z-min M       Refinement-box minimum z (default: -0.01 m)
  --star-volume-z-max M       Refinement-box maximum z (default: 0.21 m)

  --force            Permit replacement of all canonical generated outputs
  -h, --help         Show this help

The container wrappers select Docker or Apptainer from the configured site.
Set NEKTAR_CONTAINER_RUNTIME to force one runtime. The default full Nektar++
OCI image is an immutable digest-pinned reference in
scripts/nektar/container_images.sh.
EOF
}

while (($#)); do
    case "$1" in
        --power-on-demand)
            power_on_demand=true
            shift
            ;;
        --star-np)
            [[ $# -ge 2 ]] || {
                echo "--star-np requires a value" >&2
                exit 2
            }
            star_processes="$2"
            shift 2
            ;;
        --rans-np)
            [[ $# -ge 2 ]] || {
                echo "--rans-np requires a value" >&2
                exit 2
            }
            rans_processes="$2"
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
        --star-template)
            [[ $# -ge 2 ]] || {
                echo "--star-template requires a value" >&2
                exit 2
            }
            star_template="$2"
            shift 2
            ;;
        --star-step)
            [[ $# -ge 2 ]] || {
                echo "--star-step requires a value" >&2
                exit 2
            }
            star_step="$2"
            shift 2
            ;;
        --star-mesh-operation)
            [[ $# -ge 2 ]] || {
                echo "--star-mesh-operation requires a value" >&2
                exit 2
            }
            star_mesh_operation="$2"
            shift 2
            ;;
        --star-wing-control)
            [[ $# -ge 2 ]] || {
                echo "--star-wing-control requires a value" >&2
                exit 2
            }
            star_wing_control="$2"
            shift 2
            ;;
        --star-volume-control)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-control requires a value" >&2
                exit 2
            }
            star_volume_control="$2"
            shift 2
            ;;
        --star-volume-part)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-part requires a value" >&2
                exit 2
            }
            star_volume_part="$2"
            shift 2
            ;;
        --skip-star)
            skip_star=true
            shift
            ;;
        --name)
            [[ $# -ge 2 ]] || {
                echo "--name requires a value" >&2
                exit 2
            }
            case_name="$2"
            shift 2
            ;;
        --cad-file)
            [[ $# -ge 2 ]] || {
                echo "--cad-file requires a value" >&2
                exit 2
            }
            cad_file="$2"
            shift 2
            ;;
        --ccm-file)
            [[ $# -ge 2 ]] || {
                echo "--ccm-file requires a value" >&2
                exit 2
            }
            ccm_file="$2"
            shift 2
            ;;
        --cad-order)
            [[ $# -ge 2 ]] || {
                echo "--cad-order requires a value" >&2
                exit 2
            }
            cad_order="$2"
            shift 2
            ;;
        --bl-surface)
            [[ $# -ge 2 ]] || {
                echo "--bl-surface requires a value" >&2
                exit 2
            }
            bl_surface="$2"
            shift 2
            ;;
        --bl-layers)
            [[ $# -ge 2 ]] || {
                echo "--bl-layers requires a value" >&2
                exit 2
            }
            bl_layers="$2"
            shift 2
            ;;
        --bl-ratio)
            [[ $# -ge 2 ]] || {
                echo "--bl-ratio requires a value" >&2
                exit 2
            }
            bl_ratio="$2"
            shift 2
            ;;
        --bl-nq)
            [[ $# -ge 2 ]] || {
                echo "--bl-nq requires a value" >&2
                exit 2
            }
            bl_nq="$2"
            shift 2
            ;;
        --jac-threshold)
            [[ $# -ge 2 ]] || {
                echo "--jac-threshold requires a value" >&2
                exit 2
            }
            jac_threshold="$2"
            shift 2
            ;;
        --periodic-span)
            periodic_span=true
            shift
            ;;
        --periodic-surf1)
            [[ $# -ge 2 ]] || {
                echo "--periodic-surf1 requires a value" >&2
                exit 2
            }
            periodic_surf1="$2"
            shift 2
            ;;
        --periodic-surf2)
            [[ $# -ge 2 ]] || {
                echo "--periodic-surf2 requires a value" >&2
                exit 2
            }
            periodic_surf2="$2"
            shift 2
            ;;
        --periodic-dir)
            [[ $# -ge 2 ]] || {
                echo "--periodic-dir requires a value" >&2
                exit 2
            }
            periodic_dir="$2"
            shift 2
            ;;
        --periodic-translation-x)
            [[ $# -ge 2 ]] || {
                echo "--periodic-translation-x requires a value" >&2
                exit 2
            }
            periodic_translation_x="$2"
            shift 2
            ;;
        --periodic-translation-y)
            [[ $# -ge 2 ]] || {
                echo "--periodic-translation-y requires a value" >&2
                exit 2
            }
            periodic_translation_y="$2"
            shift 2
            ;;
        --periodic-translation-z)
            [[ $# -ge 2 ]] || {
                echo "--periodic-translation-z requires a value" >&2
                exit 2
            }
            periodic_translation_z="$2"
            shift 2
            ;;
        --periodic-tolfac)
            [[ $# -ge 2 ]] || {
                echo "--periodic-tolfac requires a value" >&2
                exit 2
            }
            periodic_tolfac="$2"
            shift 2
            ;;
        --periodic-abstol)
            [[ $# -ge 2 ]] || {
                echo "--periodic-abstol requires a value" >&2
                exit 2
            }
            periodic_abstol="$2"
            shift 2
            ;;
        --star-periodic-interface)
            [[ $# -ge 2 ]] || {
                echo "--star-periodic-interface requires a value" >&2
                exit 2
            }
            star_periodic_interface="$2"
            shift 2
            ;;
        --run-rans)
            run_rans=true
            shift
            ;;
        --rans-reynolds)
            [[ $# -ge 2 ]] || {
                echo "--rans-reynolds requires a value" >&2
                exit 2
            }
            rans_reynolds="$2"
            shift 2
            ;;
        --rans-angle-deg)
            [[ $# -ge 2 ]] || {
                echo "--rans-angle-deg requires a value" >&2
                exit 2
            }
            rans_angle_deg="$2"
            shift 2
            ;;
        --rans-pressure)
            [[ $# -ge 2 ]] || {
                echo "--rans-pressure requires a value" >&2
                exit 2
            }
            rans_pressure="$2"
            shift 2
            ;;
        --rans-turb-intensity)
            [[ $# -ge 2 ]] || {
                echo "--rans-turb-intensity requires a value" >&2
                exit 2
            }
            rans_turb_intensity="$2"
            shift 2
            ;;
        --rans-turb-visc-ratio)
            [[ $# -ge 2 ]] || {
                echo "--rans-turb-visc-ratio requires a value" >&2
                exit 2
            }
            rans_turb_visc_ratio="$2"
            shift 2
            ;;
        --rans-max-steps)
            [[ $# -ge 2 ]] || {
                echo "--rans-max-steps requires a value" >&2
                exit 2
            }
            rans_max_steps="$2"
            shift 2
            ;;
        --rans-min-steps)
            [[ $# -ge 2 ]] || {
                echo "--rans-min-steps requires a value" >&2
                exit 2
            }
            rans_min_steps="$2"
            shift 2
            ;;
        --rans-residual-tol)
            [[ $# -ge 2 ]] || {
                echo "--rans-residual-tol requires a value" >&2
                exit 2
            }
            rans_residual_tolerance="$2"
            shift 2
            ;;
        --rans-allow-unconverged)
            rans_allow_unconverged=true
            shift
            ;;
        --rans-pressure-mode)
            [[ $# -ge 2 ]] || {
                echo "--rans-pressure-mode requires a value" >&2
                exit 2
            }
            rans_pressure_mode="$2"
            shift 2
            ;;
        --rans-session)
            [[ $# -ge 2 ]] || {
                echo "--rans-session requires a value" >&2
                exit 2
            }
            rans_session="$2"
            run_rans=true
            shift 2
            ;;
        --rans-num-modes)
            [[ $# -ge 2 ]] || {
                echo "--rans-num-modes requires a value" >&2
                exit 2
            }
            rans_num_modes="$2"
            shift 2
            ;;
        --star-base-size)
            [[ $# -ge 2 ]] || {
                echo "--star-base-size requires a value" >&2
                exit 2
            }
            star_base_size="$2"
            shift 2
            ;;
        --star-surface-target-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-surface-target-pct requires a value" >&2
                exit 2
            }
            star_surface_target_pct="$2"
            shift 2
            ;;
        --star-surface-min-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-surface-min-pct requires a value" >&2
                exit 2
            }
            star_surface_min_pct="$2"
            shift 2
            ;;
        --star-max-cell-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-max-cell-pct requires a value" >&2
                exit 2
            }
            star_max_cell_pct="$2"
            shift 2
            ;;
        --star-tet-growth)
            [[ $# -ge 2 ]] || {
                echo "--star-tet-growth requires a value" >&2
                exit 2
            }
            star_tet_growth="$2"
            shift 2
            ;;
        --star-wing-target-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-wing-target-pct requires a value" >&2
                exit 2
            }
            star_wing_target_pct="$2"
            shift 2
            ;;
        --star-wing-min-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-wing-min-pct requires a value" >&2
                exit 2
            }
            star_wing_min_pct="$2"
            shift 2
            ;;
        --star-wing-curvature)
            [[ $# -ge 2 ]] || {
                echo "--star-wing-curvature requires a value" >&2
                exit 2
            }
            star_wing_curvature_points="$2"
            shift 2
            ;;
        --star-prism-height)
            [[ $# -ge 2 ]] || {
                echo "--star-prism-height requires a value" >&2
                exit 2
            }
            star_prism_height="$2"
            shift 2
            ;;
        --star-prism-layers)
            [[ $# -ge 2 ]] || {
                echo "--star-prism-layers requires a value" >&2
                exit 2
            }
            star_prism_layers="$2"
            shift 2
            ;;
        --star-prism-stretching)
            [[ $# -ge 2 ]] || {
                echo "--star-prism-stretching requires a value" >&2
                exit 2
            }
            star_prism_stretching="$2"
            shift 2
            ;;
        --star-volume-size-pct)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-size-pct requires a value" >&2
                exit 2
            }
            star_volume_size_pct="$2"
            shift 2
            ;;
        --star-volume-x-min)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-x-min requires a value" >&2
                exit 2
            }
            star_volume_x_min="$2"
            shift 2
            ;;
        --star-volume-x-max)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-x-max requires a value" >&2
                exit 2
            }
            star_volume_x_max="$2"
            shift 2
            ;;
        --star-volume-y-min)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-y-min requires a value" >&2
                exit 2
            }
            star_volume_y_min="$2"
            shift 2
            ;;
        --star-volume-y-max)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-y-max requires a value" >&2
                exit 2
            }
            star_volume_y_max="$2"
            shift 2
            ;;
        --star-volume-z-min)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-z-min requires a value" >&2
                exit 2
            }
            star_volume_z_min="$2"
            shift 2
            ;;
        --star-volume-z-max)
            [[ $# -ge 2 ]] || {
                echo "--star-volume-z-max requires a value" >&2
                exit 2
            }
            star_volume_z_max="$2"
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

if [[ ! "$star_processes" =~ ^[1-9][0-9]*$ ]]; then
    echo "--star-np must be a positive integer: $star_processes" >&2
    exit 2
fi
if [[ -z "$rans_processes" ]]; then
    rans_processes="$star_processes"
elif [[ ! "$rans_processes" =~ ^[1-9][0-9]*$ ]]; then
    echo "--rans-np must be a positive integer: $rans_processes" >&2
    exit 2
fi
if [[ ! "$case_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "--name must contain only letters, digits, dot, underscore or hyphen." >&2
    exit 2
fi
if [[ ! "$cad_order" =~ ^[0-9]+$ ]] || ((cad_order < 2)); then
    echo "--cad-order must be an integer of at least 2: $cad_order" >&2
    exit 2
fi
if [[ ! "$bl_surface" =~ ^[0-9]+$ ]]; then
    echo "--bl-surface must be a non-negative integer: $bl_surface" >&2
    exit 2
fi
if [[ ! "$periodic_surf1" =~ ^[0-9]+$ || ! "$periodic_surf2" =~ ^[0-9]+$ ]]; then
    echo "--periodic-surf1 and --periodic-surf2 must be non-negative integers." >&2
    exit 2
fi
if [[ "$periodic_surf1" == "$periodic_surf2" ]]; then
    echo "The two periodic composite IDs must differ." >&2
    exit 2
fi
if [[ -z "$star_periodic_interface" ]]; then
    echo "--star-periodic-interface must not be empty." >&2
    exit 2
fi
if [[ ! "$periodic_dir" =~ ^(x|y|z)$ ]]; then
    echo "--periodic-dir must be x, y or z: $periodic_dir" >&2
    exit 2
fi
for translation in \
    "$periodic_translation_x" \
    "$periodic_translation_y" \
    "$periodic_translation_z"; do
    awk -v value="$translation" 'BEGIN { exit !(value ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/) }' || {
        echo "Periodic translation components must be numeric: $translation" >&2
        exit 2
    }
done
if [[ ! "$bl_layers" =~ ^[1-9][0-9]*$ ]]; then
    echo "--bl-layers must be a positive integer: $bl_layers" >&2
    exit 2
fi
if [[ ! "$star_prism_layers" =~ ^[1-9][0-9]*$ ]]; then
    echo "--star-prism-layers must be a positive integer: $star_prism_layers" >&2
    exit 2
fi
if [[ ! "$rans_max_steps" =~ ^[1-9][0-9]*$ ]]; then
    echo "--rans-max-steps must be a positive integer: $rans_max_steps" >&2
    exit 2
fi
if [[ ! "$rans_min_steps" =~ ^[0-9]+$ ]]; then
    echo "--rans-min-steps must be a non-negative integer: $rans_min_steps" >&2
    exit 2
fi
if [[ "$rans_num_modes" == auto ]]; then
    rans_num_modes=$((cad_order + 1))
elif [[ ! "$rans_num_modes" =~ ^[0-9]+$ ]] || ((rans_num_modes < 2)); then
    echo "--rans-num-modes must be an integer of at least 2: $rans_num_modes" >&2
    exit 2
fi
if [[ ! "$rans_pressure_mode" =~ ^(keep|subtract-first|zero-mean)$ ]]; then
    echo "Invalid --rans-pressure-mode: $rans_pressure_mode" >&2
    exit 2
fi
if ((star_prism_layers != 1)); then
    echo "This pipeline requires exactly one STAR macro-prism layer." >&2
    echo "Use run_star_mesh.sh directly to experiment with multiple STAR layers." >&2
    exit 2
fi
if [[ "$bl_nq" == auto ]]; then
    bl_nq=$((cad_order + 1))
elif [[ ! "$bl_nq" =~ ^[1-9][0-9]*$ ]]; then
    echo "--bl-nq must be a positive integer or auto: $bl_nq" >&2
    exit 2
fi
if ((bl_nq < cad_order + 1)); then
    echo "--bl-nq must be at least cad-order + 1 ($((cad_order + 1)))." >&2
    exit 2
fi

validate_positive_number() {
    local option="$1"
    local value="$2"
    if ! awk -v value="$value" 'BEGIN { exit !(value > 0) }'; then
        echo "$option must be positive: $value" >&2
        exit 2
    fi
}

validate_positive_number --bl-ratio "$bl_ratio"
validate_positive_number --jac-threshold "$jac_threshold"
validate_positive_number --star-base-size "$star_base_size"
validate_positive_number --star-surface-target-pct "$star_surface_target_pct"
validate_positive_number --star-surface-min-pct "$star_surface_min_pct"
validate_positive_number --star-max-cell-pct "$star_max_cell_pct"
validate_positive_number --star-wing-target-pct "$star_wing_target_pct"
validate_positive_number --star-wing-min-pct "$star_wing_min_pct"
validate_positive_number --star-wing-curvature "$star_wing_curvature_points"
validate_positive_number --star-prism-height "$star_prism_height"
validate_positive_number --star-prism-stretching "$star_prism_stretching"
validate_positive_number --star-volume-size-pct "$star_volume_size_pct"
validate_positive_number --rans-reynolds "$rans_reynolds"
validate_positive_number --rans-turb-intensity "$rans_turb_intensity"
validate_positive_number --rans-turb-visc-ratio "$rans_turb_visc_ratio"
validate_positive_number --rans-residual-tol "$rans_residual_tolerance"
validate_positive_number --periodic-tolfac "$periodic_tolfac"

validate_real_number() {
    local option="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$ ]]; then
        echo "$option must be a finite number: $value" >&2
        exit 2
    fi
}

validate_real_number --star-volume-x-min "$star_volume_x_min"
validate_real_number --star-volume-x-max "$star_volume_x_max"
validate_real_number --star-volume-y-min "$star_volume_y_min"
validate_real_number --star-volume-y-max "$star_volume_y_max"
validate_real_number --star-volume-z-min "$star_volume_z_min"
validate_real_number --star-volume-z-max "$star_volume_z_max"
validate_real_number --rans-angle-deg "$rans_angle_deg"
validate_real_number --rans-pressure "$rans_pressure"
validate_real_number --periodic-abstol "$periodic_abstol"

if ! awk -v value="$periodic_tolfac" 'BEGIN { exit !(value >= 1) }'; then
    echo "--periodic-tolfac must be at least 1: $periodic_tolfac" >&2
    exit 2
fi
if ! awk -v value="$periodic_abstol" 'BEGIN { exit !(value >= 0) }'; then
    echo "--periodic-abstol must be non-negative: $periodic_abstol" >&2
    exit 2
fi

if ! awk -v value="$rans_turb_intensity" 'BEGIN { exit !(value < 1) }'; then
    echo "--rans-turb-intensity is a fraction and must be less than 1." >&2
    exit 2
fi

if ! awk -v value="$jac_threshold" 'BEGIN { exit !(value <= 1) }'; then
    echo "--jac-threshold must not exceed 1: $jac_threshold" >&2
    exit 2
fi
if ! awk -v value="$star_tet_growth" \
    'BEGIN { exit !(value > 1 && value <= 2) }'; then
    echo "--star-tet-growth must satisfy 1 < R <= 2: $star_tet_growth" >&2
    exit 2
fi
if ! awk -v value="$star_prism_stretching" \
    'BEGIN { exit !(value >= 1) }'; then
    echo "--star-prism-stretching must be at least 1: $star_prism_stretching" >&2
    exit 2
fi
if ! awk -v minimum="$star_surface_min_pct" \
    -v target="$star_surface_target_pct" \
    'BEGIN { exit !(minimum <= target) }'; then
    echo "STAR global minimum surface size must not exceed its target." >&2
    exit 2
fi
if ! awk -v minimum="$star_wing_min_pct" \
    -v target="$star_wing_target_pct" \
    'BEGIN { exit !(minimum <= target) }'; then
    echo "STAR wing minimum surface size must not exceed its target." >&2
    exit 2
fi
if ! awk -v lo="$star_volume_x_min" -v hi="$star_volume_x_max" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--star-volume-x-min must be less than --star-volume-x-max." >&2
    exit 2
fi
if ! awk -v lo="$star_volume_y_min" -v hi="$star_volume_y_max" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--star-volume-y-min must be less than --star-volume-y-max." >&2
    exit 2
fi
if ! awk -v lo="$star_volume_z_min" -v hi="$star_volume_z_max" \
    'BEGIN { exit !(lo < hi) }'; then
    echo "--star-volume-z-min must be less than --star-volume-z-max." >&2
    exit 2
fi
if [[ "$skip_star" == true && "$power_on_demand" == true && "$run_rans" != true ]]; then
    echo "--power-on-demand was requested, but --skip-star leaves no STAR stage to run." >&2
    echo "Add --run-rans or remove --power-on-demand." >&2
    exit 2
fi

pod_key="${STAR_POD_KEY:-}"
unset STAR_POD_KEY
if [[ "$power_on_demand" == true && -z "$pod_key" ]]; then
    echo "--power-on-demand requires the STAR_POD_KEY environment variable." >&2
    exit 2
fi

cd "$project_dir"
mkdir -p nekmesh logs

if [[ "$cad_file" == /* || "$cad_file" == *:* ]]; then
    echo "--cad-file must be a colon-free path relative to the tutorial root." >&2
    exit 2
fi
if [[ -n "$ccm_file" && ("$ccm_file" == /* || "$ccm_file" == *:*) ]]; then
    echo "--ccm-file must be a colon-free path relative to the tutorial root." >&2
    exit 2
fi
if [[ ! -s "$cad_file" ]]; then
    echo "CAD file is missing or empty: $cad_file" >&2
    exit 1
fi
if [[ "$rans_session" == auto ]]; then
    rans_session_auto=true
    rans_session="nekmesh/${case_name}_restart_session.xml"
fi
if [[ -n "$rans_session" ]]; then
    if [[ "$rans_session" == /* || "$rans_session" == *:* ]]; then
        echo "--rans-session must be a colon-free path relative to the tutorial root." >&2
        exit 2
    fi
    if [[ "$rans_session_auto" != true && ! -s "$rans_session" ]]; then
        echo "RANS target session is missing or empty: $rans_session" >&2
        exit 1
    fi
fi

linear_stem="$case_name"
periodic_check_stem="${case_name}_linear_periodic_check"
projected_stem="${case_name}_p${cad_order}"
final_stem="${projected_stem}_bl${bl_layers}"
split_stem="${final_stem}_prealign"
periodic_stem="${final_stem}_periodic_oriented"
if [[ -z "$ccm_file" ]]; then
    ccm_file="star/${case_name}_linear.ccm"
fi
quality_tag="${jac_threshold//./p}"
quality_file="nekmesh/${final_stem}_jac_under_${quality_tag}.txt"

global_target_m="$(awk -v b="$star_base_size" -v p="$star_surface_target_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
global_min_m="$(awk -v b="$star_base_size" -v p="$star_surface_min_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
wing_target_m="$(awk -v b="$star_base_size" -v p="$star_wing_target_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
wing_min_m="$(awk -v b="$star_base_size" -v p="$star_wing_min_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
volume_size_m="$(awk -v b="$star_base_size" -v p="$star_volume_size_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
max_cell_m="$(awk -v b="$star_base_size" -v p="$star_max_cell_pct" 'BEGIN { printf "%.9g", b*p/100 }')"
first_split_height_m="$(awk -v h="$star_prism_height" -v n="$bl_layers" -v r="$bl_ratio" \
    'BEGIN { if (r == 1) value=h/n; else value=h*(r-1)/(r^n-1); printf "%.9g", value }')"

printf '[pipeline] parameter summary\n'
printf '  STAR base size (reference)  : %s m\n' "$star_base_size"
printf '  STAR global surface sizes   : target %s m (%s%%), minimum %s m (%s%%)\n' \
    "$global_target_m" "$star_surface_target_pct" \
    "$global_min_m" "$star_surface_min_pct"
printf '  STAR wing surface sizes     : target %s m (%s%%), minimum %s m (%s%%)\n' \
    "$wing_target_m" "$star_wing_target_pct" \
    "$wing_min_m" "$star_wing_min_pct"
printf '  STAR volume-control target  : %s m (%s%% of base)\n' \
    "$volume_size_m" "$star_volume_size_pct"
printf '  STAR volume-control box     : (%s,%s,%s) -> (%s,%s,%s) m\n' \
    "$star_volume_x_min" "$star_volume_y_min" "$star_volume_z_min" \
    "$star_volume_x_max" "$star_volume_y_max" "$star_volume_z_max"
printf '  STAR tetrahedral controls   : maximum %s m (%s%% of base), growth %s\n' \
    "$max_cell_m" "$star_max_cell_pct" "$star_tet_growth"
printf '  STAR macro prism stack      : total height %s m, %s layer\n' \
    "$star_prism_height" "$star_prism_layers"
printf '  NekMesh curved geometry     : polynomial P=%s (%s points/direction)\n' \
    "$cad_order" "$bl_nq"
printf '  NekMesh prism split         : 1 macro layer -> %s layers, outward growth ratio %s\n' \
    "$bl_layers" "$bl_ratio"
printf '  derived wall-first layer    : %s m (layers sum to %s m)\n' \
    "$first_split_height_m" "$star_prism_height"
if [[ "$periodic_span" == true ]]; then
    printf '  spanwise periodic pair      : C[%s] <-> C[%s], dir=%s, orient=true\n' \
        "$periodic_surf1" "$periodic_surf2" "$periodic_dir"
    printf '  periodic tolerances         : tolfac=%s, abstol=%s\n' \
        "$periodic_tolfac" "$periodic_abstol"
    printf '  STAR periodic interface     : %s\n' "$star_periodic_interface"
    printf '  STAR periodic translation   : (%s,%s,%s) m\n' \
        "$periodic_translation_x" "$periodic_translation_y" \
        "$periodic_translation_z"
fi
if [[ "$run_rans" == true ]]; then
    rans_kinematic_viscosity="$(awk -v re="$rans_reynolds" \
        'BEGIN { printf "%.17g", 1.0/re }')"
    printf '  STAR RANS precursor         : SST, nondimensional U=1, rho=1, Re_c=%s\n' \
        "$rans_reynolds"
    printf '  STAR/Nektar viscosity       : mu=nu=1/Re=%s\n' \
        "$rans_kinematic_viscosity"
    printf '  STAR RANS incidence         : alpha=%s deg\n' "$rans_angle_deg"
    printf '  STAR RANS stopping          : max=%s OR (min=%s AND all residuals<%s)\n' \
        "$rans_max_steps" "$rans_min_steps" "$rans_residual_tolerance"
    printf '  STAR RANS acceptance        : residual convergence required=%s\n' \
        "$([[ "$rans_allow_unconverged" == true ]] && printf false || printf true)"
    if [[ "$skip_star" == true ]]; then
        printf '  STAR launcher MPI ranks     : mesh stage=skipped, RANS stage=%s\n' \
            "$rans_processes"
    else
        printf '  STAR launcher MPI ranks     : mesh stage=%s, RANS stage=%s\n' \
            "$star_processes" "$rans_processes"
    fi
    printf '  STAR parallelism note       : an individual mesher may still report serial execution\n'
    printf '  RANS mesh caveat            : using the one-layer handoff mesh (transfer smoke test)\n'
else
    printf '  STAR launcher MPI ranks     : mesh stage=%s\n' "$star_processes"
fi
if [[ "$skip_star" == true ]]; then
    if [[ "$run_rans" == true ]]; then
        printf '  execution plan              : STAR meshing skipped; STAR RANS ENABLED\n'
    else
        printf '  execution plan              : STAR meshing skipped; STAR RANS DISABLED\n'
    fi
    printf '  note: STAR mesh values are descriptive under --skip-star; they do not modify the reused CCM\n'
    printf '        --star-prism-height must match that CCM for the derived height to be meaningful\n'
fi

generated_outputs=(
    "nekmesh/${linear_stem}_linear.xml"
    "nekmesh/${linear_stem}_linear.vtu"
    "nekmesh/${projected_stem}.xml"
    "nekmesh/${projected_stem}.vtu"
    "nekmesh/${final_stem}.xml"
    "nekmesh/${final_stem}.vtu"
    "$quality_file"
    "logs/${case_name}_star_driver.log"
    "logs/${linear_stem}_linear_import.log"
    "logs/${linear_stem}_linear_fieldconvert.log"
    "logs/${projected_stem}_projectcad.log"
    "logs/${projected_stem}_jac.log"
    "logs/${projected_stem}_fieldconvert.log"
    "logs/${final_stem}_split.log"
    "logs/${final_stem}_jac.log"
    "logs/${final_stem}_fieldconvert.log"
    "logs/${case_name}_pipeline.provenance.txt"
)
if [[ -n "$star_step" && "$skip_star" != true ]]; then
    generated_outputs+=(
        "$star_template"
        "star/${case_name}_bootstrap.log"
        "star/${case_name}_bootstrap.provenance.txt"
        "logs/${case_name}_bootstrap_driver.log"
    )
fi
if [[ "$periodic_span" == true ]]; then
    generated_outputs+=(
        "nekmesh/${periodic_check_stem}.xml"
        "nekmesh/${split_stem}.xml"
        "nekmesh/${periodic_stem}.xml"
        "logs/${case_name}_peralign_preflight.log"
        "logs/${case_name}_peralign.log"
        "logs/${final_stem}_projectcad_restore.log"
    )
fi
if [[ "$run_rans" == true ]]; then
    generated_outputs+=(
        "star/${case_name}_rans.sim"
        "star/${case_name}_rans_raw.csv"
        "star/${case_name}_rans_nektar.csv"
        "star/${case_name}_rans.log"
        "star/${case_name}_rans.provenance.txt"
        "logs/${case_name}_rans_driver.log"
    )
fi
if [[ -n "$rans_session" ]]; then
    generated_outputs+=(
        "nekmesh/${case_name}_rans_initial.fld"
        "nekmesh/${case_name}_rans_initial.vtu"
        "logs/${case_name}_rans_interpolation.log"
    )
    if [[ "$rans_session_auto" == true ]]; then
        generated_outputs+=(
            "$rans_session"
            "logs/${case_name}_restart_session.log"
        )
    fi
fi

if [[ "$force" != true ]]; then
    for output in "${generated_outputs[@]}"; do
        if [[ -e "$output" ]]; then
            echo "Pipeline output exists (use --force): $output" >&2
            exit 1
        fi
    done
fi

force_arg=()
star_force_arg=()
if [[ "$force" == true ]]; then
    force_arg=(-f)
    star_force_arg=(--force)
fi

run_stage() {
    local label="$1"
    local log="$2"
    shift 2

    printf '[pipeline] %s\n' "$label"
    if "$@" >"$log" 2>&1; then
        printf '[pipeline] completed: %s (log: %s)\n' "$label" "$log"
    else
        local status=$?
        printf '[pipeline] failed: %s, status %s (log: %s)\n' \
            "$label" "$status" "$log" >&2
        tail -n 50 -- "$log" >&2 || true
        return "$status"
    fi
}

run_star_stage() {
    local star_args=(
        --np "$star_processes"
        --template "$star_template"
        --mesh-operation "$star_mesh_operation"
        --wing-control "$star_wing_control"
        --volume-control "$star_volume_control"
        --volume-part "$star_volume_part"
        --output-sim "star/${case_name}_meshed.sim"
        --output-ccm "$ccm_file"
        --log "star/${case_name}_star_batch.log"
        --provenance "star/${case_name}_linear.provenance.txt"
        --base-size "$star_base_size"
        --surface-target-pct "$star_surface_target_pct"
        --surface-min-pct "$star_surface_min_pct"
        --max-cell-pct "$star_max_cell_pct"
        --tet-growth "$star_tet_growth"
        --wing-target-pct "$star_wing_target_pct"
        --wing-min-pct "$star_wing_min_pct"
        --wing-curvature-points "$star_wing_curvature_points"
        --prism-height "$star_prism_height"
        --prism-layers "$star_prism_layers"
        --prism-stretching "$star_prism_stretching"
        --volume-size-pct "$star_volume_size_pct"
        --volume-x-min "$star_volume_x_min"
        --volume-x-max "$star_volume_x_max"
        --volume-y-min "$star_volume_y_min"
        --volume-y-max "$star_volume_y_max"
        --volume-z-min "$star_volume_z_min"
        --volume-z-max "$star_volume_z_max"
        "${star_force_arg[@]}"
    )
    if [[ -n "$star_executable" ]]; then
        star_args+=(--star-executable "$star_executable")
    fi
    if [[ "$power_on_demand" == true ]]; then
        STAR_POD_KEY="$pod_key" \
            "$script_dir/run_star_mesh.sh" \
            "${star_args[@]}" --power-on-demand
    else
        "$script_dir/run_star_mesh.sh" "${star_args[@]}"
    fi
}

run_star_bootstrap_stage() {
    local bootstrap_args=(
        --step "$star_step"
        --output-sim "$star_template"
        --log "star/${case_name}_bootstrap.log"
        --provenance "star/${case_name}_bootstrap.provenance.txt"
        --np "$star_processes"
        --periodic-translation-x "$periodic_translation_x"
        --periodic-translation-y "$periodic_translation_y"
        --periodic-translation-z "$periodic_translation_z"
        "${star_force_arg[@]}"
    )
    if [[ "$periodic_span" == true ]]; then
        bootstrap_args+=(--periodic-span)
    else
        bootstrap_args+=(--no-periodic-span)
    fi
    if [[ -n "$star_executable" ]]; then
        bootstrap_args+=(--star-executable "$star_executable")
    fi
    if [[ "$power_on_demand" == true ]]; then
        STAR_POD_KEY="$pod_key" "$script_dir/run_star_bootstrap.sh" \
            "${bootstrap_args[@]}" --power-on-demand
    else
        "$script_dir/run_star_bootstrap.sh" "${bootstrap_args[@]}"
    fi
}

run_rans_stage() {
    local rans_span_mode="symmetry"
    if [[ "$periodic_span" == true ]]; then
        rans_span_mode="periodic"
    fi
    local rans_args=(
        --input-sim "star/${case_name}_meshed.sim"
        --output-sim "star/${case_name}_rans.sim"
        --raw-table "star/${case_name}_rans_raw.csv"
        --output-csv "star/${case_name}_rans_nektar.csv"
        --log "star/${case_name}_rans.log"
        --provenance "star/${case_name}_rans.provenance.txt"
        --np "$rans_processes"
        --reynolds "$rans_reynolds"
        --angle-deg "$rans_angle_deg"
        --pressure "$rans_pressure"
        --turb-intensity "$rans_turb_intensity"
        --turb-visc-ratio "$rans_turb_visc_ratio"
        --max-steps "$rans_max_steps"
        --min-steps "$rans_min_steps"
        --residual-tol "$rans_residual_tolerance"
        --pressure-mode "$rans_pressure_mode"
        --span-mode "$rans_span_mode"
        --periodic-interface "$star_periodic_interface"
        "${star_force_arg[@]}"
    )
    if [[ -n "$star_executable" ]]; then
        rans_args+=(--star-executable "$star_executable")
    fi
    if [[ "$rans_allow_unconverged" == true ]]; then
        rans_args+=(--allow-unconverged)
    fi
    if [[ "$power_on_demand" == true ]]; then
        STAR_POD_KEY="$pod_key" "$script_dir/run_star_rans.sh" \
            "${rans_args[@]}" --power-on-demand
    else
        "$script_dir/run_star_rans.sh" "${rans_args[@]}"
    fi
}

require_nonempty() {
    if [[ ! -s "$1" ]]; then
        echo "Expected non-empty pipeline output is missing: $1" >&2
        exit 1
    fi
}

validate_jacobians() {
    local quality_log="$1"
    grep -oE \
        'Total negative Jacobians:[[:space:]]+[0-9]+|Worst Jacobian:[[:space:]]+[-+0-9.eE]+|Integration of Jacobian:[[:space:]]+[-+0-9.eE]+%' \
        "$quality_log" || true
    if ! grep -Eq 'Total negative Jacobians:[[:space:]]+0([[:space:]]|$)' \
        "$quality_log"; then
        echo "High-order mesh has negative Jacobians; stopping." >&2
        exit 1
    fi
}

validate_peralign() {
    local align_log="$1"
    if grep -Eq \
        'Skipping periodic alignment|skipping periodic alignment|different numbers of elements|Could not find matching (edge|face)' \
        "$align_log"; then
        echo "NekMesh could not establish the requested periodic pairing." >&2
        grep -E \
            'Skipping periodic alignment|skipping periodic alignment|different numbers of elements|Could not find matching (edge|face)' \
            "$align_log" >&2 || true
        exit 1
    fi
    if ! grep -Eq 'Orient\(necessary for Tet/Prisms\)[[:space:]]*=[[:space:]]*(1|true)' \
        "$align_log"; then
        echo "NekMesh peralign did not confirm hybrid-element orientation." >&2
        exit 1
    fi
}

started_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$skip_star" != true ]]; then
    if [[ -n "$star_step" ]]; then
        run_stage "STAR STEP-to-SIM bootstrap" \
            "logs/${case_name}_bootstrap_driver.log" run_star_bootstrap_stage
    fi
    run_stage "STAR mesh and CCM export" \
        "logs/${case_name}_star_driver.log" run_star_stage
else
    printf '[pipeline] skipping STAR meshing; reusing %s\n' "$ccm_file"
    if [[ "$run_rans" == true ]]; then
        printf '[pipeline] STAR RANS remains enabled and will run after the linear/periodic preflight\n'
    else
        printf '[pipeline] STAR RANS is disabled\n'
    fi
fi
require_nonempty "$ccm_file"

if [[ "$run_rans" != true ]]; then
    pod_key=""
fi

run_stage "linear CCM import" "logs/${linear_stem}_linear_import.log" \
    "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
    "$ccm_file" "nekmesh/${linear_stem}_linear.xml"
require_nonempty "nekmesh/${linear_stem}_linear.xml"

run_stage "linear VTU export" "logs/${linear_stem}_linear_fieldconvert.log" \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "nekmesh/${linear_stem}_linear.xml" "nekmesh/${linear_stem}_linear.vtu"
require_nonempty "nekmesh/${linear_stem}_linear.vtu"

if [[ "$periodic_span" == true ]]; then
    # This first pass is deliberately discarded. It cheaply proves that the
    # two STAR composites are one-to-one before a RANS solve or HO processing.
    run_stage "spanwise periodic preflight" "logs/${case_name}_peralign_preflight.log" \
        "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
        -m "peralign:surf1=${periodic_surf1}:surf2=${periodic_surf2}:dir=${periodic_dir}:orient:tolfac=${periodic_tolfac}:abstol=${periodic_abstol}" \
        "nekmesh/${linear_stem}_linear.xml" "nekmesh/${periodic_check_stem}.xml"
    validate_peralign "logs/${case_name}_peralign_preflight.log"
    require_nonempty "nekmesh/${periodic_check_stem}.xml"
fi

# For a periodic run, do not spend RANS iterations until peralign has proved
# that the newly generated STAR span meshes have a one-to-one pairing.
if [[ "$run_rans" == true ]]; then
    run_stage "STAR steady SST RANS precursor" \
        "logs/${case_name}_rans_driver.log" run_rans_stage
    require_nonempty "star/${case_name}_rans_nektar.csv"
    pod_key=""
fi

run_stage "order-${cad_order} CAD projection" "logs/${projected_stem}_projectcad.log" \
    "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
    -m "projectcad:file=${cad_file}:order=${cad_order}" \
    "nekmesh/${linear_stem}_linear.xml" "nekmesh/${projected_stem}.xml"
require_nonempty "nekmesh/${projected_stem}.xml"

run_stage "order-${cad_order} Jacobian check" "logs/${projected_stem}_jac.log" \
    "$nektar_script_dir/nekmesh_docker.sh" -v -m jac:quality \
    "nekmesh/${projected_stem}.xml" unused:stdout
validate_jacobians "logs/${projected_stem}_jac.log"

run_stage "order-${cad_order} native high-order VTU" "logs/${projected_stem}_fieldconvert.log" \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "nekmesh/${projected_stem}.xml" "nekmesh/${projected_stem}.vtu:vtu:highorder"
require_nonempty "nekmesh/${projected_stem}.vtu"

bl_output_stem="$final_stem"
if [[ "$periodic_span" == true ]]; then
    bl_output_stem="$split_stem"
fi

run_stage "${bl_layers}-layer prism split" "logs/${final_stem}_split.log" \
    "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
    -m "bl:surf=${bl_surface}:layers=${bl_layers}:r=${bl_ratio}:nq=${bl_nq}" \
    "nekmesh/${projected_stem}.xml" "nekmesh/${bl_output_stem}.xml"
require_nonempty "nekmesh/${bl_output_stem}.xml"

if [[ "$periodic_span" == true ]]; then
    # The installed peralign module specifically requires orient to be run
    # after BL splitting for a tet-prism hybrid. Reordering recreates tets and
    # drops face-interior curvature, so restore CAD curvature afterwards.
    run_stage "final spanwise periodic alignment" "logs/${case_name}_peralign.log" \
        "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
        -m "peralign:surf1=${periodic_surf1}:surf2=${periodic_surf2}:dir=${periodic_dir}:orient:tolfac=${periodic_tolfac}:abstol=${periodic_abstol}" \
        "nekmesh/${split_stem}.xml" "nekmesh/${periodic_stem}.xml"
    validate_peralign "logs/${case_name}_peralign.log"
    require_nonempty "nekmesh/${periodic_stem}.xml"

    run_stage "post-peralign CAD curvature restoration" \
        "logs/${final_stem}_projectcad_restore.log" \
        "$nektar_script_dir/nekmesh_docker.sh" "${force_arg[@]}" -v \
        -m "projectcad:file=${cad_file}:order=${cad_order}" \
        "nekmesh/${periodic_stem}.xml" "nekmesh/${final_stem}.xml"
    require_nonempty "nekmesh/${final_stem}.xml"
fi

run_stage "split-mesh Jacobian audit" "logs/${final_stem}_jac.log" \
    "$nektar_script_dir/nekmesh_docker.sh" -v \
    -m "jac:histo=${jac_threshold},14,8:quality:detail:histofile=${quality_file}" \
    "nekmesh/${final_stem}.xml" unused:stdout
validate_jacobians "logs/${final_stem}_jac.log"
require_nonempty "$quality_file"

run_stage "split-mesh native high-order VTU" \
    "logs/${final_stem}_fieldconvert.log" \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "nekmesh/${final_stem}.xml" \
    "nekmesh/${final_stem}.vtu:vtu:highorder"
require_nonempty "nekmesh/${final_stem}.vtu"

if [[ -n "$rans_session" ]]; then
    if [[ "$rans_session_auto" == true ]]; then
        restart_force=()
        [[ "$force" == true ]] && restart_force=(--force)
        run_stage "Nektar restart-session generation" \
            "logs/${case_name}_restart_session.log" \
            python3 "$nektar_script_dir/prepare_nektar_restart_session.py" \
            "nekmesh/${final_stem}.xml" "$rans_session" \
            --num-modes "$rans_num_modes" "${restart_force[@]}"
        require_nonempty "$rans_session"
    fi
    run_stage "STAR RANS field interpolation onto Nektar expansion" \
        "logs/${case_name}_rans_interpolation.log" \
        "$nektar_script_dir/rans_csv_to_nektar_fld.sh" \
        --session "$rans_session" \
        --csv "star/${case_name}_rans_nektar.csv" \
        --output "nekmesh/${case_name}_rans_initial.fld" \
        --vtu "nekmesh/${case_name}_rans_initial.vtu" \
        "${star_force_arg[@]}"
    require_nonempty "nekmesh/${case_name}_rans_initial.fld"
    require_nonempty "nekmesh/${case_name}_rans_initial.vtu"
fi

provenance="logs/${case_name}_pipeline.provenance.txt"
{
    printf 'started_utc=%s\n' "$started_utc"
    printf 'completed_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'host=%s\n' "$(hostname)"
    printf 'star_skipped=%s\n' "$skip_star"
    printf 'star_parameters_applied=%s\n' "$([[ "$skip_star" == true ]] && printf false || printf true)"
    printf 'star_license_mode=%s\n' "$([[ "$power_on_demand" == true ]] && printf power-on-demand || printf default)"
    printf 'star_processes=%s\n' "$star_processes"
    printf 'rans_processes=%s\n' "$rans_processes"
    printf 'star_template=%s\n' "$star_template"
    printf 'star_step=%s\n' "$star_step"
    printf 'star_mesh_operation=%s\n' "$star_mesh_operation"
    printf 'star_wing_control=%s\n' "$star_wing_control"
    printf 'star_volume_control=%s\n' "$star_volume_control"
    printf 'star_volume_part=%s\n' "$star_volume_part"
    printf 'case_name=%s\n' "$case_name"
    printf 'cad_file=%s\n' "$cad_file"
    printf 'ccm_file=%s\n' "$ccm_file"
    printf 'cad_order=%s\n' "$cad_order"
    printf 'bl_surface=%s\n' "$bl_surface"
    printf 'bl_layers=%s\n' "$bl_layers"
    printf 'bl_ratio=%s\n' "$bl_ratio"
    printf 'bl_nq=%s\n' "$bl_nq"
    printf 'jac_threshold=%s\n' "$jac_threshold"
    printf 'periodic_span=%s\n' "$periodic_span"
    printf 'periodic_surf1=%s\n' "$periodic_surf1"
    printf 'periodic_surf2=%s\n' "$periodic_surf2"
    printf 'periodic_direction=%s\n' "$periodic_dir"
    printf 'periodic_translation_x_m=%s\n' "$periodic_translation_x"
    printf 'periodic_translation_y_m=%s\n' "$periodic_translation_y"
    printf 'periodic_translation_z_m=%s\n' "$periodic_translation_z"
    printf 'periodic_tolfac=%s\n' "$periodic_tolfac"
    printf 'periodic_abstol=%s\n' "$periodic_abstol"
    printf 'star_periodic_interface=%s\n' "$star_periodic_interface"
    printf 'rans_enabled=%s\n' "$run_rans"
    printf 'rans_nondimensional_velocity=%s\n' "1.0"
    printf 'rans_angle_deg=%s\n' "$rans_angle_deg"
    printf 'rans_nondimensional_density=%s\n' "1.0"
    printf 'rans_reynolds=%s\n' "$rans_reynolds"
    printf 'rans_nondimensional_kinematic_viscosity=%s\n' \
        "$(awk -v re="$rans_reynolds" 'BEGIN { printf "%.17g", 1.0/re }')"
    printf 'rans_reference_pressure=%s\n' "$rans_pressure"
    printf 'rans_turbulence_intensity=%s\n' "$rans_turb_intensity"
    printf 'rans_turbulent_viscosity_ratio=%s\n' "$rans_turb_visc_ratio"
    printf 'rans_maximum_steps=%s\n' "$rans_max_steps"
    printf 'rans_minimum_steps=%s\n' "$rans_min_steps"
    printf 'rans_residual_tolerance=%s\n' "$rans_residual_tolerance"
    printf 'rans_allow_unconverged=%s\n' "$rans_allow_unconverged"
    printf 'rans_pressure_mode=%s\n' "$rans_pressure_mode"
    printf 'rans_session=%s\n' "$rans_session"
    printf 'rans_session_auto=%s\n' "$rans_session_auto"
    printf 'rans_num_modes=%s\n' "$rans_num_modes"
    printf 'star_base_size_m=%s\n' "$star_base_size"
    printf 'star_surface_target_pct=%s\n' "$star_surface_target_pct"
    printf 'star_surface_min_pct=%s\n' "$star_surface_min_pct"
    printf 'star_max_cell_pct=%s\n' "$star_max_cell_pct"
    printf 'star_tet_growth_rate=%s\n' "$star_tet_growth"
    printf 'star_wing_target_pct=%s\n' "$star_wing_target_pct"
    printf 'star_wing_min_pct=%s\n' "$star_wing_min_pct"
    printf 'star_wing_curvature_points=%s\n' "$star_wing_curvature_points"
    printf 'star_volume_size_pct=%s\n' "$star_volume_size_pct"
    printf 'star_volume_size_m=%s\n' "$volume_size_m"
    printf 'star_volume_x_min_m=%s\n' "$star_volume_x_min"
    printf 'star_volume_x_max_m=%s\n' "$star_volume_x_max"
    printf 'star_volume_y_min_m=%s\n' "$star_volume_y_min"
    printf 'star_volume_y_max_m=%s\n' "$star_volume_y_max"
    printf 'star_volume_z_min_m=%s\n' "$star_volume_z_min"
    printf 'star_volume_z_max_m=%s\n' "$star_volume_z_max"
    printf 'star_prism_height_m=%s\n' "$star_prism_height"
    printf 'star_prism_layers=%s\n' "$star_prism_layers"
    printf 'star_prism_stretching=%s\n' "$star_prism_stretching"
    printf 'derived_global_target_m=%s\n' "$global_target_m"
    printf 'derived_global_min_m=%s\n' "$global_min_m"
    printf 'derived_wing_target_m=%s\n' "$wing_target_m"
    printf 'derived_wing_min_m=%s\n' "$wing_min_m"
    printf 'derived_volume_size_m=%s\n' "$volume_size_m"
    printf 'derived_first_split_height_m=%s\n' "$first_split_height_m"
    printf 'container_runtime_request=%s\n' "${NEKTAR_CONTAINER_RUNTIME:-auto}"
    printf 'nektar_release=%s\n' "$NEKTAR_RELEASE_DEFAULT"
    printf 'nektar_image=%s\n' "${NEKTAR_CONTAINER_IMAGE:-$NEKTAR_IMAGE_DEFAULT}"
    for output in \
        "$cad_file" \
        "$ccm_file" \
        "nekmesh/${linear_stem}_linear.xml" \
        "nekmesh/${linear_stem}_linear.vtu" \
        "nekmesh/${projected_stem}.xml" \
        "nekmesh/${projected_stem}.vtu" \
        "nekmesh/${final_stem}.xml" \
        "nekmesh/${final_stem}.vtu" \
        "$quality_file"; do
        printf 'sha256[%s]=%s\n' "$output" "$(sha256sum "$output" | awk '{print $1}')"
    done
    if [[ "$run_rans" == true ]]; then
        for output in \
            "star/${case_name}_rans.sim" \
            "star/${case_name}_rans_raw.csv" \
            "star/${case_name}_rans_nektar.csv"; do
            printf 'sha256[%s]=%s\n' "$output" "$(sha256sum "$output" | awk '{print $1}')"
        done
    fi
    if [[ "$periodic_span" == true ]]; then
        printf 'sha256[%s]=%s\n' "nekmesh/${periodic_stem}.xml" \
            "$(sha256sum "nekmesh/${periodic_stem}.xml" | awk '{print $1}')"
    fi
    if [[ -n "$rans_session" ]]; then
        printf 'sha256[%s]=%s\n' "$rans_session" "$(sha256sum "$rans_session" | awk '{print $1}')"
        printf 'sha256[%s]=%s\n' "nekmesh/${case_name}_rans_initial.fld" \
            "$(sha256sum "nekmesh/${case_name}_rans_initial.fld" | awk '{print $1}')"
    fi
} >"$provenance"

printf '[pipeline] complete\n'
printf '[pipeline] final mesh: nekmesh/%s.xml\n' "$final_stem"
printf '[pipeline] final VTU : nekmesh/%s.vtu\n' "$final_stem"
if [[ "$run_rans" == true ]]; then
    printf '[pipeline] RANS CSV  : star/%s_rans_nektar.csv\n' "$case_name"
fi
if [[ "$periodic_span" == true ]]; then
    printf '[pipeline] periodic  : nekmesh/%s.xml\n' "$periodic_stem"
fi
if [[ -n "$rans_session" ]]; then
    printf '[pipeline] initial fld: nekmesh/%s_rans_initial.fld\n' "$case_name"
    printf '[pipeline] initial VTU: nekmesh/%s_rans_initial.vtu\n' "$case_name"
fi
printf '[pipeline] metadata  : %s\n' "$provenance"
