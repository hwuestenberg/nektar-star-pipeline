# Full NACA0012 STAR-CCM+ to NekMesh tutorial

For the concise project overview and current reproducibility boundary, see the
[repository README](../README.md). STEP-to-SIM generation and the manual STAR
fallback are described in [star-template.md](star-template.md).

This directory holds the reproducible tutorial pipeline:

```text
CAD -> STAR-CCM+ linear tetrahedra/prisms -> CCM -> NekMesh -> Nektar++
```

The complete linear import, P4 CAD projection, macro-prism split and
high-order validation pipeline has passed its checkpoints. Generated meshes
and logs are intentionally disposable. The source CAD and scripts are tracked;
the generated STAR template remains an ignored, version-specific artifact.

## Directory layout

```text
cad/                         Generated CAD and geometry checkpoint files
cases/naca0012-periodic/     Version-controlled case parameters
config/                      Site configuration example; local file ignored
scripts/cad/                 Reproducible OpenCASCADE CAD generation
scripts/star/                STAR-CCM+ Java macros
scripts/nektar/              NekMesh/FieldConvert container and restart tools
scripts/workflow/            End-to-end and individual-stage drivers
scripts/site/                Optional site-specific launch/sync helpers
star/                        Ignored STAR simulations and linear CCM meshes
nekmesh/                     Ignored NekMesh meshes and diagnostic exports
logs/                        Ignored pipeline logs and provenance
```

For a fresh remote run, the non-generated inputs are:

```text
README.md
cad/naca0012_domain.step
cases/naca0012-periodic/case.env
config/site.env
scripts/
```

Create `config/site.env` from `config/site.env.example`; it is deliberately
not tracked or transferred by the site-sync helpers. The `.sim` output is also
local and ignored. See `cases/naca0012-periodic/README.md` for the current case
entry point.

The pipeline recreates the contents of `logs/` and `nekmesh/`, along with the
meshed `.sim`, linear `.ccm`, provenance and STAR log files under `star/`.
Never store the Power-on-Demand key in this tree; enter it into a temporary
shell variable as shown below.

## Installed CAD route

FreeCAD, CadQuery and PythonOCC are not installed. The available Gmsh 4.13.1
build includes OpenCASCADE 7.7.2, so the CAD script uses Gmsh's OpenCASCADE
kernel to write a proper STEP BRep. It does not create or convert an STL.

Confirm the Python environment with:

```bash
python3 -c 'import gmsh; print(gmsh.__version__)'
gmsh -info
```

## Generate the CAD

From this directory, run:

```bash
python3 scripts/cad/create_naca0012_domain.py
```

The default output is:

```text
cad/naca0012_domain.step
```

All command-line dimensions are expressed in metres:

```bash
python3 scripts/cad/create_naca0012_domain.py \
  --chord-m 1.0 \
  --span-m 0.2 \
  --upstream-m 5.0 \
  --downstream-m 10.0 \
  --vertical-extent-m 5.0 \
  --profile-points 161 \
  --thickness 0.12 \
  --output cad/naca0012_domain.step
```

The airfoil extends from `x=0` to `x=1 m`; `--downstream-m` is the outer
domain's positive x coordinate, not the distance measured from the trailing
edge.

## Trailing-edge choice

The script uses the requested NACA coefficient `-0.1015`. It gives a finite
trailing-edge thickness of `0.00252c`, or `2.52 mm` for the default chord. The
upper and lower spline faces are joined by one intentional planar trailing-edge
face. This is more robust for the initial CAD/STAR/NekMesh exercise than forcing
a zero-angle sharp closure. It also makes an accidental trailing-edge sliver
easy to distinguish from the intended topology.

## Units

The public script parameters use metres, but the OpenCASCADE model is built in
millimetres. The STEP file explicitly contains:

```text
SI_UNIT(.MILLI.,.METRE.)
```

The default STEP coordinates therefore use `c=1000 mm`. At the later STAR
import, select **millimetres** as the CAD import unit. STAR should then show a
physical chord of `1 m`, and the exported CCM mesh should use metre-scale
coordinates.

The locally inspected NekMesh OpenCASCADE backend converts STEP millimetres to
metres internally. Supplying this same STEP file to `projectcad` should
therefore coincide with the metre-scale CCM mesh without an additional scale
factor.

## Numerical checkpoint

The generator re-imports its own STEP and stops with an error unless it finds:

- one fluid solid with no orphaned construction entities;
- exactly 14 vertices, 21 curves, nine faces and one volume;
- nine faces and a closed manifold boundary shell;
- a bounding box of `[-5000,10000] x [-5000,5000] x [0,200] mm`;
- two span faces containing airfoil-shaped holes;
- three wing faces: upper, lower and the deliberate blunt trailing edge;
- a positive airfoil subtraction volume consistent with the analytical NACA
  section area;
- a `504 mm^2` trailing-edge face.

Gmsh's STEP writer does not retain its model entity names as per-face STEP
labels. The validation table printed by the script identifies faces by their
geometry; the corresponding STAR Part Surfaces will be renamed manually at the
next checkpoint.

## Visual checkpoint

Open the STEP in Gmsh:

```bash
gmsh cad/naca0012_domain.step
```

In the GUI:

1. Show geometry surfaces and curves.
2. Rotate the model and confirm the `15 m x 10 m x 0.2 m` outer box proportions.
3. Use **Tools -> Visibility** (the exact label varies slightly by Gmsh build)
   to hide one `z=constant` span face, or use a clipping plane.
4. Confirm that the NACA section is a through-hole in one fluid solid, not an
   isolated wing solid.
5. Inspect the smooth leading edge and the short, deliberate planar face at the
   trailing edge. There should be no duplicate or additional tiny faces.

Stop here and record the numerical summary and visual result before importing
the STEP into STAR-CCM+.

## Sync to the remote STAR-CCM+ host

Configure the SSH target and remote working directory in the ignored site file:

```bash
cp config/site.env.example config/site.env
${EDITOR:-vi} config/site.env
```

`REMOTE_HOST` may be an SSH alias, hostname, or `user@hostname` target.
`REMOTE_DIR` is relative to the remote home directory. Preview the upload from
the tutorial root:

