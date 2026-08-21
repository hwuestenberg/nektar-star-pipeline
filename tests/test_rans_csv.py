from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import pytest

from scripts.nektar.normalize_star_rans_csv import canonical_header, find_column

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
NORMALIZER = REPOSITORY_ROOT / "scripts/nektar/normalize_star_rans_csv.py"


def test_header_normalization_and_ambiguity_detection() -> None:
    assert canonical_header('"Static Pressure [Pa]"') == "staticpressurepa"
    assert find_column(["X Coordinate [m]", "Y Coordinate [m]"], "x", None) == 0
    with pytest.raises(ValueError, match="could not identify one 'x' column"):
        find_column(["X [m]", "X Coordinate [m]"], "x", None)


def test_zero_mean_pressure_conversion(tmp_path: Path) -> None:
    raw = tmp_path / "star.csv"
    normalized = tmp_path / "nektar.csv"
    raw.write_text(
        "STAR XyzInternalTable export\n"
        "X [m],Y [m],Z [m],Velocity Component X [m/s],"
        "Velocity Component Y [m/s],Velocity Component Z [m/s],"
        "Static Pressure [Pa]\n"
        "0,0,0,10,0,0,101\n"
        "1,0,0,9,1,0,99\n",
        encoding="utf-8",
    )

    completed = subprocess.run(
        [
            sys.executable,
            str(NORMALIZER),
            str(raw),
            str(normalized),
            "--pressure-mode",
            "zero-mean",
        ],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    with normalized.open(encoding="utf-8") as stream:
        assert stream.readline().strip() == "# x,y,z,u,v,w,p"
        rows = [[float(value) for value in row] for row in csv.reader(stream)]

    assert rows == [
        [0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 1.0],
        [1.0, 0.0, 0.0, 9.0, 1.0, 0.0, -1.0],
    ]
    assert "Pressure offset (Pa)   : 100" in completed.stdout
