#!/usr/bin/env bash
# Three-level STAR resolution study with fixed high-order NekMesh parameters.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
# shellcheck source=scripts/workflow/lib/common.sh
source "$script_dir/lib/common.sh"

execute=false
force=false
power_on_demand=false
periodic_span=false
star_processes=1
star_template="star/naca0012_mesh_template.sim"
star_periodic_interface="SpanwisePeriodic"
name_prefix="naca0012_star"
macro_height="0.03"
selected_level="all"
volume_size_pct="5.0"
volume_x_min="-0.25"
volume_x_max="1.50"
volume_y_min="-0.30"
volume_y_max="0.30"
volume_z_min="-0.01"
volume_z_max="0.21"

usage() {
    cat <<'EOF'
Usage: scripts/workflow/run_resolution_study.sh [options]

Plan or execute three complete STAR -> NekMesh resolution variants. The
characteristic STAR sizes halve per level, targeting twice as many elements
in each spatial direction. A tetrahedral volume would therefore grow by
approximately 8x per level. NekMesh is fixed at P=4, 8 boundary layers and
outward ratio 1.2.

Options:
  --execute             Actually run the three pipelines (default: plan only)
  --power-on-demand     Supply STAR_POD_KEY to each STAR invocation
  --periodic-span       Require SpanMin/SpanMax peralign at every level
  --force               Permit replacement of each variant's outputs
  --star-np N           STAR process count (default: 1)
  --star-template FILE  Prepared STAR template (use a conformal periodic
                        template together with --periodic-span)
  --star-periodic-interface NAME
                        Interface required by periodic STAR RANS
                        (default: SpanwisePeriodic)
  --name-prefix NAME    Variant prefix (default: naca0012_star)
  --macro-height M      Fixed STAR macro-prism height in metres (default: .03)
  --volume-size-pct P   Refinement size as % of each level's base (default: 5)
  --volume-x-min M      Refinement-box minimum x (default: -0.25 m)
  --volume-x-max M      Refinement-box maximum x (default: 1.50 m)
  --volume-y-min M      Refinement-box minimum y (default: -0.30 m)
  --volume-y-max M      Refinement-box maximum y (default: 0.30 m)
  --volume-z-min M      Refinement-box minimum z (default: -0.01 m)
  --volume-z-max M      Refinement-box maximum z (default: 0.21 m)
  --level N             Run only level 0, 1 or 2 (default: plan/run all)
  -h, --help            Show this help

The three output names are PREFIX_r0, PREFIX_r1 and PREFIX_r2. The macro-prism
height is held fixed so the physical boundary-layer depth and the final split
heights are not changed by the tangential/volume refinement.
EOF
}