```bash
./scripts/site/sync_to_remote.sh
```

The preview contacts the host but does not transfer files. When the displayed
source and destination are correct, execute it with:

```bash
./scripts/site/sync_to_remote.sh --execute
```

The default destination is:

```text
~/nektar-star-pipeline/
```

Override it when needed without editing the script:

```bash
./scripts/site/sync_to_remote.sh \
  --remote-dir work/meshing/nektar-star-pipeline \
  --execute
```

Uploads omit `.git`, Python caches, STAR `.sim`/`.ccm` files and generated
NekMesh outputs. The script never uses `rsync --delete`, so running it again
will not remove STAR work generated remotely.

## Reproducible headless STAR mesh generation

STAR-CCM+ 20.04 uses Java macros for in-process scripting.
`scripts/star/BootstrapCase.java` creates the named geometry part, region,
boundaries, Automated Mesh operation, controls and periodic interface in a new
simulation. `scripts/star/ConfigureMesh.java` then applies explicit numeric
mesh settings, and `scripts/star/ExportCcm.java` performs the mesh-only CCM
export.

Bootstrap the template directly from STEP:

```bash
./scripts/workflow/run_star_bootstrap.sh --force
```

This stage is also selected automatically by the full pipeline when
`STAR_STEP` is non-empty in `config/site.env`. The API compiles against STAR
20.04 and the tracked STEP has completed the bootstrap at runtime. Keep the
manual template path below as a fallback for other STAR releases or for
diagnosing site-specific import behavior.

For the manual fallback, save the successfully configured simulation as:

```text
star/naca0012_mesh_template.sim
```

The template may contain the existing mesh. STAR's batch `mesh` command will
execute any out-of-date mesh operations; clearing the generated mesh before
saving the template makes a forced rebuild explicit but is not required.

After synchronising the scripts, run on the remote host:

```bash
cd ~/nektar-star-pipeline
./scripts/workflow/run_star_mesh.sh
```

The canonical CCM file already exists after the interactive tutorial, so use
the deliberately explicit replacement option when you are ready to regenerate
it:

```bash
./scripts/workflow/run_star_mesh.sh --force
```

The default is one STAR process, which is appropriate for this 42,100-cell
tutorial and avoids adding parallel decomposition variability. A larger case
can use, for example:

```bash
./scripts/workflow/run_star_mesh.sh --np 8
```

The command produces:

```text
star/naca0012_meshed.sim
star/naca0012_linear.ccm
star/naca0012_star_batch.log
star/naca0012_linear.provenance.txt
```

The input template is never opened in place. The script copies it into a
private staging directory, invokes STAR with the equivalent of:

```bash
starccm+ -np 1 \
  -batch "scripts/star/ConfigureMesh.java,mesh,scripts/star/ExportCcm.java" \
  staged_naca0012_mesh_template.sim
```

and publishes the SIM and CCM outputs only after STAR returns success, the CCM
file is non-empty, and the macro's completion marker is present in the log.
Existing outputs are protected unless `--force` is supplied. Run:

```bash
./scripts/workflow/run_star_mesh.sh --help
```

for path overrides, a command-only dry run and additional STAR launcher
options. The provenance file records STAR's version, the exact command and
SHA-256 hashes of the template, both macros, generated simulation and CCM
mesh. It also records every numeric mesh parameter.

If STAR reports that it cannot obtain a `ccmpsuite` license, close any
interactive STAR session that is holding the available seat or wait for a seat
to become available. Sites with DOE-token preprocessing licenses can instead
pass STAR's supported launcher option after `--`:

```bash
./scripts/workflow/run_star_mesh.sh --force -- -powerpre
```

Do not select `-powerpre` unless that is the intended licensing mode at the
site; it requests ten `DOEtoken` licenses.

For a Power-on-Demand license, do not put the key directly in the command line:
the shell history, process list, STAR output and provenance could expose it.
Read it without echoing and let the wrapper supply it to STAR through the
supported `LM_PROJECT` environment variable:

```bash
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" \
  ./scripts/workflow/run_star_mesh.sh --force --power-on-demand
unset star_pod_key
```

The wrapper adds `-power` but records only `license_mode=power-on-demand`; it
does not print or write the value of `STAR_POD_KEY`.

The maintained export macro is `scripts/star/ExportCcm.java`; it uses
environment variables supplied by the wrapper instead of embedding a remote
home path.

## Headless STAR RANS precursor

The automated workflow can now continue from a generated STAR mesh to a
steady, constant-density SST k-omega solution. This is a separate stage from
the mesh-only CCM export:

```text
STAR mesh ---------------------------> mesh-only CCM -> NekMesh
    |
    +-> steady SST RANS -> x,y,z,u,v,w[,p] samples --> FieldConvert -> .fld
```

Keeping the two outputs separate is intentional. NekMesh reads CCM here as a
linear mesh source; the RANS solution is transferred independently as scattered
point data onto the final curved/split Nektar++ expansion.

The STAR stage is implemented by:

```text
scripts/workflow/run_star_rans.sh
scripts/star/ConfigureRans.java
scripts/star/ExportRansTable.java
scripts/nektar/normalize_star_rans_csv.py
```

`ConfigureRans.java` creates or reuses a continuum named `RANS_SST` and enables:

- three-dimensional, steady, segregated flow;
- single-component gas with constant density and viscosity;
- RANS turbulence, SST k-omega and all-y+ wall treatment.

For the present zero-incidence tutorial it assigns `Wing` as a no-slip wall,
`Upstream`, `FarfieldTop` and `FarfieldBottom` as velocity inlets, and
`Downstream` as a pressure outlet. The default span mode assigns
`SpanMin`/`SpanMax` as symmetries. With `--span-mode periodic`, the macro leaves
those boundaries under the periodic interface already defined in the input
STAR template. At nonzero incidence, revisit the top/bottom farfield treatment
rather than assuming that tangential velocity inlets are still the best
external-boundary choice.

Run the RANS stage independently after mesh generation with:

```bash
./scripts/workflow/run_star_rans.sh \
  --input-sim star/naca0012_meshed.sim \
  --reynolds 684587.012 \
  --angle-deg 0 \
  --max-steps 2000 \
  --force
```

The donor is deliberately normalized exactly like the Nektar++ case:
`U_inf=1`, `rho=1`, and `c=1`. The only flow-scale input is the chord Reynolds
number, and both codes therefore use
`mu=nu=1/Re=1.4607346947446909e-6` for the default `Re=684587.012`.
STAR still labels these numerical values with its unit system; they represent
the nondimensional equations and are transferred to Nektar++ without velocity
or viscosity rescaling.
The run produces:

```text
star/naca0012_rans.sim
star/naca0012_rans_raw.csv
star/naca0012_rans_nektar.csv
star/naca0012_rans.log
star/naca0012_rans.provenance.txt
```

The raw table uses STAR's version-dependent column labels. The normalized file
has the FieldConvert convention:

```text
# x,y,z,u,v,w,p
```

The driver uses the same transactional staging and Power-on-Demand handling as
the mesh driver. A secure PoD invocation is:

```bash
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" \
  ./scripts/workflow/run_star_rans.sh --power-on-demand --force
unset star_pod_key
```

The complete mesh/high-order pipeline exposes the RANS stage through
`--run-rans`. For the previously selected high-order parameters:

```bash
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" \
  ./scripts/workflow/run_remote_pipeline.sh \
    --name naca0012_rans_smoke \
    --power-on-demand \
    --run-rans \
    --rans-reynolds 684587.012 \
    --rans-max-steps 2000 \
    --rans-min-steps 500 \
    --rans-residual-tol 3e-3 \
    --cad-order 4 \
    --bl-layers 8 \
    --bl-ratio 1.2 \
    --force
unset star_pod_key
```

This first command solves RANS on the same one-thick-prism mesh used for the
NekMesh topology handoff. Treat that as an interoperability and initialization
smoke test, not as a validated wall-resolved RANS calculation. A credible SST
donor generally needs its own STAR mesh branch with a conventional multi-layer
prism stack and a checked y+ distribution. The target CCM branch must retain
exactly one macro prism for NekMesh splitting. Because the field transfer is
coordinate based, the donor and target STAR meshes may differ while sharing
the same physical CAD, units and domain.

For example, make a separate donor-mesh simulation without changing the
one-prism handoff output:

```bash
./scripts/workflow/run_star_mesh.sh \
  --output-sim star/naca0012_rans_donor_mesh.sim \
  --output-ccm star/naca0012_rans_donor_mesh.ccm \
  --log star/naca0012_rans_donor_mesh.log \
  --provenance star/naca0012_rans_donor_mesh.provenance.txt \
  --prism-layers 20 \
  --prism-height 0.03 \
  --prism-stretching 1.2

./scripts/workflow/run_star_rans.sh \
  --input-sim star/naca0012_rans_donor_mesh.sim \
  --output-sim star/naca0012_rans_donor.sim \
  --raw-table star/naca0012_rans_donor_raw.csv \
  --output-csv star/naca0012_rans_donor_nektar.csv
```

Those layer values are an example only. Select the donor first-cell height,
layer count and stretching from its target wall treatment/y+ and verify prism
quality; do not copy them into the one-layer NekMesh handoff branch.

Before accepting the RANS solution, inspect at least:

- continuity, momentum, k and omega residual histories;
- force-coefficient histories rather than residuals alone;
- mass imbalance and freestream recovery;
- wall y+ and the suitability of the all-y+ treatment;
- the raw/normalized sample count and coordinate bounds.

The scripted stopping logic is:

```text
Maximum Steps OR (Minimum Steps AND every active residual < tolerance)
```

Configure it with `--rans-max-steps`, `--rans-min-steps` and
`--rans-residual-tol`. Maximum steps remains a safety cap; reaching it means
the residual convergence branch was not satisfied. The RANS log and
provenance report the final iteration and the state of every enabled stopping
criterion. By default the pipeline rejects such a capped, unconverged field.
Use `--rans-allow-unconverged` only when deliberately testing transfer and
interoperability rather than creating a production initial condition.

The tutorial keeps a relaxed `3e-3` transfer criterion after at least 500
iterations and permits the maximum-step result because this one-macro-prism
donor is only an interoperability precursor. Recheck the residual and force
histories after changing to the normalized `U=1` formulation: solver scaling
can change the reported normalized-residual history even at identical
Reynolds number. This is not a universal RANS convergence tolerance, and
increasing the cap alone does not fix a residual plateau.

Residual convergence is necessary but not sufficient. For production work,
also create lift/drag report monitors and require a suitably small asymptotic
band or standard deviation over a meaningful window. At zero incidence, an
absolute/asymptotic lift band is preferable to relative change because the
mean lift is close to zero. Inspect mass imbalance, y+ and surface loads before
accepting the field; no numerical stopping rule can guarantee the physically
correct steady solution.

To create a Nektar++ initial field, use a solver session that contains both the
final curved geometry and its `EXPANSIONS` definition:

```bash
./scripts/nektar/rans_csv_to_nektar_fld.sh \
  --session nekmesh/naca0012_solver.xml \
  --csv star/naca0012_rans_nektar.csv \
  --output nekmesh/naca0012_rans_initial.fld \
  --vtu nekmesh/naca0012_rans_initial.vtu \
  --force
```

Internally this runs the FieldConvert module:

```text
interppointdatatofld:frompts=star/naca0012_rans_nektar.csv
```

A bare NekMesh geometry XML has no solution expansions and is therefore not
enough for this step. The field names should be compatible with `u,v,w,p`.
After interpolation, inspect the VTU, the velocity divergence, boundary values
and pressure convention. The scattered cell-centre interpolation does not
guarantee a discretely divergence-free Nektar++ field or exact no-slip values;
the Nektar++ startup strategy should enforce boundary conditions and, where
appropriate, project/correct the initial velocity before collecting physical
statistics.

For the complete automated path, request a restart session derived from the
newly generated final mesh:

