# STAR STEP-to-SIM bootstrap and manual fallback

The normal workflow generates the ignored STAR simulation from the tracked
CAD BRep:

```bash
./scripts/workflow/run_star_bootstrap.sh --force
```

`scripts/star/BootstrapCase.java` starts in a new empty simulation and creates:

```text
Geometry Part: naca0012_domain
Region: Fluid
Boundaries: Wing, Downstream, SpanMin, FarfieldTop,
            SpanMax, FarfieldBottom, Upstream
Automated Mesh: NACA0012_AutomatedMesh
Surface controls: WingSurfaceControl, NoPrismFarfieldControl
Periodic interface: SpanwisePeriodic
Periodic meshing contact: SpanMin <-> SpanMax, translational and mesh-only
```

The mesh operation enables the Surface Remesher, Tetrahedral Mesher and Prism
Layer Mesher. Prism generation is disabled on the six outer-domain surfaces;
the wing retains the parent prism settings later applied by
`ConfigureMesh.java`.

The canonical STEP may import as seven named part surfaces or as nine CAD
faces, with the upper, lower and blunt-trailing-edge faces separate. The macro
prefers the explicit STEP names and supports the generator's stable nine-face
ordering as a fallback. Any other topology is rejected instead of guessed.

The command creates:

```text
star/naca0012_periodic_template.sim
star/naca0012_bootstrap.log
star/naca0012_bootstrap.provenance.txt
```

Use `--no-periodic-span` for an ordinary pair of span boundaries. Use
`--dry-run` to validate paths and show the STAR command without requesting a
license. The input STEP declares millimetres; STAR imports it into its SI
simulation coordinates, so the expected chord and span are 1 m and 0.2 m.

The end-to-end driver performs this stage automatically when `STAR_STEP` is
non-empty in `config/site.env`:

```text
STAR_STEP=cad/naca0012_domain.step
STAR_TEMPLATE=star/naca0012_periodic_template.sim
```

Clear `STAR_STEP` to reuse a prepared template. This is useful with another
STAR release or while diagnosing a bootstrap API difference.

## Runtime checkpoint

The macro compiles against the STAR 20.04 API jars. A runtime test must also
reach the macro completion marker:

```text
STAR_BATCH_BOOTSTRAP_COMPLETE
```

Runtime construction from the tracked STEP has completed under STAR 20.04.
The bootstrap rejects a periodic template unless both the mesh-level contact
and region interface resolve a nonzero translation. The subsequent mesh log
must additionally report a conformal periodic contact; NekMesh `peralign` is
the independent downstream one-to-one check.

## Manual-template fallback

A manually prepared template must contain the same hierarchy and names shown
above. It must enable the three meshers, select the complete NACA wall in
`WingSurfaceControl`, and use an imprinted translational periodic interface for
`SpanMin`/`SpanMax`. A generated mesh or flow solution is not required.

Before use, check:

1. one fluid region and seven physical boundaries;
2. any residual `Default` boundary has zero faces;
3. chord 1 m and span 0.2 m;
4. one-to-one conformal periodic surfaces;
5. only the wing grows prisms.

The `.sim` is version-specific and can retain site state, so it remains ignored
and must not be force-added to Git.
