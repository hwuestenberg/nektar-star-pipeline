# STAR-CCM+ to NekMesh external-aerodynamics tutorial

[![non-STAR validation](https://github.com/hwuestenberg/nektar-star-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/hwuestenberg/nektar-star-pipeline/actions/workflows/ci.yml)

This repository builds a linear hybrid mesh in STAR-CCM+ and converts it into
a curved high-order Nektar++ mesh:

```text
STEP fluid domain
  -> STAR-CCM+ tetrahedra + one macro prism layer
  -> CCM
  -> NekMesh CAD projection
  -> high-order prism-layer splitting
  -> optional periodic alignment
  -> optional STAR RANS restart field
```

The reference case is a genuinely three-dimensional, spanwise-extruded
NACA0012 section. The STAR mesh is a linear handoff mesh, not the final
high-order boundary-layer discretisation.

## Status

The following configuration has been exercised end to end:

- Simcenter STAR-CCM+ 2506, build 20.04.007;
- linear tetrahedra with one standard macro prism layer;
- NekMesh polynomial order 4;
- eight split prism layers with outward ratio 1.2;
- translational spanwise periodicity;
- zero negative final Jacobians in the validated run;
- STAR steady SST donor data interpolated into a Nektar++ restart field.

STAR-CCM+ is commercial software and is not distributed by this repository.
The STAR Java API can change between versions, so other releases may require
small macro updates.

## Current reproducibility boundary

CAD generation and every post-STAR stage are scripted. The pipeline currently
requires a locally prepared STAR simulation template containing the imported
geometry, named boundaries, Automated Mesh operation and periodic interface.
The binary `.sim` file is deliberately ignored.

See [the STAR template prerequisite](docs/star-template.md) before attempting a
fresh run. A future STEP-to-template bootstrap macro will remove this remaining
manual checkpoint.

## Repository layout

```text
cad/                         Reference STEP fluid domain
cases/naca0012-periodic/     Portable validated case parameters
config/                      Local site-configuration example
docs/                        Detailed tutorial and prerequisites
scripts/cad/                 CAD generation and validation
scripts/star/                STAR-CCM+ Java macros
scripts/nektar/              NekMesh, FieldConvert and restart tools
scripts/workflow/            Pipeline and individual-stage drivers
scripts/site/                Optional site-specific helpers
star/, nekmesh/, logs/       Ignored generated data
work/, results/              Reserved ignored run/output directories
```

## Prerequisites

- Python 3 and the Gmsh Python module with OpenCASCADE support;
- a licensed STAR-CCM+ installation compatible with the Java macros;
- Docker or Apptainer;
- SSH and rsync only when using the optional remote-host helpers.

NekMesh and FieldConvert use immutable, digest-pinned Nektar++ container
images defined in `scripts/nektar/container_images.sh`.

## Generate and validate the CAD

```bash
python3 scripts/cad/create_naca0012_domain.py
```

The generator writes `cad/naca0012_domain.step`, reimports it and validates its
units, bounding box, solid count, manifold boundary and expected wing faces.
All command-line dimensions are expressed in metres; the STEP BRep explicitly
stores millimetre units.

## Configure a site

```bash
cp config/site.env.example config/site.env
${EDITOR:-vi} config/site.env
```

`config/site.env` is ignored by Git and by the sync helpers. It contains only
machine-specific paths, process counts, container runtime and license mode.
Never store a Power-on-Demand key in it. When that mode is selected,
`execute.sh` prompts without echoing and only supplies the key to STAR's
subprocess environment.

The optional remote helpers use `REMOTE_HOST` and `REMOTE_DIR` from the same
file. `STAR_EXECUTABLE` and `APPTAINER_EXECUTABLE` may be command names resolved
through `PATH` or explicit paths supplied by the user; the repository contains
no site installation paths.

## Run the validated case

After supplying the required local STAR template:

```bash
./execute.sh
```

The portable case settings are in
`cases/naca0012-periodic/case.env`. Individual stages and all available
parameters are exposed through:

```bash
./scripts/workflow/run_remote_pipeline.sh --help
./scripts/workflow/run_star_mesh.sh --help
./scripts/workflow/run_star_rans.sh --help
```

The final Nektar++ inputs are:

```text
nekmesh/naca0012_periodic_full_p4_bl8.xml
nekmesh/naca0012_periodic_full_rans_initial.fld
```

Use the cleanup driver only after a successful pipeline; it verifies both
final files before offering to remove intermediates:

```bash
./scripts/workflow/cleanup_pipeline_outputs.sh \
  --name naca0012_periodic_full
```

The default is a preview. Add `--execute` only after checking the list.

## Documentation

- [Full staged tutorial](docs/tutorial.md)
- [STAR template prerequisite](docs/star-template.md)
- [Validated periodic case](cases/naca0012-periodic/README.md)

The long-form tutorial records the GUI checkpoints, unit conventions,
parameter meanings, periodic workflow, RANS transfer and troubleshooting
observed during development.

## Contributing and citation

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) for the
non-STAR validation commands and repository-hygiene requirements. Citation
metadata for research use is provided in [CITATION.cff](CITATION.cff).

This project's original material is available under the [MIT License](LICENSE).
STAR-CCM+, Nektar++, Gmsh, container images and other dependencies retain their
own licenses and are not distributed or relicensed by this repository.
