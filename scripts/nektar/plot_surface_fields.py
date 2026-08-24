#!/usr/bin/env python3
"""Plot chordwise wall-shear magnitude and pressure from FieldConvert CSVs."""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple


class Sample(NamedTuple):
    x: float
    y: float
    value: float


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Plot native Shear_mag and pressure against chordwise position. "
            "Repeated spanwise samples are averaged at each x station."
        )
    )
    parser.add_argument(
        "wss_csv",
        type=Path,
        help="FieldConvert CSV containing x, y and Shear_mag",
    )
    parser.add_argument(
        "pressure_csv",
        type=Path,
        help="FieldConvert CSV containing x, y and p",
    )
    parser.add_argument(
        "--shear-output",
        type=Path,
        help="Shear plot path (default: WSS CSV stem + .png)",
    )
    parser.add_argument(
        "--pressure-output",
        type=Path,
        help="Pressure plot path (default: pressure CSV stem + .png)",
    )
    parser.add_argument(
        "--chord",
        type=float,
        default=1.0,
        help="Chord used to normalize the horizontal coordinate (default: 1)",
    )
    parser.add_argument(
        "--leading-edge-x",
        type=float,
        default=0.0,
        help="Leading-edge x coordinate (default: 0)",
    )
    parser.add_argument(
        "--x-tolerance",
        type=float,
        default=1.0e-10,
        help=(
            "Tolerance in x/c for grouping repeated spanwise samples "
            "(default: 1e-10)"
        ),
    )
    parser.add_argument("--dpi", type=int, default=180, help="PNG DPI (default: 180)")
    args = parser.parse_args()

    if not math.isfinite(args.chord) or args.chord <= 0.0:
        parser.error("--chord must be a positive finite number")
    if not math.isfinite(args.leading_edge_x):
        parser.error("--leading-edge-x must be finite")
    if not math.isfinite(args.x_tolerance) or args.x_tolerance <= 0.0:
        parser.error("--x-tolerance must be a positive finite number")
    if args.dpi <= 0:
        parser.error("--dpi must be positive")
    return args


def normalized_header(name: str) -> str:
    return name.lstrip("#").strip().lower()


def read_samples(path: Path, field: str) -> list[Sample]:
    if not path.is_file():
        raise ValueError(f"CSV file does not exist: {path}")

    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.reader(stream)
        try:
            raw_header = next(reader)
        except StopIteration as exc:
            raise ValueError(f"CSV file is empty: {path}") from exc

        header = [normalized_header(name) for name in raw_header]
        required = {"x", "y", field.lower()}
        missing = required.difference(header)
        if missing:
            names = ", ".join(sorted(missing))
            raise ValueError(f"{path} is missing required column(s): {names}")

        x_index = header.index("x")
        y_index = header.index("y")
        field_index = header.index(field.lower())
        samples: list[Sample] = []
        for line_number, row in enumerate(reader, start=2):
            if not row or all(not item.strip() for item in row):
                continue
            try:
                sample = Sample(
                    float(row[x_index]),
                    float(row[y_index]),
                    float(row[field_index]),
                )
            except (IndexError, ValueError) as exc:
                raise ValueError(
                    f"Could not parse numeric data in {path}:{line_number}"
                ) from exc
            if not all(math.isfinite(value) for value in sample):
                raise ValueError(f"Non-finite data in {path}:{line_number}")
            samples.append(sample)

    if not samples:
        raise ValueError(f"CSV file contains no data rows: {path}")
    return samples


def chordwise_average(
    samples: list[Sample],
    leading_edge_x: float,
    chord: float,
    tolerance: float,
) -> dict[str, tuple[list[float], list[float]]]:
    groups: dict[tuple[str, int], list[tuple[float, float]]] = defaultdict(list)
    for sample in samples:
        side = "upper" if sample.y >= 0.0 else "lower"
        x_over_c = (sample.x - leading_edge_x) / chord
        station = round(x_over_c / tolerance)
        groups[(side, station)].append((x_over_c, sample.value))

    result: dict[str, tuple[list[float], list[float]]] = {}
    for side in ("upper", "lower"):
        averaged = []
        for (group_side, _), values in groups.items():
            if group_side != side:
                continue
            count = len(values)
            averaged.append(
                (
                    sum(value[0] for value in values) / count,
                    sum(value[1] for value in values) / count,
                )
            )
        averaged.sort(key=lambda item: item[0])
        result[side] = (
            [item[0] for item in averaged],
            [item[1] for item in averaged],
        )
    return result


def plot_field(
    data: dict[str, tuple[list[float], list[float]]],
    output: Path,
    ylabel: str,
    title: str,
    dpi: int,
) -> None:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        raise RuntimeError(
            "matplotlib is required; install the repository requirements"
        ) from exc

    output.parent.mkdir(parents=True, exist_ok=True)
    figure, axis = plt.subplots(figsize=(7.0, 4.5), constrained_layout=True)
    styles = {
        "upper": {"color": "tab:blue", "label": "Upper surface"},
        "lower": {"color": "tab:orange", "label": "Lower surface"},
    }
    for side in ("upper", "lower"):
        x_values, values = data[side]
        if x_values:
            axis.plot(x_values, values, linewidth=1.25, **styles[side])
    axis.set_xlabel(r"$x/c$")
    axis.set_ylabel(ylabel)
    axis.set_title(title)
    axis.grid(True, alpha=0.25)
    axis.legend()
    figure.savefig(output, dpi=dpi)
    plt.close(figure)


def main() -> int:
    args = parse_arguments()
    shear_output = args.shear_output or args.wss_csv.with_suffix(".png")
    pressure_output = args.pressure_output or args.pressure_csv.with_suffix(".png")

    try:
        shear = read_samples(args.wss_csv, "shear_mag")
        pressure = read_samples(args.pressure_csv, "p")
        shear_data = chordwise_average(
            shear, args.leading_edge_x, args.chord, args.x_tolerance
        )
        pressure_data = chordwise_average(
            pressure, args.leading_edge_x, args.chord, args.x_tolerance
        )
        plot_field(
            shear_data,
            shear_output,
            r"Shear magnitude, $|\tau_w|$",
            "Mean wing wall-shear magnitude",
            args.dpi,
        )
        plot_field(
            pressure_data,
            pressure_output,
            r"Pressure, $p$",
            "Mean wing pressure",
            args.dpi,
        )
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit(f"error: {exc}") from exc

    print(f"Shear plot   : {shear_output}")
    print(f"Pressure plot: {pressure_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