```bash
./scripts/workflow/run_remote_pipeline.sh \
  --star-template star/naca0012_periodic_template.sim \
  --name naca0012_periodic_full \
  --periodic-span \
  --run-rans \
  --rans-session auto \
  --rans-num-modes 5 \
  --cad-order 4 \
  --bl-layers 8 \
  --bl-ratio 1.2 \
  --power-on-demand \
  --force
```

With `--rans-session auto`, the pipeline copies the final mesh geometry into
`nekmesh/NAME_restart_session.xml`, replaces the default geometry-only
expansions with `u,v,w,p`, and then writes both:

```text
nekmesh/NAME_rans_initial.fld
nekmesh/NAME_rans_initial.vtu
```

The automatic session is sufficient for interpolation and visualization. The
solver validation session is tracked separately at
`nektar/naca0012-periodic/session.xml`; it adds the intended expansions,
conditions, periodic pair, force/modal-energy filters and checkpoint output.
Run it with:

```bash
./scripts/workflow/run_nektar_solver.sh --force --steps 100 --np 32
```

The 100-step restart validation has completed on 32 MPI ranks. A 48-rank
decomposition failed in its first pressure solve, so decomposition sensitivity
must still be checked before selecting a production MPI layout. That run used
the preceding donor scaling; regenerate the donor and repeat it after the
`U=1`, `rho=1`, `nu=1/Re` change. See `nektar/naca0012-periodic/README.md` for
the current checkpoint.

## Spanwise periodicity in STAR and NekMesh

STAR and Nektar++ need three related pieces of periodic information:

```text
STAR periodic interface -> periodic RANS flux/solution coupling
NekMesh peralign        -> matching composite order and orientation
Nektar++ P conditions   -> periodic solver boundary conditions
```

`peralign` does not create a matching mesh. It assumes that the two surfaces
contain the same number of translated faces with the same shapes and sizes.
The earlier non-periodic STAR meshes do not satisfy this: the baseline
`SpanMin` and `SpanMax` composites contain 3154 and 3176 faces respectively.
A periodic pipeline must therefore start from a STAR template that generates a
one-to-one spanwise surface mesh.

### STAR template checkpoint

Create a separate template so the validated symmetry case remains available:

```text
star/naca0012_periodic_template.sim
```

In STAR-CCM+ 20.04:

1. Open the existing mesh template.
2. Under **Regions > Fluid > Boundaries**, select `SpanMin` and `SpanMax`.
3. Right-click and choose **Create Interface**. Some installations expose
   **Create Periodic Interface** directly.
4. Rename the resulting object under **Interfaces** to `SpanwisePeriodic`.
5. Select periodic/translational coupling and set the translation from
   `SpanMin` to `SpanMax` to `(0, 0, 0.2 m)`. Reversing the selected boundary
   order may require `(0, 0, -0.2 m)`.
6. If STAR offers mapped/non-conformal versus conformal/one-to-one periodicity,
   select conformal or one-to-one. A mapped interface can solve RANS but cannot
   satisfy NekMesh `peralign`.
7. Clear the old volume and surface meshes, regenerate
   `NACA0012_AutomatedMesh`, and save the new template.

The exact interface labels vary by STAR release. Confirm that the mesh log
reports one conformal periodic interface and that the two boundaries have equal
face counts. If the dialog only creates a non-conformal mapping, stop and
report its displayed properties; that interface alone is insufficient to
constrain the surface remesher.

For a standalone RANS run based on the periodic template:

```bash
./scripts/workflow/run_star_rans.sh \
  --input-sim star/naca0012_periodic_meshed.sim \
  --span-mode periodic \
  --periodic-interface SpanwisePeriodic \
  --max-steps 2000
```

Periodicity is a STAR interface relationship, not a boundary type. In periodic
mode, `ConfigureRans.java` deliberately does not replace the span boundaries
with symmetry conditions.

### Automated NekMesh alignment

Enable the complete periodic path with:

```bash
./scripts/workflow/run_remote_pipeline.sh \
  --star-template star/naca0012_periodic_template.sim \
  --periodic-span \
  --star-periodic-interface SpanwisePeriodic \
  --run-rans \
  --cad-order 4 \
  --bl-layers 8 \
  --bl-ratio 1.2
```

For the verified CCM mapping, the pipeline runs the equivalent of:

```bash
NekMesh -v \
  -m peralign:surf1=6:surf2=8:dir=z:orient:tolfac=4:abstol=0 \
  nekmesh/naca0012_linear.xml \
  nekmesh/naca0012_linear_periodic_check.xml
```

The `orient` option is required for the tetrahedron/prism hybrid mesh. The
pipeline first makes a disposable linear `peralign` pass as a cheap one-to-one
preflight. The installed module explicitly recommends applying the effective
`peralign:orient` pass after boundary-layer splitting for a hybrid mesh, so the
production order is `projectcad -> bl -> peralign:orient -> projectcad`.
The final projection restores tetrahedral and face-interior curvature discarded
when `orient` recreates elements. Unequal face counts, missing face pairs or
skipped alignment are treated as failures before RANS iterations are run.

The default pair is `SpanMin=C[6]`, `SpanMax=C[8]`, translated along `z`.
Override `--periodic-surf1`, `--periodic-surf2` or `--periodic-dir` if a new CCM
import produces different IDs.

### Nektar++ periodic conditions

`peralign` fixes ordering but does not write solver boundary conditions. A
session using boundary-region IDs 6 and 8 can pair all incompressible variables
as follows:

```xml
<BOUNDARYREGIONS>
  <B ID="6"> C[6] </B>
  <B ID="8"> C[8] </B>
</BOUNDARYREGIONS>
<BOUNDARYCONDITIONS>
  <REGION REF="6">
    <P VAR="u" VALUE="[8]" />
    <P VAR="v" VALUE="[8]" />
    <P VAR="w" VALUE="[8]" />
    <P VAR="p" VALUE="[8]" />
  </REGION>
  <REGION REF="8">
    <P VAR="u" VALUE="[6]" />
    <P VAR="v" VALUE="[6]" />
    <P VAR="w" VALUE="[6]" />
    <P VAR="p" VALUE="[6]" />
  </REGION>
</BOUNDARYCONDITIONS>
```

