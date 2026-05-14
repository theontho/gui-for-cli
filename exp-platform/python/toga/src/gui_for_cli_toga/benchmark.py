from __future__ import annotations

from pathlib import Path
from time import perf_counter

from .bundle_loader import load_bundle
from .runtime import RuntimeModel


def reject_forbidden_output(path: Path) -> None:
    resolved = path.expanduser().resolve()
    forbidden = [Path("/tmp"), Path("/var/tmp")]
    if any(resolved == root or root in resolved.parents for root in forbidden):
        raise ValueError("benchmark output must not be written under /tmp or /var/tmp")


def run_benchmark(
    bundle_path: str,
    *,
    repo_root: str | None,
    locale: str | None,
    output: str | None,
    full: bool,
    workspace_root: str | None = None,
) -> str:
    started = perf_counter()
    bundle = load_bundle(bundle_path, repo_root=repo_root, locale=locale, workspace_root=workspace_root)
    loaded_ms = (perf_counter() - started) * 1000
    model = RuntimeModel(bundle)
    model.bootstrap()
    if full:
        model.refresh_all_data_sources()
    snapshot = model.render_snapshot()
    ready_ms = (perf_counter() - started) * 1000
    line = (
        "gfc-toga benchmark "
        f"bundle_loaded_ms={loaded_ms:.1f} "
        f"ui_ready_ms={ready_ms:.1f} "
        f"pages={snapshot['page_count']} "
        f"controls={snapshot['control_count']} "
        f"actions={snapshot['action_count']} "
        f"setup_steps={snapshot['setup_steps']} "
        f"terminal_text_direction={snapshot['terminal_text_direction']} "
        f"layout_direction={snapshot['layout_direction']}"
    )
    if output:
        path = Path(output)
        reject_forbidden_output(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(line + "\n", encoding="utf-8")
    return line
