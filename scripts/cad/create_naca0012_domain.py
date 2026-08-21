#!/usr/bin/env python3
"""Create and validate a STEP fluid domain around an extruded NACA 0012.

Command-line dimensions are in metres.  Geometry is constructed in
millimetres because the OpenCASCADE STEP writer records millimetre units and
NekMesh's OpenCASCADE backend converts those coordinates back to metres.
"""

from __future__ import annotations

import argparse
import math
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

import gmsh

MM_PER_M = 1000.0
TRAILING_EDGE_COEFFICIENT = -0.1015


@dataclass(frozen=True)
class DomainDimensions:
    chord: float
    span: float
    upstream: float
    downstream: float
    vertical_extent: float

    @property
    def expected_bbox(self) -> tuple[float, float, float, float, float, float]:
        return (
            -self.upstream,
            -self.vertical_extent,
            0.0,
            self.downstream,
            self.vertical_extent,
            self.span,
        )


@dataclass(frozen=True)
class SurfaceInfo:
    tag: int
    name: str
    area: float
    bbox: tuple[float, float, float, float, float, float]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a STEP BRep of a box minus an extruded NACA 0012."
    )
    parser.add_argument("--chord-m", type=float, default=1.0)
    parser.add_argument("--span-m", type=float, default=0.2)
    parser.add_argument("--upstream-m", type=float, default=5.0)
    parser.add_argument("--downstream-m", type=float, default=10.0)
    parser.add_argument("--vertical-extent-m", type=float, default=5.0)
    parser.add_argument("--profile-points", type=int, default=161)
    parser.add_argument("--thickness", type=float, default=0.12)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("cad/naca0012_domain.step"),
    )
    return parser.parse_args()


def naca_half_thickness(x_over_c: float, chord: float, thickness: float) -> float:
    """Return NACA 00xx half-thickness in the same units as ``chord``."""
    x = x_over_c
    return (
        5.0
        * thickness
        * chord
        * (
            0.2969 * math.sqrt(x)
            - 0.1260 * x
            - 0.3516 * x**2
            + 0.2843 * x**3
            + TRAILING_EDGE_COEFFICIENT * x**4
        )
    )


def validate_arguments(args: argparse.Namespace) -> None:
    positive_values = {
        "chord": args.chord_m,
        "span": args.span_m,
        "upstream length": args.upstream_m,
        "downstream coordinate": args.downstream_m,
        "vertical extent": args.vertical_extent_m,
        "thickness": args.thickness,
    }
    for name, value in positive_values.items():
        if value <= 0.0:
            raise ValueError(f"{name} must be positive; got {value}")
    if args.downstream_m <= args.chord_m:
        raise ValueError("downstream-m must lie beyond the airfoil trailing edge")
    if args.profile_points < 21:
        raise ValueError("profile-points must be at least 21")
    maximum_half_thickness = max(
        naca_half_thickness(i / 1000.0, args.chord_m, args.thickness)
        for i in range(1001)
    )
    if args.vertical_extent_m <= maximum_half_thickness:
        raise ValueError("vertical-extent-m must completely contain the airfoil")
    if args.output.suffix.lower() not in {".step", ".stp"}:
        raise ValueError("output filename must end in .step or .stp")


def make_profile_points(
    chord: float, thickness: float, count: int
) -> tuple[list[int], list[int]]:
    upper: list[int] = []
    lower: list[int] = []

    for i in range(count):
        theta = math.pi * i / (count - 1)
        x_over_c = 0.5 * (1.0 - math.cos(theta))
        x = chord * x_over_c
        y = naca_half_thickness(x_over_c, chord, thickness)

        if i == 0:
            leading_edge = gmsh.model.occ.addPoint(x, 0.0, 0.0)
            upper.append(leading_edge)
            lower.append(leading_edge)
        else:
            upper.append(gmsh.model.occ.addPoint(x, y, 0.0))
            lower.append(gmsh.model.occ.addPoint(x, -y, 0.0))

    return upper, lower


def remove_orphan_entities() -> None:
    """Remove construction points so the STEP contains only the fluid solid."""
    for dim in (2, 1, 0):
        orphaned = []
        for entity in gmsh.model.getEntities(dim):
            upward, _ = gmsh.model.getAdjacencies(*entity)
            if len(upward) == 0:
                orphaned.append(entity)
        if orphaned:
            gmsh.model.occ.remove(orphaned, recursive=False)
            gmsh.model.occ.synchronize()