while (($#)); do
    case "$1" in
        --execute)
            execute=true
            shift
            ;;
        --power-on-demand)
            power_on_demand=true
            shift
            ;;
        --periodic-span)
            periodic_span=true
            shift
            ;;
        --force)
            force=true
            shift
            ;;
        --star-np)
            require_arg --star-np "$#"
            star_processes="$2"
            shift 2
            ;;
        --star-template)
            require_arg --star-template "$#"
            star_template="$2"
            shift 2
            ;;
        --star-periodic-interface)
            require_arg --star-periodic-interface "$#"
            star_periodic_interface="$2"
            shift 2
            ;;
        --name-prefix)
            require_arg --name-prefix "$#"
            name_prefix="$2"
            shift 2
            ;;
        --macro-height)
            require_arg --macro-height "$#"
            macro_height="$2"
            shift 2
            ;;
        --volume-size-pct)
            require_arg --volume-size-pct "$#"
            volume_size_pct="$2"
            shift 2
            ;;
        --volume-x-min)
            require_arg --volume-x-min "$#"
            volume_x_min="$2"
            shift 2
            ;;
        --volume-x-max)
            require_arg --volume-x-max "$#"
            volume_x_max="$2"
            shift 2
            ;;
        --volume-y-min)
            require_arg --volume-y-min "$#"
            volume_y_min="$2"
            shift 2
            ;;
        --volume-y-max)
            require_arg --volume-y-max "$#"
            volume_y_max="$2"
            shift 2
            ;;
        --volume-z-min)
            require_arg --volume-z-min "$#"
            volume_z_min="$2"
            shift 2
            ;;
        --volume-z-max)
            require_arg --volume-z-max "$#"
            volume_z_max="$2"
            shift 2
            ;;
        --level)
            require_arg --level "$#"
            selected_level="$2"
            shift 2
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
if [[ ! "$name_prefix" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "--name-prefix contains unsupported characters: $name_prefix" >&2
    exit 2
fi
if ! awk -v value="$macro_height" 'BEGIN { exit !(value > 0) }'; then
    echo "--macro-height must be positive: $macro_height" >&2
    exit 2
fi
if ! awk -v value="$volume_size_pct" 'BEGIN { exit !(value > 0) }'; then
    echo "--volume-size-pct must be positive: $volume_size_pct" >&2
    exit 2
fi
validate_real_number --volume-x-min "$volume_x_min"
validate_real_number --volume-x-max "$volume_x_max"
validate_real_number --volume-y-min "$volume_y_min"
validate_real_number --volume-y-max "$volume_y_max"
validate_real_number --volume-z-min "$volume_z_min"
validate_real_number --volume-z-max "$volume_z_max"
for axis in x y z; do
    min_name="volume_${axis}_min"
    max_name="volume_${axis}_max"
    if ! awk -v lo="${!min_name}" -v hi="${!max_name}" \
        'BEGIN { exit !(lo < hi) }'; then
        echo "--volume-${axis}-min must be less than --volume-${axis}-max." >&2
        exit 2
    fi
done
if [[ "$selected_level" != all && ! "$selected_level" =~ ^[012]$ ]]; then
    echo "--level must be 0, 1 or 2: $selected_level" >&2
    exit 2
fi

# h_i/h_0 = 2^(-i). Curvature points scale inversely with h so the
# leading-edge curvature constraint refines with the target/minimum sizes.
levels=(r0 r1 r2)
base_sizes=(1.0 0.5 0.25)
curvature_points=(36 72 144)

printf '%-5s %-28s %12s %12s %14s %12s\n' \
    level name base_size_m curvature volume_size_m tet_work
printf '%-5s %-28s %12s %12s %14s %12s\n' \
    ----- ---- ----------- --------- ------------- --------
indices=(0 1 2)
if [[ "$selected_level" != all ]]; then
    indices=("$selected_level")
fi

for index in "${indices[@]}"; do
    relative_tet_work="$((8 ** index))x"
    level_volume_size="$(awk -v b="${base_sizes[$index]}" -v p="$volume_size_pct" \
        'BEGIN { printf "%.9g", b*p/100 }')"
    printf '%-5s %-28s %12s %12s %14s %12s\n' \
        "${levels[$index]}" "${name_prefix}_${levels[$index]}" \
        "${base_sizes[$index]}" "${curvature_points[$index]}" \
        "$level_volume_size" "$relative_tet_work"
done
printf '\nFixed NekMesh settings: P=4, layers=8, ratio=1.2, nq=5 (automatic)\n'
printf 'Spanwise peralign: %s\n' "$periodic_span"
printf 'STAR template: %s\n' "$star_template"
first_height="$(awk -v h="$macro_height" \
    'BEGIN { r=1.2; n=8; printf "%.9g", h*(r-1)/(r^n-1) }')"
printf 'Fixed STAR macro height: %s m; derived first split height: %s m\n' \
    "$macro_height" "$first_height"
printf 'Fixed STAR volume box: (%s,%s,%s) -> (%s,%s,%s) m\n' \
    "$volume_x_min" "$volume_y_min" "$volume_z_min" \
    "$volume_x_max" "$volume_y_max" "$volume_z_max"

if [[ "$execute" != true ]]; then
    printf '\nPlan only. Add --execute when ready to run the selected variant(s).\n'
    exit 0
fi

pod_key="${STAR_POD_KEY:-}"
unset STAR_POD_KEY
if [[ "$power_on_demand" == true && -z "$pod_key" ]]; then
    echo "--power-on-demand requires STAR_POD_KEY." >&2
    exit 2
fi

common_args=(
    --star-np "$star_processes"
    --star-template "$star_template"
    --star-periodic-interface "$star_periodic_interface"
    --star-prism-height "$macro_height"
    --star-volume-size-pct "$volume_size_pct"
    --star-volume-x-min "$volume_x_min"
    --star-volume-x-max "$volume_x_max"
    --star-volume-y-min "$volume_y_min"
    --star-volume-y-max "$volume_y_max"
    --star-volume-z-min "$volume_z_min"
    --star-volume-z-max "$volume_z_max"
    --cad-order 4
    --bl-layers 8
    --bl-ratio 1.2
)
if [[ "$force" == true ]]; then
    common_args+=(--force)
fi
if [[ "$periodic_span" == true ]]; then
    common_args+=(--periodic-span)
fi

cd "$project_dir"
for index in "${indices[@]}"; do
    variant="${name_prefix}_${levels[$index]}"
    variant_args=(
        --name "$variant"
        --star-base-size "${base_sizes[$index]}"
        --star-wing-curvature "${curvature_points[$index]}"
        "${common_args[@]}"
    )

    printf '\n[study] starting %s\n' "$variant"
    if [[ "$power_on_demand" == true ]]; then
        STAR_POD_KEY="$pod_key" "$script_dir/run_remote_pipeline.sh" \
            --power-on-demand "${variant_args[@]}"
    else
        "$script_dir/run_remote_pipeline.sh" "${variant_args[@]}"
    fi
done
pod_key=""

printf '\n%-5s %12s %12s %12s %12s\n' \
    level elements tets prisms ratio_prev
printf '%-5s %12s %12s %12s %12s\n' \
    ----- -------- ---- ------ ----------
previous=""
for index in "${!levels[@]}"; do
    level="${levels[$index]}"
    log="logs/${name_prefix}_${level}_linear_import.log"
    if [[ ! -s "$log" ]]; then
        continue
    fi
    elements="$(awk '/\[InputStar\].* Elements$/ {print $(NF-1); exit}' "$log")"
    prisms="$(awk '/# of prisms:/ {print $NF; exit}' "$log")"
    tets="$(awk '/# of tetrahedra:/ {print $NF; exit}' "$log")"
    ratio="-"
    if [[ -n "$previous" ]]; then
        ratio="$(awk -v current="$elements" -v old="$previous" \
            'BEGIN { printf "%.3f", current/old }')"
    fi
    printf '%-5s %12s %12s %12s %12s\n' \
        "$level" "$elements" "$tets" "$prisms" "$ratio"
    previous="$elements"
done

printf '\nThe 8x tetrahedral-work factors are scaling estimates, not constraints. Surface\n'
printf 'triangles and macro prisms should scale closer to 4x per level.\n'