Both directions must be specified. After interpolating the STAR field, compare
`u,v,w,p` on the two planes after translating by `0.2 m`; scattered
interpolation can introduce a small seam mismatch even when the STAR donor is
periodic. Configure the solver's pressure-nullspace treatment consistently.

After uploading, load the local site settings, log in with X11 forwarding and
locate the remote STAR command:

```bash
source config/site.env
ssh -X "$REMOTE_HOST"
cd ~/nektar-star-pipeline
which starccm+
```

If STAR is supplied through environment modules, load the site-provided STAR
module first. Do not assume the local machine's Python/Gmsh environment exists
on the remote host; the validated STEP is already generated and ready to
import.

Set `STAR_EXECUTABLE` in `config/site.env` to a command available through
`PATH` or to the site-specific executable path. The validated macro API targets
STAR-CCM+ 2506, build 20.04.007.

After synchronising the latest scripts, launch it from an X11-forwarded remote
shell with:

```bash
./scripts/site/launch_star.sh
```

Additional STAR command-line options can be appended to that command and are
passed through unchanged.

To retrieve selected STAR results later, preview the generic download helper
from the local tutorial root:

```bash
./scripts/site/sync_from_remote.sh
./scripts/site/sync_from_remote.sh --execute
```

## Container runtime and pinned Nektar++ image

All Nektar++ wrappers use one digest-pinned full OCI image on local and remote
machines. It supplies NekMesh, FieldConvert and IncNavierStokesSolver. Runtime
selection prefers Docker when available and otherwise uses
the `APPTAINER_EXECUTABLE` command/path from `config/site.env`.

Apptainer pulls the images through their `docker://` registry transport; this
does not require a privileged Docker daemon. The historical wrapper filenames
retain `_docker.sh` so existing commands continue to work. Runtime selection is
automatic, or can be made explicit with:

```bash
NEKTAR_CONTAINER_RUNTIME=apptainer ./scripts/nektar/nekmesh_docker.sh -l
```

The immutable default is defined once in `scripts/nektar/container_images.sh`.
Override it only deliberately using `NEKTAR_CONTAINER_IMAGE`.
The former component-specific NekMesh, FieldConvert and solver image variables
have been removed; delete them from older local `config/site.env` files.

## Remote end-to-end pipeline

`scripts/workflow/run_remote_pipeline.sh` has production and diagnostic
profiles. Production is the default. Pass `--diagnostic` to chain the
validated tutorial checkpoints below, stopping at the first failure:

```text
STAR mesh + mesh-only CCM export
  -> NekMesh linear import
  -> linear VTU
  -> P4 projection onto cad/naca0012_domain.step
  -> P4 Jacobian check
  -> native high-order P4 VTU
  -> six-layer P4 prism split
  -> final Jacobian audit
  -> native high-order split-mesh VTU
```

Run the complete pipeline on the remote host using the PoD key without putting
the credential in shell history or any pipeline/container log:

```bash
cd ~/nektar-star-pipeline
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" \
  ./scripts/workflow/run_remote_pipeline.sh --force --power-on-demand
unset star_pod_key
```

`--star-np N` sets the MPI process count for both STAR meshing and the STAR
RANS solve. To use a smaller serial mesh stage but a parallel RANS stage, add
an independent override, for example:

```bash
--star-np 1 --rans-np 8
```

Conversely, `--star-np 8` without `--rans-np` runs every STAR stage with eight
processes. NekMesh and FieldConvert remain controlled by their own container
tools and are unaffected by these options.

The pipeline copies the credential into the STAR subprocess environment only,
then removes it before launching Apptainer. To restart at the first NekMesh
stage using an already validated CCM file:

```bash
./scripts/workflow/run_remote_pipeline.sh --force --skip-star
```

Each stage has a log under `logs/`. Jacobian stages are parsed, and the pipeline
fails if `Total negative Jacobians` is nonzero. The final products are:

```text
nekmesh/naca0012_p4_bl6.xml
nekmesh/naca0012_p4_bl6.vtu
nekmesh/naca0012_p4_bl6_jac_under_0p7.txt
logs/naca0012_pipeline.provenance.txt
```

The provenance file records timestamps, host, non-secret license mode,
container image digests, and SHA-256 hashes from STEP through final XML/VTU.
The first Apptainer invocation can take longer because it must populate the
user's image cache.

The default production path used by `execute.sh`:

- CAD projection, prism splitting and `peralign:orient` retain their validated
  XML serialization boundaries. The intermediate XMLs live in a private
  temporary directory and are deleted after the final Jacobian gate;
- STAR RANS and NekMesh run concurrently after STAR publishes the meshed SIM
  and CCM;
- all diagnostic VTUs, the periodic preflight, intermediate XML files and the
  pre-split Jacobian audit are omitted;
- RANS exports and interpolates only `u,v,w`, since the committed solver
  session initializes pressure independently;
- a validated STAR template is reused instead of being bootstrapped again.

The production ordering deliberately remains
`projectcad -> bl -> peralign:orient -> projectcad -> jac`. Removing the first
projection requires a separate A/B geometry and Jacobian validation.
If production fails, the driver prints `./execute.sh --diagnostic`; that rerun
restores intermediate XMLs, VTUs, the periodic preflight and detailed quality
logs for diagnosis.

After validating and archiving a completed case, preview removal of its
reproducible intermediates with:

```bash
./scripts/workflow/cleanup_pipeline_outputs.sh --name naca0012_periodic
```

Review the `KEEP`/`REMOVE` list, then apply it explicitly:

```bash
./scripts/workflow/cleanup_pipeline_outputs.sh \
  --name naca0012_periodic \
  --execute
```

The cleanup reads the completed pipeline provenance before deleting it and
refuses to operate unless both runtime inputs are present and non-empty. It
keeps only the final high-order mesh `nekmesh/NAME_pP_blN.xml` and interpolated
restart `nekmesh/NAME_rans_initial.fld` from that case's generated products.
Diagnostic VTUs are removed; CAD, scripts and STAR template inputs are
preserved. The automatic restart XML is for interpolation rather than a full
solver configuration, so the eventual solver session must retain matching
`u,v,w,p` expansions while adding `CONDITIONS`, boundary conditions, solver
information and pressure-nullspace treatment.

