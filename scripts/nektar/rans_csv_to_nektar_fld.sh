#!/usr/bin/env bash
# Interpolate STAR cell-centre RANS samples onto a Nektar++ expansion.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
csv_file="star/naca0012_rans_nektar.csv"
session_file=""
output_fld="nekmesh/naca0012_rans_initial.fld"
output_vtu=""
force=false

usage() {
    cat <<'EOF'
Usage: scripts/nektar/rans_csv_to_nektar_fld.sh --session FILE [options]

Interpolate normalized STAR x,y,z,u,v,w,p cell-centre data onto the expansion
points defined by a Nektar++ session and write an initial-condition .fld file.

Options:
  --session FILE     Nektar++ XML session containing GEOMETRY and EXPANSIONS
  --csv FILE         Normalized STAR point-data CSV
                     (default: star/naca0012_rans_nektar.csv)
  --output FILE      Output field (default: nekmesh/naca0012_rans_initial.fld)
  --vtu FILE         Also export the interpolated field for inspection
  --force            Permit replacement of existing outputs
  -h, --help         Show this help

The session's EXPANSIONS FIELDS must be compatible with u,v,w,p. For a first
P4 checkpoint use, for example:

  <EXPANSIONS>
    <E COMPOSITE="C[0]" NUMMODES="5" TYPE="MODIFIED" FIELDS="u,v,w,p" />
  </EXPANSIONS>

NUMMODES is the number of modes; check the convention used by the intended
solver session rather than inferring it from the curved geometry order.
EOF
}

while (($#)); do
    case "$1" in
        --session)
            [[ $# -ge 2 ]] || {
                echo "--session requires a value" >&2
                exit 2
            }
            session_file="$2"
            shift 2
            ;;
        --csv)
            [[ $# -ge 2 ]] || {
                echo "--csv requires a value" >&2
                exit 2
            }
            csv_file="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || {
                echo "--output requires a value" >&2
                exit 2
            }
            output_fld="$2"
            shift 2
            ;;
        --vtu)
            [[ $# -ge 2 ]] || {
                echo "--vtu requires a value" >&2
                exit 2
            }
            output_vtu="$2"
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

[[ -n "$session_file" ]] || {
    echo "--session is required." >&2
    exit 2
}
for path in "$session_file" "$csv_file" "$output_fld" "$output_vtu"; do
    [[ -z "$path" || ("$path" != /* && "$path" != *:*) ]] || {
        echo "Paths must be colon-free and relative to the tutorial root: $path" >&2
        exit 2
    }
done

cd "$project_dir"
[[ -s "$session_file" ]] || {
    echo "Session is missing or empty: $session_file" >&2
    exit 1
}
[[ -s "$csv_file" ]] || {
    echo "RANS CSV is missing or empty: $csv_file" >&2
    exit 1
}
grep -q '<EXPANSIONS' "$session_file" || {
    echo "Session has no EXPANSIONS block: $session_file" >&2
    echo "A bare NekMesh geometry XML is insufficient for field interpolation." >&2
    exit 1
}
grep -Eq 'FIELDS="[^"]*(u|v|w|p)' "$session_file" || {
    echo "Session EXPANSIONS do not appear to define u,v,w,p." >&2
    exit 1
}

outputs=("$output_fld")
[[ -z "$output_vtu" ]] || outputs+=("$output_vtu")
if [[ "$force" != true ]]; then
    for output in "${outputs[@]}"; do
        [[ ! -e "$output" ]] || {
            echo "Output exists (use --force): $output" >&2
            exit 1
        }
    done
fi
mkdir -p -- "$(dirname -- "$output_fld")"
[[ -z "$output_vtu" ]] || mkdir -p -- "$(dirname -- "$output_vtu")"

fieldconvert_force=()
[[ "$force" == true ]] && fieldconvert_force=(-f)
"$script_dir/fieldconvert_docker.sh" "${fieldconvert_force[@]}" -v \
    -m "interppointdatatofld:frompts=${csv_file}" \
    "$session_file" "$output_fld"
[[ -s "$output_fld" ]] || {
    echo "FieldConvert did not create: $output_fld" >&2
    exit 1
}

if [[ -n "$output_vtu" ]]; then
    "$script_dir/fieldconvert_docker.sh" "${fieldconvert_force[@]}" -v \
        "$session_file" "$output_fld" "$output_vtu:vtu:highorder"
    [[ -s "$output_vtu" ]] || {
        echo "FieldConvert did not create: $output_vtu" >&2
        exit 1
    }
fi

echo "Nektar initial field: $output_fld"
[[ -z "$output_vtu" ]] || echo "Inspection VTU     : $output_vtu"
