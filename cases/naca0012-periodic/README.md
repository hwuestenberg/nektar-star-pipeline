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

The numerical composite identifiers in `case.env` are validated for the
current geometry and STAR boundary ordering. The pipeline's periodic preflight
must pass before these identifiers are accepted.

The STAR `.sim` template is still a local prerequisite. It is intentionally
not version-controlled; replacing it with a STEP-to-template bootstrap macro is
the next reproducibility task.
