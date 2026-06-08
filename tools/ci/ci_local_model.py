from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON = os.environ.get("PYTHON", sys.executable)
APPLE_DIR = "platform/apple"
APPLE_WORKSPACE = f"{APPLE_DIR}/GUIForCLI.xcworkspace"
APPLE_DERIVED_DATA = f"{APPLE_DIR}/DerivedData"
LOCAL_GROUPS = ("apple", "typescript", "rust", "go", "cpp", "dotnet", "python", "windows", "meta")
ALL_ZERO_SHA = "0" * 40
if sys.platform.startswith("darwin"):
    CURRENT_OS = "darwin"
elif sys.platform.startswith("win"):
    CURRENT_OS = "windows"
elif sys.platform.startswith("linux"):
    CURRENT_OS = "linux"
else:
    CURRENT_OS = sys.platform
APPLE_PLATFORMS = ("darwin",)
NPM = "npm.cmd" if CURRENT_OS == "windows" else "npm"
MAKE_HELP_COMMAND = (
    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "make.ps1", "help"]
    if CURRENT_OS == "windows"
    else ["make", "help"]
)
SWIFT_FORMAT_PATHS = [
    f"{APPLE_DIR}/Package.swift",
    f"{APPLE_DIR}/Project.swift",
    f"{APPLE_DIR}/Tuist.swift",
    f"{APPLE_DIR}/shared/Package.swift",
    f"{APPLE_DIR}/shared/Sources",
    f"{APPLE_DIR}/shared/Tests",
    f"{APPLE_DIR}/shared/app",
    f"{APPLE_DIR}/swiftui",
    f"{APPLE_DIR}/exp",
    "scripts",
]
SWIFT_GIT_ENV = {
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "safe.bareRepository",
    "GIT_CONFIG_VALUE_0": "all",
}


@dataclass
class Step:
    name: str
    command: list[str]
    groups: tuple[str, ...]
    fast_skip: bool = False  # skipped in --fast mode
    optional: bool = False  # missing tools yield warning, not failure
    platforms: tuple[str, ...] = ()
    timeout_seconds: int | None = None
