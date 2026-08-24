from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/nektar/plot_surface_fields.py"


def test_plot_surface_fields(tmp_path: Path) -> None:
    wss = tmp_path / "mean_fields_wss.csv"
    pressure = tmp_path / "mean_fields_pressure.csv"
    wss.write_text(
        "# x,y,z,Shear_x,Shear_y,Shear_z,Shear_mag\n"
        "0.0,0.0,0.0,0,0,0,0.2\n"
        "0.5,0.05,0.0,0,0,0,0.1\n"
        "0.5,0.05,0.2,0,0,0,0.3\n"
        "0.5,-0.05,0.0,0,0,0,0.15\n"
        "1.0,-0.001,0.0,0,0,0,0.05\n",
        encoding="utf-8",
    )
    pressure.write_text(
        "# x,y,z,p\n"
        "0.0,0.0,0.0,0.5\n"
        "0.5,0.05,0.0,-0.1\n"
        "0.5,0.05,0.2,-0.3\n"
        "0.5,-0.05,0.0,0.1\n"
        "1.0,-0.001,0.0,0.0\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCRIPT), str(wss), str(pressure)],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    assert (tmp_path / "mean_fields_wss.png").stat().st_size > 0
    assert (tmp_path / "mean_fields_pressure.png").stat().st_size > 0
    assert "Shear plot" in result.stdout
    assert "Pressure plot" in result.stdout


def test_plot_surface_fields_rejects_missing_field(tmp_path: Path) -> None:
    wss = tmp_path / "wss.csv"
    pressure = tmp_path / "pressure.csv"
    wss.write_text("# x,y,z,Shear_x\n0,0,0,1\n", encoding="utf-8")
    pressure.write_text("# x,y,z,p\n0,0,0,1\n", encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(SCRIPT), str(wss), str(pressure)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "shear_mag" in result.stderr.lower()
