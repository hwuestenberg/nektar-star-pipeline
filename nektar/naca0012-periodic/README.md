# Nektar++ periodic restart validation

This directory contains the solver-side validation case for the generated
high-order mesh and STAR RANS restart. `session.xml` is adapted from a
semi-implicit incompressible setup, with case-specific history-point filters
removed.

The retained validation outputs are:

- `wing_forces.fce`, to expose force transients and boundary mistakes;
- `modal_energy.mdl`, to expose modal-energy growth or instability;
- `checkpoint_*.chk`, to verify checkpoint/restart output;
- per-step CFL and solver information in `solver.log`.

The default session uses P5 velocity, P4 pressure, IMEX order 2, the periodic
`SpanMin`/`SpanMax` pair, a no-slip wing, slip top/bottom boundaries, a fixed
inlet and a standard pressure-pinned outlet. Velocity starts from the generated
STAR restart; pressure starts from zero because the donor pressure is not the
Nektar++ pressure-correction variable.

STAR and Nektar++ share the nondimensional convention `U_inf=1`, `rho=1`, and
`c=1`. `run_nektar_solver.sh` reads `RANS_REYNOLDS` from the case configuration
and overrides the session's `Reynolds` parameter; the session evaluates
`Kinvis=1/Reynolds`. Use `--reynolds RE` only for an explicit override, and
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
