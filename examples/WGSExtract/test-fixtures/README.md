# Test fixtures

Tiny CSV catalogs used by `list-reference-genomes.py` when the upstream
`wgsextract-cli` `seed_genomes.csv` cannot be located (typically in CI
or on a fresh dev clone before the runtime has been installed).

These are **not** the canonical catalog — they intentionally contain
only a few rows. The real catalog lives inside the
`wgsextract-cli` repo at `app/src/wgsextract_cli/assets/reference/seed_genomes.csv`
and is materialized by `setup-wgsextract-pixi.sh`.
