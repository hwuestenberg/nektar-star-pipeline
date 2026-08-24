# Periodic NACA0012 tutorial case

`case.env` contains the portable parameters for the currently validated case:
order-4 CAD projection, eight split prism layers with ratio 1.2, and a periodic
spanwise RANS donor calculation.

Create the local site configuration before running the case:

```bash
cp config/site.env.example config/site.env
${EDITOR:-vi} config/site.env
./execute.sh
```

The numerical composite identifiers in `case.env` match the scripted
STEP-to-SIM bootstrap (`SpanMin=C[6]`, `SpanMax=C[8]`, `Wing=C[4]`). A GUI
prepared template may export another ordering and must override these values.
The pipeline's periodic preflight must pass before the span identifiers are
accepted.

By default `STAR_STEP` in the site configuration makes the pipeline generate
the ignored STAR `.sim` template directly from the tracked STEP file. Clear
`STAR_STEP` to use an existing prepared template instead. The bootstrap macro
has been API-compiled and run under STAR 20.04. It creates the mesh-only
periodic part-surface contact as well as the region interface so the
parts-based remesher can generate a one-to-one span pair.
Generic imported CAD surfaces are classified from their coordinate bounds,
not STAR object order, and every remaining airfoil face is merged into `Wing`.

`RANS_REYNOLDS` is the single flow-scale parameter shared by the STAR donor
and Nektar++ case. The STAR scripts enforce `U_inf=1`, `rho=1`, and `c=1`, then
set dynamic viscosity to `1/RANS_REYNOLDS`; the Nektar runner reads the same
case parameter and sets `Kinvis=1/RANS_REYNOLDS`. A newly generated restart
therefore needs no velocity rescaling before Nektar++ reads it.

`RANS_ALLOW_UNCONVERGED=true` accepts the exported RANS donor field when the
maximum-iteration cap is reached. This case deliberately uses that mode
because its single thick STAR prism is designed for NekMesh splitting, not as
a production RANS boundary layer. Set it to `false` when residual convergence
is a required acceptance condition.