To leave the full pipeline running after the SSH connection closes, start it
with `nohup` while retaining the same no-echo credential handling:

```bash
cd ~/nektar-star-pipeline
mkdir -p logs
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" \
  nohup ./scripts/workflow/run_remote_pipeline.sh --force --power-on-demand \
  >logs/naca0012_pipeline.driver.log 2>&1 </dev/null &
pipeline_pid=$!
unset star_pod_key
printf '%s\n' "$pipeline_pid" >logs/naca0012_pipeline.pid
echo "Pipeline PID: $pipeline_pid"
```

Monitor it during this or a later SSH session with:

```bash
tail -f logs/naca0012_pipeline.driver.log
```

The driver log contains only short stage transitions and Jacobian summaries;
detailed tool output remains in the per-stage logs.

## Pipeline parameterisation

The command-line defaults reproduce the validated 42,100-cell baseline rather
than inheriting numeric values silently from the `.sim` template. List all
options with:

```bash
./scripts/workflow/run_star_mesh.sh --help
./scripts/workflow/run_remote_pipeline.sh --help
```

### Parameters owned by STAR

STAR creates the linear topology, so these settings require remeshing and a
new CCM export:

| Option | Baseline | Role |
|---|---:|---|
| `--star-base-size` | `1.0 m` | Global reference length used by the percentage controls |
| `--star-surface-target-pct` | `50` | Default surface target, as a percentage of base size |
| `--star-surface-min-pct` | `1` | Default surface lower bound |
| `--star-wing-target-pct` | `2` | Wing target triangle size; `0.02 m` at the baseline base size |
| `--star-wing-min-pct` | `0.25` | Wing lower bound; `0.0025 m` at baseline |
| `--star-wing-curvature` | `36` | Curvature sampling points around a full circle on the wing control |
| `--star-max-cell-pct` | `10000` | Maximum tetrahedron size relative to base size |
| `--star-tet-growth` | `1.2` | Rate at which tetrahedron size grows away from fine surfaces |
| `--star-volume-size-pct` | `5` | Tet size inside the near-wing block; `0.05 m` at baseline |
| `--star-volume-{x,y,z}-{min,max}` | see below | Six coordinates of the near-wing refinement block |
| `--star-prism-height` | `0.03 m` | Physical total height of the macro-prism stack |
| `--star-prism-layers` | `1` | Linear layers generated by STAR |
| `--star-prism-stretching` | `1.5` | Only meaningful if STAR itself generates multiple layers |

The complete pipeline enforces `--star-prism-layers 1`. This is an intentional
topological invariant: each wall-normal STAR prism is one macro element for
NekMesh to split. `run_star_mesh.sh` exposes other counts for isolated
experiments, but such a CCM is outside this baseline workflow. Standard prism
cells are also forced on by the configuration macro.

The macro keeps `--star-prism-height` physically independent of base size. It
converts the requested metre value to STAR's relative prism-thickness value at
runtime. By contrast, the target/minimum sizes deliberately remain percentages:
changing only base size scales global and wing resolution together. For
example, `--star-base-size 0.5` changes the baseline wing target from `0.02 m`
to `0.01 m`. Change a percentage at the same time if that coupling is not
wanted.

The configuration macro also creates or updates a shape part named
`WingRefinement` and a volumetric control named `WingVolumeControl`. Their
default coordinates are

```text
corner 1 = (-0.25, -0.30, -0.01) m
corner 2 = ( 1.50,  0.30,  0.21) m
```

The block is sizing geometry only: it is not Boolean-subtracted, assigned to a
region, or added to the automated mesh operation's input parts. Its small
spanwise overhang avoids placing its faces exactly on `z=0` and `z=0.2`.
`--star-volume-size-pct` is relative to base size, so leaving it at `5` gives
physical sizes `0.05`, `0.025`, and `0.0125 m` when base size is halved through
the three-level study. The six coordinates are independent parameters and stay
fixed unless explicitly changed.

The initial `5%` control was verified against the same baseline surface and
prism settings. NekMesh reported:

```text
mesh       tetrahedra   prisms   total
baseline        37691     4409   42100
refined         52467     4409   56876
```

The control therefore added 14,776 tetrahedra (39.2%) without changing the
one-layer prism count.

`--star-max-cell-pct` is only an upper bound. Surface size, proximity, volume
growth, the thin `0.2 m` span and prism-to-tet transition can all impose a
smaller local tetrahedron. Likewise, the achieved wing triangles are governed
jointly by target size, minimum size and curvature; none is a promise of one
uniform edge length.

The corresponding standalone STAR names omit the `star-` prefix. For example:

```bash
./scripts/workflow/run_star_mesh.sh --force \
  --base-size 0.75 \
  --wing-target-pct 1.5 \
  --wing-min-pct 0.2 \
  --wing-curvature-points 48 \
  --tet-growth 1.15 \
  --volume-size-pct 5 \
  --volume-x-min -0.25 --volume-x-max 1.75 \
  --volume-y-min -0.35 --volume-y-max 0.35 \
  --volume-z-min -0.01 --volume-z-max 0.21 \
  --prism-height 0.025
```

### Parameters owned by NekMesh

These can be varied while reusing the same linear CCM with `--skip-star`:

| Option | Baseline | Role |
|---|---:|---|
| `--cad-order` | `4` | Polynomial order used by `projectcad` |
| `--bl-surface` | `4` | Wing composite passed to `bl:surf` |
| `--bl-layers` | `6` | Number of children made from each macro prism |
| `--bl-ratio` | `1.5` | Ratio of successive thicknesses from wall to outer edge |
| `--bl-nq` | `P+1` | Points used by the BL module; automatic unless overridden |
| `--jac-threshold` | `0.7` | Cutoff for the detailed final Jacobian report |

The code enforces `nq >= P+1`; leaving `--bl-nq` unset makes it dependent on
the CAD order. The number of layers and geometric ratio are otherwise
independent of polynomial order. They subdivide the existing macro thickness
without changing its outer interface with the tetrahedra. For macro height
`H`, layer count `N`, and outward thickness ratio `r`, the first height is

