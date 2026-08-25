# Nektar++ periodic restart validation

This directory contains the solver-side validation case for the generated
high-order mesh and STAR RANS restart. `session.xml` is adapted from a
semi-implicit incompressible setup, with case-specific history-point filters
removed.

The retained validation outputs are:

- `wing_forces.fce`, to expose force transients and boundary mistakes;
- `modal_energy.mdl`, to expose modal-energy growth or instability;
- `instantaneous_*.chk`, to verify checkpoint/restart output;
- per-step CFL and solver information in `solver.log`.

The default session uses P5 velocity, P4 pressure, IMEX order 2, the periodic
`SpanMin`/`SpanMax` pair, a no-slip wing, slip top/bottom boundaries, a fixed
inlet and a standard pressure-pinned outlet. Velocity starts from the generated
STAR restart; pressure starts from zero because the donor pressure is not the
Nektar++ pressure-correction variable.

STAR and Nektar++ share the nondimensional convention `U_inf=1`, `rho=1`, and
`c=1`. `run_nektar_solver.sh` reads `RANS_REYNOLDS` from the case configuration
and materializes it, together with `NumSteps`, directly into
`RUN_DIR/session.xml`; the session evaluates `Kinvis=1/Reynolds` from that
concrete value. This is a real, self-contained copy rather than a solver `-P`
command-line override, so `RUN_DIR/session.xml` alone is a reproducible record
of exactly what ran, and `run_nektar_postprocess.sh` reads it directly with no
separate override. Use `--reynolds RE` only for an explicit override, and
regenerate the STAR restart at the same Reynolds number.

Run 100 steps with, for example:

```bash
./scripts/workflow/run_nektar_solver.sh --force --steps 100 --np 16
```

The runner stages links under `nektar/naca0012-periodic/run/`, invokes the
digest-pinned Nektar++ container and fails immediately on non-finite linear
solver output, exceeded iteration caps, PETSc errors or a fatal signal. It
also terminates the complete solver process group on interruption.

## Current solver checkpoint

The restart path has been loaded and advanced through 100 steps on 32 MPI
ranks. That structural validation used the preceding donor scaling; rerun the
full STAR transfer before claiming the new `U=1` normalization as exercised.
A 48-rank decomposition failed in the first pressure solve, so 32 ranks is the
currently validated decomposition for this tutorial mesh.

## Wing skin friction

Wall-shear and pressure post-processing is a separate stage from the solver
run, in `scripts/workflow/run_nektar_postprocess.sh`. Run it after the solver
passes its force, modal-energy, checkpoint and averaged-field checks:

```bash
./scripts/workflow/run_nektar_postprocess.sh --force
```

Its defaults already point at this run directory's mesh, materialized
session and `mean_fields_avg.fld`, so no arguments are required after a
standard `run_nektar_solver.sh` run; `execute.sh` invokes it the same way
with explicit paths. It post-processes the final `mean_fields_avg.fld` from
the `AverageFields` filter on Wing (`B[0]`, `C[4]`) with FieldConvert's `wss`
module. It writes:

```text
run/wing_surface.xml
run/mean_fields_wss.fld
run/mean_fields_wss.csv
run/mean_fields_wss.vtu
run/mean_fields_pressure.fld
run/mean_fields_pressure.csv
run/mean_fields_pressure.vtu
```

The surface field contains the native `wss` output: `Shear_x`, `Shear_y`,
`Shear_z` and `Shear_mag`. Skin-friction normalization is deliberately left to
downstream analysis. A parallel `extract:bnd=0` also extracts the Wing
boundary from `mean_fields_avg.fld`; the published pressure field retains only
`p`. The expensive `wss` and `extract` modules use the requested MPI rank
count. Their finite audits, pressure field selection, and all CSV/high-order-
VTU exports run on one rank. Run `run_nektar_postprocess.sh` with different
`--field`/`--prefix`/`--output-dir` arguments to post-process another
field/checkpoint. The expensive volume-field reconstruction in `wss` is
serial by default: Nektar++ 5.10.0 produced partition-dependent non-finite
boundary values in MPI for this hybrid mesh. A finite-norm audit prevents such
fields from being published. `--np N` is available for retesting a newer
image, but `N=1` is the validated setting. The extracted surface field is
written as one portable `.fld`.

Plot the native mean shear magnitude and pressure against chordwise position
with:

```bash
python3 scripts/nektar/plot_surface_fields.py \
  nektar/naca0012-periodic/run/mean_fields_wss.csv \
  nektar/naca0012-periodic/run/mean_fields_pressure.csv
```

This writes separate `mean_fields_wss.png` and `mean_fields_pressure.png`
figures beside the CSV files. Upper and lower surfaces are shown separately;
repeated points at each `x/c` station are averaged only in the spanwise
direction. Use `--chord` and `--leading-edge-x` for geometry whose chord does
not run from `x=0` to `x=1`.
