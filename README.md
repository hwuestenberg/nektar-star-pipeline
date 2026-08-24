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

The current source uses shared nondimensional flow scaling in STAR and
Nektar++: `U_inf=1`, `rho=1`, and `mu=nu=1/Re`. Regenerate the STAR donor and
restart after changing `RANS_REYNOLDS`; an older restart is not rescaled in
place.

STAR-CCM+ is commercial software and is not distributed by this repository.
The STAR Java API can change between versions, so other releases may require
small macro updates.

## STAR reproducibility boundary

The pipeline includes a STEP-to-SIM bootstrap macro. In a new STAR simulation
it imports the CAD BRep, creates the fluid region and named boundaries, selects
the surface/tetrahedral/prism meshers, creates the surface controls and, by
default, constructs the translational spanwise-periodic interface. The binary
`.sim` remains an ignored generated artifact.

The macro is API-compiled against STAR 20.04 and has completed remote runtime
construction from the tracked STEP. The fresh-template path creates both the
solver-level periodic interface and the mesh-only periodic part-surface
contact required for conformal spanwise remeshing. A prepared template remains
a documented fallback for other STAR releases. See
[STEP-to-SIM bootstrap and fallback](docs/star-template.md).

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

NekMesh, FieldConvert and IncNavierStokesSolver use one immutable,
digest-pinned full Nektar++ image for the latest stable release (`v5.10.0`),
defined in
`scripts/nektar/container_images.sh`.

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

After configuring the local STAR installation:

```bash
./execute.sh
```

`execute.sh` selects the lean production DAG. It reuses an existing validated
STAR template, overlaps STAR RANS with high-order mesh generation, retains one
final periodic/Jacobian gate, and omits diagnostic VTUs. Required NekMesh
module serialization uses private temporary XMLs which are removed on return.
If the configured template is absent, the first run bootstraps it from
`STAR_STEP`; later runs reuse it.

After producing the mesh and restart, `execute.sh` directly runs
`run_nektar_solver.sh` using the configured Reynolds number,
`NEKTAR_SOLVER_STEPS` and the single end-to-end `MPI_NP` rank count. The same
rank count is passed to STAR meshing, STAR RANS, the Nektar++ solver and the
parallel-capable surface post-processing operations. The solver driver then
computes
the mean Wing wall-shear vector and magnitude from the final
`mean_fields_avg.fld` produced by the `AverageFields` filter. Conversion
to skin-friction coefficient is deliberately left to downstream analysis. It
also extracts the mean Wing pressure into FLD, CSV and high-order VTU outputs.
The validated Nektar++ 5.10.0 WSS path is serial and performs an automatic
finite-norm audit before publishing the result; on the reference production
mesh this is a substantial, memory-intensive post-process. Use
`--no-wall-shear` for solver-only smoke tests.

For tutorial checkpoints and visual exports, invoke
`./execute.sh --diagnostic`, or add `--diagnostic` when invoking
`scripts/workflow/run_remote_pipeline.sh` directly. Every failed production
run prints this diagnostic rerun hint.

To discard all reproducible outputs before a clean run, preview and then
execute the generated-artifact cleanup:

```bash
./scripts/workflow/clean_generated.sh
./scripts/workflow/clean_generated.sh --execute
./execute.sh
```

The cleanup preserves the ignored local `config/site.env` and any untracked
non-ignored source files.

The portable case settings are in
`cases/naca0012-periodic/case.env`. Individual stages and all available
parameters are exposed through:

```bash
./scripts/workflow/run_remote_pipeline.sh --help
./scripts/workflow/run_star_bootstrap.sh --help
./scripts/workflow/run_star_mesh.sh --help
./scripts/workflow/run_star_rans.sh --help
./scripts/workflow/run_nektar_solver.sh --help
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
- [STAR STEP-to-SIM bootstrap and fallback](docs/star-template.md)
- [Validated periodic case](cases/naca0012-periodic/README.md)
- [Nektar++ restart validation case](nektar/naca0012-periodic/README.md)

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