```text
h1 = H/N                              for r = 1
h1 = H (r - 1) / (r^N - 1)           otherwise.
```

The driver prints this derived value before doing any work. A ratio above one
grows layers away from the wall; a value below one reverses that grading.
Under `--skip-star`, all `--star-*` values are descriptive and do not alter the
reused CCM. Set `--star-prism-height` to the height actually used by that CCM
if the printed derived first-layer height is to be meaningful; provenance
marks whether the STAR settings were applied.

`--bl-surface` is stable only while the CCM boundary/composite ordering is
unchanged. After changing CAD faces, STAR boundaries or the CCM writer, inspect
the verbose linear import and update this ID before splitting.

Use `--name` to prevent a parameter study from overwriting another variant.
Use `--ccm-file` to decouple the output name from an existing linear mesh. For
example, this makes an order-5/eight-layer variant without rerunning STAR:

```bash
./scripts/workflow/run_remote_pipeline.sh --skip-star --force \
  --name naca0012_from_baseline_p5_bl8 \
  --ccm-file star/naca0012_linear.ccm \
  --cad-order 5 \
  --bl-layers 8 \
  --bl-ratio 1.35
```

For a complete new linear and high-order variant:

```bash
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" ./scripts/workflow/run_remote_pipeline.sh \
  --power-on-demand --force \
  --name naca0012_fine_h025_p5_bl8 \
  --star-base-size 0.75 \
  --star-wing-target-pct 1.5 \
  --star-wing-min-pct 0.2 \
  --star-wing-curvature 48 \
  --star-tet-growth 1.15 \
  --star-volume-size-pct 5 \
  --star-volume-x-max 1.75 \
  --star-prism-height 0.025 \
  --cad-order 5 \
  --bl-layers 8 \
  --bl-ratio 1.35
unset star_pod_key
```

The principal coupled quality checks are:

- Finer STAR wing triangles generally reduce the geometric displacement each
  high-order face must absorb, but excessive linear refinement only increases
  element count and can introduce small trailing-edge elements.
- Raising CAD order improves geometric representation but can reduce curved
  Jacobians; it does not automatically require changing STAR resolution.
- Increasing macro height gives the splitter more physical boundary-layer
  depth, but makes STAR prism extrusion and leading/trailing-edge curving more
  demanding. Splitting cannot repair a crossed or collapsed macro prism.
- Increasing `N` or `r` reduces the first split height for fixed `H`; it does
  not alter the prism/tetrahedron interface. Check the printed `h1` and the
  final Jacobian audit together.
- CAD order, layer count and ratio can be swept from one CCM. Any change to
  base size, surface controls, tet growth or macro height requires a new CCM.

Geometry parameters such as chord, span and domain extents remain owned by
`scripts/cad/create_naca0012_domain.py`. Changing them requires regenerating the
STEP file and updating/recreating the STAR geometry/template before this mesh
pipeline runs. The STEP used by `projectcad` must remain exactly coincident
with the geometry used for that CCM.

### Three-level STAR resolution study

`scripts/workflow/run_resolution_study.sh` defines a three-level study with fixed
NekMesh settings `P=4`, `layers=8`, and `r=1.2`. To target twice as many
elements in every spatial direction, it halves the characteristic STAR sizes
between levels:

```text
level   base size [m]   wing target [m]   volume size [m]   curvature points
r0      1.000000000     0.0200000         0.0500000          36
r1      0.500000000     0.0100000         0.0250000          72
r2      0.250000000     0.0050000         0.0125000         144
```

The percentage surface controls remain unchanged, so their physical sizes
scale with base size. Curvature points increase inversely with size to avoid
leaving the leading-edge discretisation unchanged. The macro-prism height is
held at `0.03 m`; therefore all three final eight-layer meshes have the same
nominal first height, approximately `1.8183e-3 m`.

Print the plan without consuming a STAR licence:

```bash
./scripts/workflow/run_resolution_study.sh
```

Run all three sequentially with a securely supplied PoD key:

```bash
read -rsp 'STAR PoD key: ' star_pod_key; echo
STAR_POD_KEY="$star_pod_key" ./scripts/workflow/run_resolution_study.sh \
  --execute --power-on-demand
unset star_pod_key
```

Add `--force` only when intentionally replacing an earlier study. At the end,
the script extracts total, tetrahedral and prism counts from the three linear
CCM import logs and prints the measured ratio between levels. Purely
three-dimensional tetrahedral regions scale approximately as `h^-3`, so the
study plan reports relative tet work of `1x`, `8x`, and `64x`. The historical
42,100-cell mesh did not contain this new volume control, so it is no longer
used as an absolute count estimate. Surface triangles and the one-layer
macro-prism region scale closer to `h^-2`, while local curvature, growth and
the fixed macro height introduce further deviations. Consequently, the mixed
total will not scale by exactly eight.

The third mesh can be large once converted to an eight-layer P4 mesh. Run `r0`
and `r1` first if storage or memory is limited, inspect their measured ratio and
quality, and then decide whether to launch `r2`:

```bash
STAR_POD_KEY="$star_pod_key" ./scripts/workflow/run_resolution_study.sh \
  --execute --power-on-demand --level 0
STAR_POD_KEY="$star_pod_key" ./scripts/workflow/run_resolution_study.sh \
  --execute --power-on-demand --level 1
# Run --level 2 only after inspecting the first two.
```

## CCM-enabled NekMesh in the full Nektar++ container

The locally built NekMesh executables were configured with
`NEKTAR_USE_CCM=OFF`. The pinned full Nektar++ image is instead used for a
reproducible conversion:

```bash
./scripts/nektar/nekmesh_docker.sh -l
```

The same `nektarpp/nektar` digest used for FieldConvert and the solver exposes
NekMesh with the `ccm` input and the `projectcad`, `bl`, `jac`, `peralign` and
`varopti` processing modules. The wrapper mounts this tutorial directory at
`/data` and runs as the invoking user's UID/GID, so generated files remain
locally owned.

The Stage 7 linear conversion is:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  star/naca0012_linear.ccm \
  nekmesh/naca0012_linear.xml
