# Contributing

Contributions that improve portability, validation, documentation or support
for additional STAR-CCM+/Nektar++ versions are welcome.

## Before opening a change

For defects, identify the failing layer of the pipeline:

```text
CAD -> STAR import -> surface mesh -> prism/tet mesh -> CCM export
    -> NekMesh import -> CAD projection -> prism split -> optimisation
    -> RANS field transfer
```

Include the relevant software versions, command, first meaningful error and a
minimal reproducer where possible. Do not upload license credentials or files
whose redistribution is restricted.

## Development setup

Create a Python environment and install the checked development dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
```

Before submitting a change, run:

```bash
ruff check scripts tests
python -m compileall -q scripts tests
shfmt -d -i 4 -ci \
  execute.sh scripts/nektar/*.sh scripts/workflow/*.sh scripts/site/*.sh \
  tests/*.sh
./tests/test_cli.sh
pytest
```

STAR-CCM+ cannot run in the public GitHub Actions workflow. Changes to Java
macros or STAR object assumptions must therefore state:

- the exact STAR product/build used;
- whether the test was interactive or headless;
- the mesh/RANS command invoked;
- relevant completion markers and element counts;
- whether periodic matching and final Jacobian checks passed.

## Repository hygiene

Never commit:

- STAR Power-on-Demand keys or license configuration;
- machine-local `config/site.env` files;
- proprietary STAR installation files;
- `.sim` templates unless redistribution has been explicitly reviewed;
- generated CCM meshes, RANS tables, restart fields or large visualisation
  files.

Use the existing ignored output directories and retain small textual
validation summaries where they improve regression coverage.

## Licensing

Unless explicitly stated otherwise, contributions are accepted under the MIT
License in this repository. Third-party dependencies and tools retain their
own licenses and are not relicensed by this project.
