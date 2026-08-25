#!/usr/bin/env bash
# Compute wing wall shear stress from a Nektar field.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"
nektar_script_dir="$project_dir/scripts/nektar"
# shellcheck source=scripts/workflow/lib/common.sh
source "$script_dir/lib/common.sh"

mesh_file=""
session_file=""
field_file=""
output_dir=""
prefix="wing_wss"
boundary_id=0
surface_id=4
reynolds="684587.012"
processes=1
force=false

usage() {
    cat <<'EOF'
Usage: scripts/workflow/postprocess_wall_shear.sh [options]

Compute the wall-shear vector/magnitude and extract mean pressure on the wing
with FieldConvert's wss and extract modules. Skin-friction normalization is
deliberately left to downstream analysis.

Required:
  --mesh FILE       Full high-order Nektar mesh XML
  --session FILE    Solver session XML containing Kinvis/Reynolds
  --field FILE      Solver FLD or checkpoint file/directory; use the final
                    AverageFields output (mean_fields_avg.fld) for mean WSS
  --output-dir DIR  Repository-relative output directory

Options:
  --prefix NAME       Output prefix (default: wing_wss)
  --boundary ID       Nektar boundary-region ID for wss (default: 0, Wing)
  --surface ID        NekMesh composite ID for extraction (default: 4, Wing)
  --reynolds RE       Override the session Reynolds parameter
                      (default: 684587.012)
  --np N              MPI ranks for the expensive wss and boundary-extract
                      modules (default: 1)
                      Nektar++ 5.10.0 is only validated here with N=1;
                      every result is rejected if its field norms are non-finite
  --force             Replace existing outputs
  -h, --help          Show this help

Outputs:
  OUTPUT_DIR/wing_surface.xml
  OUTPUT_DIR/PREFIX.fld
  OUTPUT_DIR/PREFIX.csv
  OUTPUT_DIR/PREFIX.vtu
  OUTPUT_DIR/PRESSURE_PREFIX.fld
  OUTPUT_DIR/PRESSURE_PREFIX.csv
  OUTPUT_DIR/PRESSURE_PREFIX.vtu

The FLD contains the native `wss` output: Shear_x, Shear_y, Shear_z and
Shear_mag. It does not contain hand-derived skin-friction coefficients. The
pressure outputs contain only p. For PREFIX=mean_fields_wss, PRESSURE_PREFIX
is mean_fields_pressure.
EOF
}

while (($#)); do
    case "$1" in
        --mesh)
            require_arg --mesh "$#"
            mesh_file="$2"
            shift 2
            ;;
        --session)
            require_arg --session "$#"
            session_file="$2"
            shift 2
            ;;
        --field)
            require_arg --field "$#"
            field_file="$2"
            shift 2
            ;;
        --output-dir)
            require_arg --output-dir "$#"
            output_dir="$2"
            shift 2
            ;;
        --prefix)
            require_arg --prefix "$#"
            prefix="$2"
            shift 2
            ;;
        --boundary)
            require_arg --boundary "$#"
            boundary_id="$2"
            shift 2
            ;;
        --surface)
            require_arg --surface "$#"
            surface_id="$2"
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

for required in mesh_file session_file field_file output_dir; do
    [[ -n "${!required}" ]] || {
        echo "Missing required option corresponding to $required." >&2
        exit 2
    }
done
for path in "$mesh_file" "$session_file" "$field_file" "$output_dir"; do
    require_repo_relative_path "Paths must be repository-relative and colon-free" "$path"
