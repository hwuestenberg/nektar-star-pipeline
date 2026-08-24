from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_production_is_default_and_execute_forwards_diagnostics() -> None:
    execute = (ROOT / "execute.sh").read_text(encoding="utf-8")
    driver = (
        ROOT / "scripts" / "workflow" / "run_remote_pipeline.sh"
    ).read_text(encoding="utf-8")

    assert "production=true" in driver
    assert "--diagnostic" in driver
    assert '[[ -s "$STAR_TEMPLATE" ]]' in execute
    assert 'pipeline_args+=("$@")' in execute
    assert "pipeline completed. Run the Nektar++ simulation next" in execute
    assert "run_nektar_solver.sh --force" in execute
    assert 'NEKTAR_SOLVER_NP:-1' in execute


def test_production_failure_prints_diagnostic_rerun_hint() -> None:
    driver = ROOT / "scripts/workflow/run_remote_pipeline.sh"

    production = subprocess.run(
        [str(driver), "--not-a-real-option"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert production.returncode != 0
    assert "./execute.sh --diagnostic" in production.stderr

    diagnostic = subprocess.run(
        [str(driver), "--diagnostic", "--not-a-real-option"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert diagnostic.returncode != 0
    assert "./execute.sh --diagnostic" not in diagnostic.stderr


def test_production_driver_keeps_one_final_quality_and_periodic_gate() -> None:
    driver = (
        ROOT / "scripts" / "workflow" / "run_remote_pipeline.sh"
    ).read_text(encoding="utf-8")

    production_function = driver.split(
        "run_production_nektar_stage() {", maxsplit=1
    )[1].split("\n}", maxsplit=1)[0]
    assert production_function.count('"projectcad:file=') == 2
    assert '"bl:surf=' in production_function
    assert '"peralign:surf1=' in production_function
    assert '"jac:quality"' in production_function
    assert "fieldconvert_docker.sh" not in production_function


def test_velocity_only_restart_session(tmp_path: Path) -> None:
    source = tmp_path / "mesh.xml"
    output = tmp_path / "restart.xml"
    source.write_text(
        """<?xml version=\"1.0\"?>
<NEKTAR>
  <GEOMETRY DIM=\"3\" SPACE=\"3\"></GEOMETRY>
  <EXPANSIONS>
    <E COMPOSITE=\"C[0]\" NUMMODES=\"2\" TYPE=\"MODIFIED\" />
  </EXPANSIONS>
</NEKTAR>
""",
        encoding="utf-8",
    )

    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/nektar/prepare_nektar_restart_session.py"),
            str(source),
            str(output),
            "--num-modes",
            "5",
            "--fields",
            "u,v,w",
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    result = output.read_text(encoding="utf-8")
    assert 'FIELDS="u,v,w"' in result
    assert 'FIELDS="u,v,w,p"' not in result


def test_wall_shear_postprocess_publishes_native_shear_only() -> None:
    script = (
        ROOT / "scripts/workflow/postprocess_wall_shear.sh"
    ).read_text(encoding="utf-8")

    assert 'wss:bnd=${boundary_id}' in script
    assert 'extract:surf=${surface_id}' in script
    assert "-m printfldnorms" in script
    assert "Rejected non-finite WSS output" in script
    assert "fieldfromstring" not in script
    assert "Cf_" not in script
    assert 'extract:bnd=${boundary_id}' in script
    assert script.count('NEKTAR_FIELDCONVERT_NP="$processes"') == 2
    assert script.count("NEKTAR_FIELDCONVERT_NP=1") == 7
    assert '"$surface_xml" "$wss_fld" "$wss_csv"' in script
    assert '"$surface_xml" "$wss_fld" "$wss_vtu:vtu:highorder"' in script
    assert '"$surface_xml" "$pressure_fld" "$pressure_csv"' in script
    assert '"$surface_xml" "$pressure_fld" "$pressure_vtu:vtu:highorder"' in script

    runner = (
        ROOT / "scripts/workflow/run_nektar_solver.sh"
    ).read_text(encoding="utf-8")
    assert "wall_shear_processes=1" in runner
    assert "mean_fields_avg.fld" in runner
    assert '--field "$mean_field_path"' in runner
    assert "instantaneous_*.chk" in runner
    assert '--np "$wall_shear_processes"' in runner