def build_domain(
    dimensions: DomainDimensions,
    thickness: float,
    profile_points: int,
    output: Path,
) -> None:
    gmsh.initialize()
    try:
        gmsh.option.setNumber("General.Terminal", 1)
        gmsh.model.add("naca0012_fluid_domain")

        upper, lower = make_profile_points(dimensions.chord, thickness, profile_points)
        upper_curve = gmsh.model.occ.addSpline(upper)
        trailing_edge = gmsh.model.occ.addLine(upper[-1], lower[-1])
        lower_curve = gmsh.model.occ.addSpline(list(reversed(lower)))
        profile_wire = gmsh.model.occ.addWire(
            [upper_curve, trailing_edge, lower_curve], checkClosed=True
        )
        profile_face = gmsh.model.occ.addPlaneSurface([profile_wire])

        extrusion = gmsh.model.occ.extrude(
            [(2, profile_face)], 0.0, 0.0, dimensions.span
        )
        wing_volumes = [tag for dim, tag in extrusion if dim == 3]
        if len(wing_volumes) != 1:
            raise RuntimeError(f"expected one wing volume, found {wing_volumes}")

        xmin, ymin, zmin, xmax, ymax, _ = dimensions.expected_bbox
        box = gmsh.model.occ.addBox(
            xmin,
            ymin,
            zmin,
            xmax - xmin,
            ymax - ymin,
            dimensions.span,
        )
        result, _ = gmsh.model.occ.cut(
            [(3, box)],
            [(3, wing_volumes[0])],
            removeObject=True,
            removeTool=True,
        )
        if len(result) != 1 or result[0][0] != 3:
            raise RuntimeError(f"boolean cut did not create one volume: {result}")

        gmsh.model.occ.synchronize()
        remove_orphan_entities()
        output.parent.mkdir(parents=True, exist_ok=True)
        gmsh.write(str(output))
    finally:
        gmsh.finalize()


def close_enough(actual: float, expected: float, tolerance: float) -> bool:
    return abs(actual - expected) <= tolerance


def classify_surface(
    bbox: tuple[float, float, float, float, float, float],
    dimensions: DomainDimensions,
    tolerance: float,
) -> str:
    xmin, ymin, zmin, xmax, ymax, zmax = bbox
    exmin, eymin, ezmin, exmax, eymax, ezmax = dimensions.expected_bbox

    if close_enough(xmin, exmin, tolerance) and close_enough(xmax, exmin, tolerance):
        return "Upstream"
    if close_enough(xmin, exmax, tolerance) and close_enough(xmax, exmax, tolerance):
        return "Downstream"
    if close_enough(ymin, eymin, tolerance) and close_enough(ymax, eymin, tolerance):
        return "FarfieldBottom"
    if close_enough(ymin, eymax, tolerance) and close_enough(ymax, eymax, tolerance):
        return "FarfieldTop"
    if close_enough(zmin, ezmin, tolerance) and close_enough(zmax, ezmin, tolerance):
        return "SpanMin"
    if close_enough(zmin, ezmax, tolerance) and close_enough(zmax, ezmax, tolerance):
        return "SpanMax"
    return "Wing"


def incidence_histogram(values: Iterable[int]) -> dict[int, int]:
    histogram: dict[int, int] = {}
    for value in values:
        histogram[value] = histogram.get(value, 0) + 1
    return histogram


def analytical_profile_area(chord: float, thickness: float) -> float:
    integral = (
        0.2969 * 2.0 / 3.0
        - 0.1260 / 2.0
        - 0.3516 / 3.0
        + 0.2843 / 4.0
        + TRAILING_EDGE_COEFFICIENT / 5.0
    )
    return 10.0 * thickness * chord**2 * integral


