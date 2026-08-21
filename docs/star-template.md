# STAR simulation-template prerequisite

The headless STAR drivers currently configure and execute an existing
simulation; they do not yet import the STEP file into an empty simulation.
Consequently, a fresh clone needs one locally created `.sim` template.

The file is ignored because it is a version-specific STAR binary and can
contain site-specific state. Do not force-add it to Git.

## Validated template name

The periodic case expects:

```text
star/naca0012_periodic_template.sim
```

The location can be changed through `STAR_TEMPLATE` in `config/site.env`.

## Required object hierarchy

The validated default names are:

```text
Region
└── Fluid
    ├── Wing
    ├── Upstream
    ├── Downstream
    ├── FarfieldTop
    ├── FarfieldBottom
    ├── SpanMin
    └── SpanMax

Automated Mesh operation: NACA0012_AutomatedMesh
Wing surface control:     WingSurfaceControl
Volume control:           WingVolumeControl
Volume refinement part:   WingRefinement
Periodic interface:       SpanwisePeriodic
```

`WingVolumeControl` and its block part can be created by `ConfigureMesh.java`
when absent. The Automated Mesh operation and `WingSurfaceControl` must already
exist, because they hold the selected meshers and wing-surface membership.

The Automated Mesh operation must enable:

- Surface Remesher;
- Tetrahedral Mesher;
- Prism Layer Mesher.

The wing control must select the complete NACA wall. The batch configuration
then enforces one standard-cell macro prism layer and applies all numeric mesh
parameters supplied by the workflow driver.

## Periodic template requirement

For periodic RANS, `SpanMin` and `SpanMax` must belong to a translational
periodic interface named `SpanwisePeriodic`. The validated translation is
approximately `(0, 0, 0.2) m`, with imprinted connectivity and a conformal
match.

Both span surfaces must receive one-to-one meshes. The pipeline runs NekMesh
`peralign` as a linear-mesh preflight and stops before RANS or high-order
processing if their face counts/orderings do not match.

## Template checkpoint

Before saving the template, verify:

1. There is exactly one fluid region named `Fluid`.
2. The seven physical boundaries above have the expected faces.
3. Any residual `Default` boundary has zero faces.
4. The imported chord is `1 m` and span is `0.2 m`.
5. The surface/tet/prism meshers are enabled.
6. `WingSurfaceControl` selects only the NACA wall.
7. The periodic interface reports a conformal match.
8. No flow solution or generated mesh is required in the template.

Save the simulation and set the local site file:

```bash
cp config/site.env.example config/site.env
${EDITOR:-vi} config/site.env
```

For a non-periodic mesh-only run, the simpler default expected by
`run_star_mesh.sh` is `star/naca0012_mesh_template.sim`; it does not require the
periodic interface.

## Planned removal of this prerequisite

A future `scripts/star/BootstrapCase.java` should start from an empty
simulation, import `cad/naca0012_domain.step` with explicit millimetre units,
classify and name faces geometrically, create the region and mesh operations,
construct the periodic interface and save the template. That macro must be
validated in the pinned STAR release before this page can be marked obsolete.
