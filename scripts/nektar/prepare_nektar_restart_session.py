#!/usr/bin/env python3
"""Create a field-interpolation session from a generated NekMesh XML mesh."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path

EXPANSIONS_RE = re.compile(
    r"(?P<indent>^[ \t]*)<EXPANSIONS>.*?</EXPANSIONS>",
    re.MULTILINE | re.DOTALL,
)
ENTRY_RE = re.compile(r"<E\b(?P<attributes>[^>]*)/>")
ATTRIBUTE_RE = re.compile(r'([A-Za-z][A-Za-z0-9_]*)="([^"]*)"')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Copy a NekMesh geometry XML and replace its EXPANSIONS block "
            "with u,v,w,p restart expansions."
        )
    )
    parser.add_argument("input", type=Path, help="final NekMesh XML")
    parser.add_argument("output", type=Path, help="restart interpolation session")
    parser.add_argument(
        "--num-modes",
        type=int,
        required=True,
        help="number of modes in each coordinate direction",
    )
    parser.add_argument(
        "--fields",
        default="u,v,w,p",
        help="comma-separated field names (default: u,v,w,p)",
    )
    parser.add_argument("--force", action="store_true", help="replace output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.num_modes < 2:
        raise ValueError("--num-modes must be at least 2")

    fields = [field.strip() for field in args.fields.split(",")]
    if not fields or any(
        not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", field) for field in fields
    ):
        raise ValueError(f"invalid --fields list: {args.fields!r}")
    if len(set(fields)) != len(fields):
        raise ValueError(f"duplicate field in --fields: {args.fields!r}")

    input_path = args.input.resolve()
    output_path = args.output.resolve()
    if input_path == output_path:
        raise ValueError("input and output session paths must differ")
    if not input_path.is_file() or input_path.stat().st_size == 0:
        raise FileNotFoundError(f"input mesh is missing or empty: {args.input}")
    if output_path.exists() and not args.force:
        raise FileExistsError(f"output exists (use --force): {args.output}")

    document = input_path.read_text(encoding="utf-8")
    if "<GEOMETRY" not in document:
        raise ValueError("input does not contain a GEOMETRY block")
    match = EXPANSIONS_RE.search(document)
    if match is None:
        raise ValueError("input does not contain an EXPANSIONS block")

    expansion_entries: list[tuple[str, str]] = []
    for entry in ENTRY_RE.finditer(match.group(0)):
        attributes = dict(ATTRIBUTE_RE.findall(entry.group("attributes")))
        composite = attributes.get("COMPOSITE")
        if composite is None:
            continue
        expansion_type = attributes.get("TYPE", "MODIFIED")
        pair = (composite, expansion_type)
        if pair not in expansion_entries:
            expansion_entries.append(pair)
    if not expansion_entries:
        raise ValueError("EXPANSIONS contains no composite entries")

    indent = match.group("indent")
    field_string = ",".join(fields)
    lines = [f"{indent}<EXPANSIONS>"]
    for composite, expansion_type in expansion_entries:
        lines.append(
            f'{indent}    <E COMPOSITE="{composite}" '
            f'NUMMODES="{args.num_modes}" TYPE="{expansion_type}" '
            f'FIELDS="{field_string}" />'
        )
    lines.append(f"{indent}</EXPANSIONS>")
    replacement = "\n".join(lines)
    result = document[: match.start()] + replacement + document[match.end() :]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.", dir=output_path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(result)
        os.replace(temporary_name, output_path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise

    print(f"Source mesh       : {args.input}")
    print(f"Restart session   : {args.output}")
    print(f"Expansion entries : {len(expansion_entries)}")
    print(f"Number of modes   : {args.num_modes}")
    print(f"Fields            : {field_string}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
