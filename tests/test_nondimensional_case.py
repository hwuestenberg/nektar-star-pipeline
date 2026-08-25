import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _case_values() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in (
        ROOT / "cases" / "naca0012-periodic" / "case.env"
    ).read_text().splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values


def _session_parameters() -> dict[str, str]:
    root = ET.parse(
        ROOT / "nektar" / "naca0012-periodic" / "session.xml"
    ).getroot()
    parameters: dict[str, str] = {}
    for parameter in root.findall("./CONDITIONS/PARAMETERS/P"):
        name, value = (item.strip() for item in parameter.text.split("=", 1))
        parameters[name] = value
    return parameters


def test_star_and_nektar_share_nondimensional_reynolds_convention():
    case = _case_values()
    session = _session_parameters()

    reynolds = float(case["RANS_REYNOLDS"])
    assert reynolds > 0.0
    assert float(session["Reynolds"]) == reynolds
    assert float(session["Uinf"]) == 1.0
    assert session["Kinvis"].replace(" ", "") == "1.0/Reynolds"
    assert abs((1.0 / reynolds) - 1.4607346947446909e-6) < 1.0e-20


def test_star_macro_derives_normalized_material_properties_from_reynolds():
    macro = (ROOT / "scripts" / "star" / "ConfigureRans.java").read_text()

    assert 'requiredDouble("STAR_RANS_REYNOLDS")' in macro
    assert "double velocity = 1.0;" in macro
    assert "double density = 1.0;" in macro
    assert "double viscosity = 1.0 / reynolds;" in macro
    assert "STAR_RANS_VELOCITY_MPS" not in macro
    assert "STAR_RANS_DENSITY_KGM3" not in macro
    assert "STAR_RANS_VISCOSITY_PAS" not in macro
