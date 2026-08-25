import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEKTAR_SCRIPTS = ROOT / "scripts" / "nektar"


def test_all_nektar_wrappers_use_one_full_image():
    config = (NEKTAR_SCRIPTS / "container_images.sh").read_text()
    release = re.search(
        r'^NEKTAR_RELEASE_DEFAULT="([^"]+)"$', config, re.MULTILINE
    )
    match = re.search(r'^NEKTAR_IMAGE_DEFAULT="([^"]+)"$', config, re.MULTILINE)

    assert release is not None
    assert release.group(1) == "v5.10.0"
    assert match is not None
    assert match.group(1) == (
        "nektarpp/nektar@sha256:"
        "2ae26f90b902742b7b2a7e6c9a18542b171e654a26f54b9944ab636d24da3748"
    )

    for name in (
        "nekmesh_docker.sh",
        "fieldconvert_docker.sh",
        "incnavierstokes_docker.sh",
    ):
        wrapper = (NEKTAR_SCRIPTS / name).read_text()
        assert '${NEKTAR_CONTAINER_IMAGE:-$NEKTAR_IMAGE_DEFAULT}' in wrapper


def test_component_specific_image_configuration_was_removed():
    files = [
        ROOT / "execute.sh",
        ROOT / "config" / "site.env.example",
        ROOT / "scripts" / "workflow" / "run_remote_pipeline.sh",
        *(NEKTAR_SCRIPTS / name for name in (
            "container_images.sh",
            "nekmesh_docker.sh",
            "fieldconvert_docker.sh",
            "incnavierstokes_docker.sh",
        )),
    ]
    forbidden = (
        "NEKMESH_CONTAINER_IMAGE",
        "FIELDCONVERT_CONTAINER_IMAGE",
        "NEKTAR_SOLVER_CONTAINER_IMAGE",
        "NEKMESH_IMAGE_DEFAULT",
        "FIELDCONVERT_IMAGE_DEFAULT",
        "NEKTAR_SOLVER_IMAGE_DEFAULT",
    )

    combined = "\n".join(path.read_text() for path in files)
    for name in forbidden:
        assert name not in combined
