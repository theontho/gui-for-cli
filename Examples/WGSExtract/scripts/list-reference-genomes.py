#!/usr/bin/env python3
"""Library list provider for the WGSExtract reference-genome control.

Emits a JSON document of `{options, items}` describing the user's
local reference-genome library, derived by joining:

  1. the upstream wgsextract-cli seed catalog (`seed_genomes.csv`,
     authored and maintained inside that project), and
  2. the on-disk state of `<library>/genomes/<final>` (+ `.fai`,
     `.partial`, etc).

Only catalog entries whose final file exists locally make it into the
`options` list; `items` is the full catalog annotated with status and
on-disk size for the library page table.

The catalog location is resolved (in order):
  * $WGSEXTRACT_REFERENCE_CATALOG, if set
  * $GUI_FOR_CLI_BUNDLE_ROOT/runtime/wgsextract-cli/app/{,src/}wgsextract_cli/assets/reference/seed_genomes.csv
  * test fixture inside the bundle (`test-fixtures/seed_genomes.csv`)
    — used by CI/tests so the script remains executable without a
    full wgsextract install.

Usage:
  list-reference-genomes.py [all|options|items] [<library>]

The library directory defaults to:
  $GUI_FOR_CLI_CONFIG_REFERENCE_LIBRARY,
  else $GUI_FOR_CLI_BUNDLE_WORKSPACE/reference,
  else $PWD/reference.

This replaces the legacy bash heredoc-based provider so the catalog
stays the single source of truth in wgsextract-cli — no manifest sync
step required when upstream adds a new genome.
"""
from __future__ import annotations

import csv
import json
import os
import sys
from pathlib import Path
from typing import Iterable


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def find_catalog(bundle_root: Path | None) -> Path | None:
    explicit = env("WGSEXTRACT_REFERENCE_CATALOG")
    if explicit and Path(explicit).is_file():
        return Path(explicit)
    candidates: list[Path] = []
    if bundle_root is not None:
        candidates += [
            bundle_root / "runtime/wgsextract-cli/app/src/wgsextract_cli/assets/reference/seed_genomes.csv",
            bundle_root / "runtime/wgsextract-cli/app/wgsextract_cli/assets/reference/seed_genomes.csv",
        ]
    script_dir = Path(__file__).resolve().parent
    candidates.append(script_dir.parent / "test-fixtures" / "seed_genomes.csv")
    for c in candidates:
        if c.is_file():
            return c
    return None


def status_for(genome_file: Path) -> str:
    if genome_file.is_file() and genome_file.with_suffix(genome_file.suffix + ".fai").is_file():
        return "installed"
    if genome_file.is_file():
        return "unindexed"
    if Path(str(genome_file) + ".partial").is_file():
        return "incomplete"
    return "missing"


def size_label(genome_file: Path) -> str:
    total = 0
    for ext in ("", ".partial", ".fai", ".gzi", ".dict"):
        candidate = Path(str(genome_file) + ext) if ext else genome_file
        if candidate.is_file():
            total += candidate.stat().st_size
    if total == 0:
        return ""
    if total > 1_073_741_824:
        return f"{total / 1_073_741_824:.1f} GB"
    return f"{total / 1_048_576:.1f} MB"


def build_for(code: str, final: str, description: str) -> str:
    blob = f"{code} {final} {description}"
    rules = [
        (("GRCh37", "hg19", "hs37", "hg37"), "GRCh37 / hg19"),
        (("GRCh38", "hg38", "hs38"), "GRCh38 / hg38"),
        (("T2T", "CHM13", "chm13", "HG002"), "T2T / CHM13"),
        (("Dog", "Canis", "GSD"), "Dog"),
        (("Cat", "Felis", "Fca"), "Cat"),
    ]
    for tokens, label in rules:
        if any(token in blob for token in tokens):
            return label
    return final


def tags_for(label: str) -> list[dict]:
    if "(Rec)" in label:
        return [{"id": "recommended", "title": "Recommended", "style": "primary"}]
    return []


def clean_label(label: str, source: str) -> str:
    primary = source[:-4] if source.endswith("-Alt") else source
    for token in ("(Rec)", f"({source})", f"({primary})"):
        if not token or token == "()":
            continue
        label = label.replace(token, "")
    while "  " in label:
        label = label.replace("  ", " ")
    return label.strip()


def load_records(catalog: Path) -> Iterable[dict]:
    with catalog.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            code = (row.get("Pyth Code") or "").strip()
            source = (row.get("Source") or "").strip()
            final = (row.get("Final File Name") or "").strip()
            label = (row.get("Library Menu Label") or "").strip()
            description = (row.get("Description") or "").strip()
            if not code or not source or not final or not label:
                continue
            yield {
                "code": code, "source": source, "final": final,
                "label": label, "description": description,
            }


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "all"
    library_arg = argv[2] if len(argv) > 2 else ""
    library = (
        library_arg
        or env("GUI_FOR_CLI_CONFIG_REFERENCE_LIBRARY")
        or os.path.join(env("GUI_FOR_CLI_BUNDLE_WORKSPACE", os.getcwd()), "reference")
    )
    genomes_dir = Path(library) / "genomes"

    bundle_root_env = env("GUI_FOR_CLI_BUNDLE_ROOT")
    bundle_root = Path(bundle_root_env) if bundle_root_env else None
    catalog = find_catalog(bundle_root)
    records = list(load_records(catalog)) if catalog else []

    output: dict = {}

    if mode in ("all", "options"):
        options: list[dict] = []
        seen_finals: set[str] = set()
        selected_assigned = False
        for record in records:
            final = record["final"]
            if final in seen_finals:
                continue
            seen_finals.add(final)
            genome_file = genomes_dir / final
            status = status_for(genome_file)
            if status not in ("installed", "unindexed"):
                continue
            entry = {"id": str(genome_file), "title": record["label"], "status": status}
            if not selected_assigned:
                entry["selected"] = True
                selected_assigned = True
            options.append(entry)
        output["options"] = options

    if mode in ("all", "items"):
        items: list[dict] = []
        for record in records:
            final = record["final"]
            genome_file = genomes_dir / final
            status = status_for(genome_file)
            display_label = clean_label(record["label"], record["source"])
            row_id = f"{record['code']}-{record['source']}-{final}"
            items.append({
                "id": row_id,
                "title": display_label,
                "status": status,
                "tags": tags_for(record["label"]),
                "tooltip": record["description"],
                "values": {
                    "name": display_label,
                    "build": build_for(record["code"], final, record["description"]),
                    "source": record["source"],
                    "code": record["code"],
                    "final": final,
                    "ref": str(genome_file),
                    "size": size_label(genome_file),
                    "description": record["description"],
                },
            })
        output["items"] = items

    json.dump(output, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