done
[[ "$prefix" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "--prefix contains unsupported characters: $prefix" >&2
    exit 2
}
[[ "$boundary_id" =~ ^[0-9]+$ ]] || {
    echo "--boundary must be a non-negative integer: $boundary_id" >&2
    exit 2
}
[[ "$surface_id" =~ ^[0-9]+$ ]] || {
    echo "--surface must be a non-negative integer: $surface_id" >&2
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

cd "$project_dir"
[[ -s "$mesh_file" ]] || { echo "Mesh is missing or empty: $mesh_file" >&2; exit 1; }
[[ -s "$session_file" ]] || { echo "Session is missing or empty: $session_file" >&2; exit 1; }
[[ -e "$field_file" ]] || { echo "Field/checkpoint is missing: $field_file" >&2; exit 1; }

mkdir -p -- "$output_dir"
surface_xml="$output_dir/wing_surface.xml"
wss_fld="$output_dir/${prefix}.fld"
wss_csv="$output_dir/${prefix}.csv"
wss_vtu="$output_dir/${prefix}.vtu"
if [[ "$prefix" == *_wss ]]; then
    pressure_prefix="${prefix%_wss}_pressure"
else
    pressure_prefix="${prefix}_pressure"
fi
pressure_fld="$output_dir/${pressure_prefix}.fld"
pressure_csv="$output_dir/${pressure_prefix}.csv"
pressure_vtu="$output_dir/${pressure_prefix}.vtu"
outputs=(
    "$surface_xml"
    "$wss_fld" "$wss_csv" "$wss_vtu"
    "$pressure_fld" "$pressure_csv" "$pressure_vtu"
)
if [[ "$force" != true ]]; then
    for output in "${outputs[@]}"; do
        [[ ! -e "$output" ]] || {
            echo "Output exists (use --force): $output" >&2
            exit 1
        }
    done
else
    for output in "${outputs[@]}"; do
        [[ ! -e "$output" && ! -L "$output" ]] || rm -rf -- "$output"
    done
fi

temporary_dir="$(mktemp -d "$output_dir/.wall-shear.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT
raw_request="$temporary_dir/raw_wss.fld"
wall_session="$temporary_dir/wall_session.xml"
wss_audit="$temporary_dir/wss_audit.fld"
wss_audit_log="$temporary_dir/wss_audit.log"
pressure_request="$temporary_dir/raw_pressure.fld"
pressure_audit="$temporary_dir/pressure_audit.fld"
pressure_audit_log="$temporary_dir/pressure_audit.log"
temporary_wss_csv="$temporary_dir/wss.csv"
temporary_pressure_csv="$temporary_dir/pressure.csv"

# FieldConvert does not expose the solver's -P parameter override. Reproduce
# the actual solver Reynolds value in a private session so Kinvis=1/Reynolds
# is evaluated consistently when wss forms the viscous traction.
awk -v reynolds="$reynolds" '
    /<P>[[:space:]]*Reynolds[[:space:]]*=/ {
        sub(/=.*/, "= " reynolds " </P>")
        found=1
    }
    { print }
    END { if (!found) exit 3 }
' "$session_file" >"$wall_session" || {
    echo "Could not override Reynolds in session: $session_file" >&2
    exit 1
}

"$nektar_script_dir/nekmesh_docker.sh" -f -v \
    -m "extract:surf=${surface_id}" "$mesh_file" "$surface_xml"

env NEKTAR_FIELDCONVERT_NP="$processes" \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    -m "wss:bnd=${boundary_id}" \
    "$mesh_file" "$wall_session" "$field_file" "$raw_request"

raw_wss="$raw_request"
if [[ ! -e "$raw_wss" ]]; then
    raw_wss="${raw_request%.fld}_b${boundary_id}.fld"
fi
if [[ -f "$raw_wss" ]]; then
    raw_wss_has_data=false
    [[ -s "$raw_wss" ]] && raw_wss_has_data=true
elif [[ -d "$raw_wss" ]]; then
    raw_wss_has_data=false
    [[ -n "$(find "$raw_wss" -type f -size +0c -print -quit)" ]] && raw_wss_has_data=true
else
    raw_wss_has_data=false
fi
[[ "$raw_wss_has_data" == true ]] || {
    echo "FieldConvert did not create the requested wing WSS field." >&2
    find "$temporary_dir" -maxdepth 1 -type f -printf '  %p\n' >&2 || true
    exit 1
}

# ProcessWSS in Nektar++ 5.10.0 can produce partition-dependent NaNs in MPI
# even when the source velocity is finite. Audit the raw Shear_* surface field
# before publishing it; the default one-rank path is the validated baseline.
if ! env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    -m printfldnorms "$surface_xml" "$raw_wss" "$wss_audit" \
    >"$wss_audit_log" 2>&1; then
    echo "FieldConvert could not audit the generated WSS field." >&2
    tail -n 40 -- "$wss_audit_log" >&2 || true
    exit 1
fi
if grep -Eqi ':[[:space:]]*[-+]?(nan|inf)([^[:alpha:]]|$)' "$wss_audit_log"; then
    echo "Rejected non-finite WSS output (requested ranks: $processes)." >&2
    echo "This Nektar++ release has shown partition-dependent MPI wss output;" >&2
    echo "rerun with --np 1 for the validated serial calculation." >&2
    grep -Ei 'error \(variable|:[[:space:]]*[-+]?(nan|inf)' \
        "$wss_audit_log" >&2 || true
    exit 1
fi
mv -f -- "$raw_wss" "$wss_fld"

# Boundary extraction is the second expensive volume operation, so use the
# requested MPI decomposition here too. The extract module retains u,v,w,p;
# reduce this to p only after the field is on the small Wing surface mesh.
env NEKTAR_FIELDCONVERT_NP="$processes" \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    -m "extract:bnd=${boundary_id}" \
    "$mesh_file" "$wall_session" "$field_file" "$pressure_request"

raw_pressure="$pressure_request"
if [[ ! -e "$raw_pressure" ]]; then
    raw_pressure="${pressure_request%.fld}_b${boundary_id}.fld"
fi
if [[ -f "$raw_pressure" ]]; then
    raw_pressure_has_data=false
    [[ -s "$raw_pressure" ]] && raw_pressure_has_data=true
elif [[ -d "$raw_pressure" ]]; then
    raw_pressure_has_data=false
    [[ -n "$(find "$raw_pressure" -type f -size +0c -print -quit)" ]] && \
        raw_pressure_has_data=true
else
    raw_pressure_has_data=false
fi
[[ "$raw_pressure_has_data" == true ]] || {
    echo "FieldConvert did not create the requested Wing pressure field." >&2
    exit 1
}

env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    -m removefield:fieldname=u \
    -m removefield:fieldname=v \
    -m removefield:fieldname=w \
    "$surface_xml" "$raw_pressure" "$pressure_fld"

if ! env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    -m printfldnorms "$surface_xml" "$pressure_fld" "$pressure_audit" \
    >"$pressure_audit_log" 2>&1; then
    echo "FieldConvert could not audit the extracted pressure field." >&2
    tail -n 40 -- "$pressure_audit_log" >&2 || true
    exit 1
fi
if grep -Eqi ':[[:space:]]*[-+]?(nan|inf)([^[:alpha:]]|$)' \
    "$pressure_audit_log"; then
    echo "Rejected non-finite pressure output (requested ranks: $processes)." >&2
    grep -Ei 'error \(variable|:[[:space:]]*[-+]?(nan|inf)' \
        "$pressure_audit_log" >&2 || true
    exit 1
fi

# Keep downstream format conversion serial. The surface exports are small and
# portable; only the preceding volume WSS/extract operations use MPI.
env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "$surface_xml" "$wss_fld" "$temporary_wss_csv"
env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "$surface_xml" "$wss_fld" "$wss_vtu:vtu:highorder"
env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "$surface_xml" "$pressure_fld" "$temporary_pressure_csv"
env NEKTAR_FIELDCONVERT_NP=1 \
    "$nektar_script_dir/fieldconvert_docker.sh" -f -v \
    "$surface_xml" "$pressure_fld" "$pressure_vtu:vtu:highorder"

# Validate the exact CSV contract consumed by plot_surface_fields.py before
# publishing either file. This catches malformed rows and non-finite values
# introduced during point interpolation, in addition to the FLD norm audits.
if ! python3 "$nektar_script_dir/plot_surface_fields.py" \
    "$temporary_wss_csv" "$temporary_pressure_csv" --validate-only; then
    echo "FieldConvert CSV output is not valid for chordwise plotting." >&2
    echo "Inspect the source mean field for non-finite Wing values." >&2
    exit 1
fi
mv -f -- "$temporary_wss_csv" "$wss_csv"
mv -f -- "$temporary_pressure_csv" "$pressure_csv"

[[ -s "$surface_xml" && -s "$wss_fld" && -s "$wss_csv" && -s "$wss_vtu" &&
    -s "$pressure_fld" && -s "$pressure_csv" && -s "$pressure_vtu" ]] || {
    echo "Wall-shear post-processing did not create its required outputs." >&2
    exit 1
}
printf 'Wing boundary ID : B[%s]\n' "$boundary_id"
printf 'Wing composite ID: C[%s]\n' "$surface_id"
printf 'WSS field        : %s\n' "$wss_fld"
printf 'WSS MPI ranks    : %s\n' "$processes"
printf 'Finite-norm audit: passed\n'
printf 'Fields           : Shear_x, Shear_y, Shear_z, Shear_mag\n'
printf 'Serial CSV       : %s\n' "$wss_csv"
printf 'Serial VTU       : %s\n' "$wss_vtu"
printf 'Pressure field   : %s\n' "$pressure_fld"
printf 'Pressure MPI ranks: %s\n' "$processes"
printf 'Pressure CSV     : %s (serial)\n' "$pressure_csv"
printf 'Pressure VTU     : %s (serial)\n' "$pressure_vtu"
