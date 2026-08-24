#!/usr/bin/env python3
"""Convert a STAR XyzInternalTable export into Nektar++ point-data CSV."""

from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
from pathlib import Path

FIELD_ALIASES = {
    "x": (r"^x(?:coordinate)?(?:m)?$",),
    "y": (r"^y(?:coordinate)?(?:m)?$",),
    "z": (r"^z(?:coordinate)?(?:m)?$",),
    "u": (
        r"^u(?:ms)?$",
        r"^velocity(?:component)?(?:x|i|0)(?:component)?(?:ms)?$",
        r"^velocity(?:ms)?(?:component)?(?:x|i|0)$",
        r"^(?:x|i)velocity(?:ms)?$",
    ),
    "v": (
        r"^v(?:ms)?$",
        r"^velocity(?:component)?(?:y|j|1)(?:component)?(?:ms)?$",
        r"^velocity(?:ms)?(?:component)?(?:y|j|1)$",
        r"^(?:y|j)velocity(?:ms)?$",
    ),
    "w": (
        r"^w(?:ms)?$",
        r"^velocity(?:component)?(?:z|k|2)(?:component)?(?:ms)?$",
        r"^velocity(?:ms)?(?:component)?(?:z|k|2)$",
        r"^(?:z|k)velocity(?:ms)?$",
    ),
    "p": (
        r"^p(?:pa)?$",
        r"^(?:static)?pressure(?:pa)?$",
    ),
}


def canonical_header(value: str) -> str:
    value = value.strip().strip('"').lower()
    value = value.replace("[", "").replace("]", "")
    value = value.replace("(", "").replace(")", "")
    return re.sub(r"[^a-z0-9]+", "", value)


def find_column(headers: list[str], field: str, explicit: str | None) -> int:
    if explicit is not None:
        for index, header in enumerate(headers):
            if header == explicit or canonical_header(header) == canonical_header(
                explicit
            ):
                return index
        raise ValueError(f"requested {field} column not found: {explicit!r}")

    normalized = [canonical_header(header) for header in headers]
    matches = [
        index
        for index, header in enumerate(normalized)
        if any(re.fullmatch(pattern, header) for pattern in FIELD_ALIASES[field])
    ]
    if len(matches) != 1:
        raise ValueError(
            f"could not identify one {field!r} column; headers are {headers!r}. "
            f"Use --{field}-column to select it explicitly."
        )
    return matches[0]


def read_star_table(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = [
            row
            for row in csv.reader(stream)
            if row and any(cell.strip() for cell in row)
        ]
    if not rows:
        raise ValueError("input table is empty")

    header_index = None
    for index, row in enumerate(rows):
        normalized = {canonical_header(cell) for cell in row}
        if any(
            re.fullmatch(pattern, value)
            for value in normalized
            for pattern in FIELD_ALIASES["x"]
        ):
            header_index = index
            break
    if header_index is None:
        raise ValueError("could not find the STAR table header row")
    return [cell.strip() for cell in rows[header_index]], rows[header_index + 1 :]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize STAR cell-centre data for FieldConvert."
    )
    parser.add_argument("input", type=Path, help="raw STAR XyzInternalTable CSV")
    parser.add_argument("output", type=Path, help="Nektar++ point-data CSV")
    parser.add_argument(
        "--pressure-mode",
        choices=("keep", "subtract-first", "zero-mean"),
        default="keep",
        help="pressure gauge adjustment (default: keep STAR values)",
    )
    parser.add_argument(
        "--velocity-only",
        action="store_true",
        help="write x,y,z,u,v,w and do not require a STAR pressure column",
    )
    for field in ("x", "y", "z", "u", "v", "w", "p"):
        parser.add_argument(
            f"--{field}-column", help=f"explicit STAR header for {field}"
        )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    headers, raw_rows = read_star_table(args.input)
    output_fields = ["x", "y", "z", "u", "v", "w"]
    if not args.velocity_only:
        output_fields.append("p")
    indices = {
        field: find_column(headers, field, getattr(args, f"{field}_column"))
        for field in output_fields
    }

    values: list[list[float]] = []
    required_width = max(indices.values()) + 1
    for line_number, row in enumerate(raw_rows, start=2):
        if len(row) < required_width:
            raise ValueError(f"short row at input data line {line_number}: {row!r}")
        try:
            record = [
                float(row[indices[field]].strip())
                for field in output_fields
            ]
        except ValueError as error:
            raise ValueError(
                f"non-numeric value at input data line {line_number}: {row!r}"
            ) from error
        if not all(math.isfinite(value) for value in record):
            raise ValueError(
                f"non-finite value at input data line {line_number}: {row!r}"
            )
        values.append(record)
    if not values:
        raise ValueError("STAR table contains no data rows")

    pressure_offset: float | None = None
    if not args.velocity_only:
        if args.pressure_mode == "subtract-first":
            pressure_offset = values[0][6]
        elif args.pressure_mode == "zero-mean":
            pressure_offset = statistics.fmean(record[6] for record in values)
        else:
            pressure_offset = 0.0
        for record in values:
            record[6] -= pressure_offset

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        stream.write(f"# {','.join(output_fields)}\n")
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerows(
            [[format(value, ".17g") for value in record] for record in values]
        )

    print(f"STAR rows              : {len(values)}")
    print(f"STAR columns           : {headers}")
    print(f"Nektar column indices  : {indices}")
    if pressure_offset is not None:
        print(f"Pressure offset (Pa)   : {pressure_offset:.17g}")
    else:
        print("Pressure field         : omitted")
    print(f"Nektar point-data CSV  : {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