def inspect_step(
    path: Path, dimensions: DomainDimensions, thickness: float
) -> list[SurfaceInfo]:
    step_text = path.read_text(encoding="ascii", errors="ignore")
    if "SI_UNIT(.MILLI.,.METRE.)" not in step_text:
        raise RuntimeError("STEP file does not declare millimetre length units")

    gmsh.initialize()
    try:
        gmsh.option.setNumber("General.Terminal", 1)
        gmsh.model.add("naca0012_round_trip_validation")
        gmsh.model.occ.importShapes(str(path), highestDimOnly=False)
        gmsh.model.occ.synchronize()

        volumes = gmsh.model.getEntities(3)
        if len(volumes) != 1:
            raise RuntimeError(f"expected one imported fluid volume, found {volumes}")

        entity_counts = {dim: len(gmsh.model.getEntities(dim)) for dim in range(4)}
        expected_entity_counts = {0: 14, 1: 21, 2: 9, 3: 1}
        if entity_counts != expected_entity_counts:
            raise RuntimeError(
                "unexpected STEP topology (vertices, curves, faces, volumes): "
                f"{entity_counts}"
            )
        for dim in (0, 1, 2):
            orphaned = [
                entity
                for entity in gmsh.model.getEntities(dim)
                if len(gmsh.model.getAdjacencies(*entity)[0]) == 0
            ]
            if orphaned:
                raise RuntimeError(f"STEP contains orphaned entities: {orphaned}")

        bbox = tuple(gmsh.model.getBoundingBox(-1, -1))
        tolerance = max(dimensions.chord * 1.0e-7, 1.0e-5)
        for axis, (actual, expected) in enumerate(
            zip(bbox, dimensions.expected_bbox, strict=True)
        ):
            if not close_enough(actual, expected, tolerance):
                raise RuntimeError(
                    f"bounding-box component {axis} is {actual}, expected {expected}"
                )

        faces = sorted(
            set(
                gmsh.model.getBoundary(
                    volumes, combined=False, oriented=False, recursive=False
                )
            )
        )
        if len(faces) != 9:
            raise RuntimeError(f"expected nine boundary faces, found {len(faces)}")

        curve_incidence: dict[tuple[int, int], int] = {}
        for face in faces:
            curves = gmsh.model.getBoundary(
                [face], combined=False, oriented=False, recursive=False
            )
            for curve in curves:
                curve_incidence[curve] = curve_incidence.get(curve, 0) + 1
        if not curve_incidence or any(value != 2 for value in curve_incidence.values()):
            raise RuntimeError(
                "fluid shell is not closed; curve incidences are "
                f"{incidence_histogram(curve_incidence.values())}"
            )

        surface_info = []
        for dim, tag in faces:
            face_bbox = tuple(gmsh.model.getBoundingBox(dim, tag))
            surface_info.append(
                SurfaceInfo(
                    tag=tag,
                    name=classify_surface(face_bbox, dimensions, tolerance),
                    area=gmsh.model.occ.getMass(dim, tag),
                    bbox=face_bbox,
                )
            )

        counts = incidence_histogram(info.name for info in surface_info)
        expected_counts = {
            "Upstream": 1,
            "Downstream": 1,
            "FarfieldBottom": 1,
            "FarfieldTop": 1,
            "SpanMin": 1,
            "SpanMax": 1,
            "Wing": 3,
        }
        if counts != expected_counts:
            raise RuntimeError(f"unexpected surface classification: {counts}")

        box_volume = (
            (dimensions.upstream + dimensions.downstream)
            * 2.0
            * dimensions.vertical_extent
            * dimensions.span
        )
        fluid_volume = gmsh.model.occ.getMass(*volumes[0])
        removed_volume = box_volume - fluid_volume
        expected_removed_volume = (
            analytical_profile_area(dimensions.chord, thickness) * dimensions.span
        )
        relative_error = abs(removed_volume - expected_removed_volume) / (
            expected_removed_volume
        )
        # The default 161-point interpolating spline is within this 0.1%
        # tolerance. Very coarse profiles may pass argument validation but are
        # intentionally rejected here when their enclosed area is inaccurate.
        if removed_volume <= 0.0 or relative_error > 1.0e-3:
            raise RuntimeError(
                "airfoil subtraction volume is inconsistent: "
                f"removed={removed_volume}, analytical={expected_removed_volume}"
            )

        trailing_edge_thickness = 2.0 * naca_half_thickness(
            1.0, dimensions.chord, thickness
        )
        expected_te_area = trailing_edge_thickness * dimensions.span
        wing_areas = sorted(info.area for info in surface_info if info.name == "Wing")
        if not close_enough(
            wing_areas[0], expected_te_area, max(expected_te_area * 1.0e-6, 1.0e-6)
        ):
            raise RuntimeError(
                "the deliberate trailing-edge face was not recovered correctly"
            )

        print("\nValidated STEP fluid domain")
        print("---------------------------")
        print("STEP units             : millimetres")
        print(f"Entities [0D,1D,2D,3D] : {[entity_counts[d] for d in range(4)]}")
        print(f"Volumes                : {len(volumes)}")
        print(f"Boundary faces         : {len(faces)}")
        print(f"Boundary curves        : {len(curve_incidence)}")
        print(
            f"Curve incidence        : {incidence_histogram(curve_incidence.values())}"
        )
        print(f"Bounding box [mm]      : {tuple(round(v, 6) for v in bbox)}")
        print(f"Fluid volume [mm^3]    : {fluid_volume:.9f}")
        print(f"Removed volume [mm^3]  : {removed_volume:.9f}")
        print(f"TE thickness [mm]      : {trailing_edge_thickness:.9f}")
        print(f"TE face area [mm^2]    : {wing_areas[0]:.9f}")
        print("\nSurface identification for later STAR naming")
        print("tag  conceptual name    area [mm^2]       bounding box [mm]")
        for info in sorted(surface_info, key=lambda item: (item.name, item.tag)):
            short_bbox = tuple(round(value, 6) for value in info.bbox)
            print(f"{info.tag:>3}  {info.name:<18} {info.area:>14.6f}  {short_bbox}")

        return surface_info
    finally:
        gmsh.finalize()


def main() -> None:
    args = parse_args()
    validate_arguments(args)

    dimensions = DomainDimensions(
        chord=args.chord_m * MM_PER_M,
        span=args.span_m * MM_PER_M,
        upstream=args.upstream_m * MM_PER_M,
        downstream=args.downstream_m * MM_PER_M,
        vertical_extent=args.vertical_extent_m * MM_PER_M,
    )
    output = args.output.resolve()
    build_domain(
        dimensions=dimensions,
        thickness=args.thickness,
        profile_points=args.profile_points,
        output=output,
    )
    inspect_step(output, dimensions, args.thickness)
    print(f"\nWrote: {output}")


if __name__ == "__main__":
    main()
