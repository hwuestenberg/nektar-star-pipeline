from __future__ import annotations

import ast
import math
import subprocess
import sys
from pathlib import Path

import pytest

from scripts.cad.create_naca0012_domain import (
    TRAILING_EDGE_COEFFICIENT,
    naca_half_thickness,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CAD_SCRIPT = REPOSITORY_ROOT / "scripts/cad/create_naca0012_domain.py"


def test_profile_endpoints_and_blunt_trailing_edge() -> None:
    chord = 1.0
    thickness = 0.12

    assert naca_half_thickness(0.0, chord, thickness) == 0.0
    expected_half_thickness = (
        5.0
        * thickness
        * chord
        * (0.2969 - 0.1260 - 0.3516 + 0.2843 + TRAILING_EDGE_COEFFICIENT)
    )
    assert naca_half_thickness(1.0, chord, thickness) == pytest.approx(
        expected_half_thickness
    )
    assert 2.0 * expected_half_thickness == pytest.approx(0.00252)


def test_cosine_spacing_clusters_points_at_leading_edge() -> None:
    point_count = 161
    uniform_first_interval = 1.0 / (point_count - 1)
    theta = math.pi / (point_count - 1)
    cosine_first_interval = 0.5 * (1.0 - math.cos(theta))

    assert cosine_first_interval < uniform_first_interval / 10.0


def test_step_generation_and_topology_validation(tmp_path: Path) -> None:
    output = tmp_path / "naca0012_domain.step"
    completed = subprocess.run(
        [
            sys.executable,
            str(CAD_SCRIPT),
            "--output",
            str(output),
        ],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    assert output.stat().st_size > 100_000
    assert "Validated STEP fluid domain" in completed.stdout
    assert "Entities [0D,1D,2D,3D] : [14, 21, 9, 1]" in completed.stdout
    bounding_box_line = next(
        line
        for line in completed.stdout.splitlines()
        if line.startswith("Bounding box")
    )
    bounding_box = ast.literal_eval(bounding_box_line.split(":", maxsplit=1)[1].strip())
    assert bounding_box == pytest.approx(
        (-5000.0, -5000.0, 0.0, 10000.0, 5000.0, 200.0)
    )
    assert "SI_UNIT(.MILLI.,.METRE.)" in output.read_text(
        encoding="utf-8", errors="replace"
    )
