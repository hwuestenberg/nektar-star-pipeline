#!/usr/bin/env python3
"""Shared CSV header-matching helpers for STAR/FieldConvert tabular exports.

Both normalize_star_rans_csv.py and plot_surface_fields.py read tabular CSV
exports produced by STAR-CCM+ or Nektar++ FieldConvert and must identify
columns by name. They use two genuinely different matching strategies:

- normalize_star_rans_csv.py matches a STAR export header against a fuzzy,
  aliased set of regex patterns per physical field (many STAR export label
  spellings for the same quantity).
- plot_surface_fields.py matches a FieldConvert CSV header against an exact,
  literal field name after light normalization (FieldConvert's own CSV
  writer uses one stable header spelling).

The two are kept as distinct functions here, rather than unified, so that
neither script's existing matching behavior changes.
"""

from __future__ import annotations

import re

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
    """Fuzzy-canonicalize a STAR export header cell for alias matching."""
    value = value.strip().strip('"').lower()
    value = value.replace("[", "").replace("]", "")
    value = value.replace("(", "").replace(")", "")
    return re.sub(r"[^a-z0-9]+", "", value)


def find_aliased_column(
    headers: list[str], field: str, explicit: str | None
) -> int:
    """Locate a STAR export column for `field` using FIELD_ALIASES."""
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


def row_contains_x_alias(cells: set[str]) -> bool:
    """True if a set of canonicalized cells contains a STAR 'x' header alias."""
    return any(
        re.fullmatch(pattern, value)
        for value in cells
        for pattern in FIELD_ALIASES["x"]
    )


def normalized_header(name: str) -> str:
    """Normalize a FieldConvert CSV header cell for exact-name matching."""
    return name.lstrip("#").strip().lower()