```

The verified import summary is:

```text
vertices       11,351
tetrahedra     37,691
prisms          4,409
pyramids            0
hexahedra           0
volume total   42,100
boundary faces 10,939
```

Print STAR labels without performing the full conversion with:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  star/naca0012_linear.ccm:ccm:writelabelsonly \
  unused:stdout
```

For this file, the full XML composite mapping is:

```text
volume:  C[0] prisms, C[2] tetrahedra
Wing:                    C[4]
Downstream:              C[5]
SpanMin:                 C[6]
FarfieldTop:             C[7]
SpanMax:                 C[8]
FarfieldBottom:          C[9]
Upstream:               C[10]
```

The labels-only command prints surface IDs 2 through 8 because it returns
before allocating all four possible 3D shape-composite slots. For later
`projectcad`/`bl` work, use the IDs in the full converted XML; in particular,
the wing is `C[4]`, not `C[2]`.

## FieldConvert container

FieldConvert and NekMesh are both part of the full `nektarpp/nektar` image, so
the pipeline does not pull a separate utility image. The FieldConvert wrapper
is:

```bash
./scripts/nektar/fieldconvert_docker.sh -h
./scripts/nektar/fieldconvert_docker.sh -l
./scripts/nektar/fieldconvert_docker.sh \
  mesh.xml solution.fld solution.vtu
```

The wrapper uses the same bind mount and invoking UID/GID as the NekMesh
wrapper. The default is the official Nektar++ `v5.10.0` release image, pinned
to its tested amd64 digest
`sha256:2ae26f90b902742b7b2a7e6c9a18542b171e654a26f54b9944ab636d24da3748`.
The release was published on 4 July 2026; its Docker tag and release commit tag
`078dc2fa` resolve to this same digest. To deliberately test the rolling
development image without editing the script, use:

```bash
NEKTAR_CONTAINER_IMAGE=nektarpp/nektar:latest \
  ./scripts/nektar/fieldconvert_docker.sh -h
```

## Stage 8: order-4 CAD projection

Project the original linear CCM mesh onto the same STEP model used by STAR:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m projectcad:file=cad/naca0012_domain.step:order=4 \
  star/naca0012_linear.ccm \
  nekmesh/naca0012_p4.xml
```

The verified CAD bounding boxes are metre-scale: the outer domain is
`[-5,10] x [-5,5] x [0,0.2]`, and the airfoil CAD faces occupy approximately
`x=[0,1]`, `y=[-0.06002,0.06002]`. Association found zero vertices, edges or
faces without a CAD object and skipped zero surface faces. The maximum initial
surface-vertex correction was `4.35e-9 m`.

Check the curved mesh without writing another mesh:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m jac:quality:list \
  nekmesh/naca0012_p4.xml \
  unused:stdout
```

The first order-4 result has zero negative Jacobians, a worst scaled Jacobian
of `0.0623402`, and 20 of 42,100 elements below `0.1`. No volume optimisation
has been applied at this stage.

Generate a diagnostic VTU that preserves the curved elements as VTK Lagrange
high-order cells:

```bash
./scripts/nektar/fieldconvert_docker.sh -f -v \
  nekmesh/naca0012_p4.xml \
  nekmesh/naca0012_p4.vtu:vtu:highorder
```

The `:vtu:highorder` suffix selects FieldConvert's high-order VTK writer; it is
not part of the output filename. Do not use `-n` for this comparison, since
that requests equispaced visualization sampling instead of preserving the
high-order cell representation.

## Stage 9: split the macro-prism layer

The full converted XML maps the wing to `C[4]`. Split its 4,409 order-4
macro-prisms into six layers using a geometric thickness ratio of 1.5:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m bl:surf=4:layers=6:r=1.5:nq=5 \
  nekmesh/naca0012_p4.xml \
  nekmesh/naca0012_p4_bl6.xml
```

`nq=5` retains polynomial order 4. With a 0.03 m macro-layer, the six layer
thicknesses from the wall outward are approximately:

```text
1.44, 2.16, 3.25, 4.87, 7.31, 10.97 mm
```

The split result contains 37,691 tetrahedra and `6 x 4,409 = 26,454` prisms,
for 64,145 volume elements. Check it with:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m jac:quality:list \
  nekmesh/naca0012_p4_bl6.xml \
  unused:stdout
```

The verified result has zero negative Jacobians and a worst scaled Jacobian of
`0.580019`. Export native high-order VTK cells with:

```bash
./scripts/nektar/fieldconvert_docker.sh -f -v \
  nekmesh/naca0012_p4_bl6.xml \
  nekmesh/naca0012_p4_bl6.vtu:vtu:highorder
```

The VTU contains 37,691 `vtkLagrangeTetra` and 26,454
`vtkLagrangeWedge` cells.

## Stage 10: focused quality audit

Record the lower-quality tail without modifying the mesh:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m jac:histo=0.7,14,8:quality:detail:histofile=nekmesh/naca0012_p4_bl6_jac_under_0p7.txt \
  nekmesh/naca0012_p4_bl6.xml \
  unused:stdout
```

There are 221 elements below a scaled Jacobian of 0.7: 20 in `[0.55,0.60)`,
60 in `[0.60,0.65)`, and 141 in `[0.65,0.70)`. All 221 are prisms. The
detailed boundary records place the worst group on wing composite `C[4]` near
`x=1`, `y=+/-0.00126`, i.e. the deliberate finite trailing-edge face. The
worst value is positive (`0.580019`), and no optimisation is applied for this
baseline case.

`varopti` requires an explicit energy model. A representative future trial,
written to a separate output rather than replacing the baseline, would be:

```bash
./scripts/nektar/nekmesh_docker.sh -v \
  -m varopti:hyperelastic:nq=5:maxiter=100:restol=1e-6:numthreads=4 \
  nekmesh/naca0012_p4_bl6.xml \
  nekmesh/naca0012_p4_bl6_varopti.xml
```

Do not run optimisation merely to increase one reported metric. First identify
invalid or near-invalid elements caused by high-order deformation, then compare
Jacobians, CAD conformity and boundary-layer spacing before and after.
