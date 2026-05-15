from __future__ import annotations

import json
import os
import shutil
import subprocess
import unittest
from pathlib import Path


MOJO_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = MOJO_DIR.parents[1]
SCRATCH = REPO_ROOT / "tmp" / "mojo-tests"


class MojoRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        shutil.rmtree(SCRATCH, ignore_errors=True)
        SCRATCH.mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        shutil.rmtree(SCRATCH, ignore_errors=True)

    def test_describes_wgs_bundle(self) -> None:
        result = run_mojo("--describe")
        snapshot = json.loads(result.stdout.strip().splitlines()[-1])

        self.assertEqual(snapshot["displayName"], "WGS Extract")
        self.assertEqual(snapshot["pages"], 9)
        self.assertGreater(snapshot["controls"], 0)
        self.assertGreater(snapshot["actions"], 0)
        self.assertEqual(snapshot["terminalTextDirection"], "ltr")

    def test_benchmark_writes_metrics(self) -> None:
        output = SCRATCH / "benchmark.json"
        result = run_mojo(
            "--benchmark",
            "--benchmark-full",
            "--once",
            "--benchmark-output",
            str(output),
        )

        self.assertIn("gfc-mojo benchmark", result.stdout)
        self.assertTrue(output.is_file())
        metrics = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(metrics["pages"], 9)
        self.assertGreater(metrics["controls"], 0)
        self.assertGreater(metrics["actions"], 0)


def run_mojo(*args: str) -> subprocess.CompletedProcess[str]:
    command = [
        "pixi",
        "run",
        "mojo",
        "run",
        "src/gui_for_cli_mojo.mojo",
        "--repo-root",
        str(REPO_ROOT),
        "--bundle",
        "examples/WGSExtract",
        "--locale",
        "en",
        *args,
    ]
    env = os.environ.copy()
    env["GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT"] = str(SCRATCH / "workspaces")
    return subprocess.run(
        command,
        cwd=MOJO_DIR,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


if __name__ == "__main__":
    unittest.main()
