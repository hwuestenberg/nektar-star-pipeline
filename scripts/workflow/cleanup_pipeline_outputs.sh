#!/usr/bin/env bash
# Remove reproducible intermediate products for one completed pipeline case.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/../.." && pwd)"

case_name="naca0012"
execute=false

usage() {
    cat <<'EOF'
Usage: scripts/workflow/cleanup_pipeline_outputs.sh [options]

Keep only the final high-order mesh XML and RANS restart FLD for one completed
pipeline case.
The default is a dry run that prints every retained and removable file.

Options:
  --name NAME  Pipeline case name (default: naca0012)
  --execute    Delete the listed intermediate files
  -h, --help   Show this help

The script requires logs/NAME_pipeline.provenance.txt and uses its recorded
CAD order and boundary-layer count to identify the retained run inputs:

  nekmesh/NAME_pP_blN.xml
  nekmesh/NAME_rans_initial.fld

It preserves CAD, scripts and STAR templates. Generated CCM/SIM/RANS files,
diagnostic VTUs, quality reports, stage logs and intermediate NekMesh files
are removed. The retained XML supplies the final high-order geometry; the
retained FLD is the interpolated STAR RANS initial condition.
EOF
}

while (($#)); do
    case "$1" in
        --name)
            [[ $# -ge 2 ]] || {
                echo "--name requires a value" >&2
                exit 2
            }
            case_name="$2"
            shift 2
            ;;
        --execute)
            execute=true
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

if [[ ! "$case_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "--name contains unsupported characters: $case_name" >&2
    exit 2
fi

cd "$project_dir"
provenance="logs/${case_name}_pipeline.provenance.txt"
[[ -s "$provenance" ]] || {
    echo "Completed pipeline provenance is missing: $provenance" >&2
    exit 1
}

provenance_value() {
    local key="$1"
    awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' \
        "$provenance"
}

recorded_case="$(provenance_value case_name)"
cad_order="$(provenance_value cad_order)"
bl_layers="$(provenance_value bl_layers)"
ccm_file="$(provenance_value ccm_file)"

[[ "$recorded_case" == "$case_name" ]] || {
    echo "Provenance case mismatch: expected $case_name, found $recorded_case" >&2
    exit 1
}
[[ "$cad_order" =~ ^[0-9]+$ ]] || {
    echo "Invalid cad_order in $provenance: $cad_order" >&2
    exit 1
}
[[ "$bl_layers" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid bl_layers in $provenance: $bl_layers" >&2
    exit 1
}

projected_stem="${case_name}_p${cad_order}"
final_stem="${projected_stem}_bl${bl_layers}"
final_xml="nekmesh/${final_stem}.xml"
final_vtu="nekmesh/${final_stem}.vtu"
restart_fld="nekmesh/${case_name}_rans_initial.fld"

# Never delete anything unless both runtime inputs already exist. The final
# VTU is intentionally diagnostic and is not required by a Nektar++ run.
[[ -s "$final_xml" ]] || {
    echo "Final XML is missing or empty: $final_xml" >&2
    exit 1
}
[[ -s "$restart_fld" ]] || {
    echo "Restart FLD is missing or empty: $restart_fld" >&2
    exit 1
}

declare -a candidates=(
    "nekmesh/${case_name}_linear.xml"
    "nekmesh/${case_name}_linear.vtu"
    "nekmesh/${case_name}_linear_periodic_check.xml"
    "nekmesh/${projected_stem}.xml"
    "nekmesh/${projected_stem}.vtu"
    "$final_vtu"
    "nekmesh/${final_stem}_prealign.xml"
    "nekmesh/${final_stem}_periodic_oriented.xml"
    "nekmesh/${case_name}_rans_initial.vtu"
    "nekmesh/${case_name}_restart_session.xml"
    "logs/${case_name}_star_driver.log"
    "logs/${case_name}_linear_import.log"
    "logs/${case_name}_linear_fieldconvert.log"
    "logs/${projected_stem}_projectcad.log"
    "logs/${projected_stem}_jac.log"
    "logs/${projected_stem}_fieldconvert.log"
    "logs/${final_stem}_split.log"
    "logs/${final_stem}_jac.log"
    "logs/${final_stem}_fieldconvert.log"
    "logs/${final_stem}_projectcad_restore.log"
    "logs/${case_name}_peralign_preflight.log"
    "logs/${case_name}_peralign.log"
    "logs/${case_name}_rans_driver.log"
    "logs/${case_name}_rans_interpolation.log"
    "logs/${case_name}_restart_session.log"
    "logs/${case_name}_pipeline.driver.log"
    "logs/${case_name}_pipeline.pid"
    "logs/.${case_name}_peralign_preflight.log.swp"
    "$provenance"
    "star/${case_name}_meshed.sim"
    "star/${case_name}_linear.ccm"
    "star/${case_name}_star_batch.log"
    "star/${case_name}_linear.provenance.txt"
    "star/${case_name}_rans.sim"
    "star/${case_name}_rans_raw.csv"
    "star/${case_name}_rans_nektar.csv"
    "star/${case_name}_rans.log"
    "star/${case_name}_rans.provenance.txt"
)

# A --ccm-file override is an intermediate only when it is a case-owned file
# directly below star/. Never remove an arbitrary external/shared CCM input.
if [[ "$ccm_file" == "star/${case_name}_"*.ccm ]]; then
    candidates+=("$ccm_file")
fi

shopt -s nullglob
for quality_file in "nekmesh/${final_stem}_jac_under_"*.txt; do
    candidates+=("$quality_file")
done
for temporary_file in "nekmesh/.${case_name}_"*; do
    candidates+=("$temporary_file")
done
shopt -u nullglob

declare -A seen=()
declare -a removable=()
for candidate in "${candidates[@]}"; do
    [[ "$candidate" != "$final_xml" && "$candidate" != "$restart_fld" ]] || continue
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    [[ -z "${seen[$candidate]:-}" ]] || continue
    seen[$candidate]=1
    removable+=("$candidate")
done

printf 'KEEP   %10s  %s\n' "$(stat -c %s -- "$final_xml")" "$final_xml"
printf 'KEEP   %10s  %s\n' "$(stat -c %s -- "$restart_fld")" "$restart_fld"
for candidate in "${removable[@]}"; do
    printf 'REMOVE %10s  %s\n' "$(stat -c %s -- "$candidate")" "$candidate"
done

if [[ "$execute" != true ]]; then
    printf '\nDry run only: %d intermediate files would be removed.\n' "${#removable[@]}"
    printf 'Run again with --execute after reviewing this list.\n'
    exit 0
fi

for candidate in "${removable[@]}"; do
    rm -f -- "$candidate"
done

printf '\nRemoved %d intermediate files for %s.\n' \
    "${#removable[@]}" "$case_name"
printf 'Retained mesh XML  : %s\n' "$final_xml"
printf 'Retained restart FLD: %s\n' "$restart_fld"
