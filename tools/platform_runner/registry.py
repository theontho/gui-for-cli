"""Registry of platform runner actions, platforms, and suites."""

from __future__ import annotations

from .operations_build_run import BUILD, RUN
from .operations_release import (
    BENCHMARK,
    CLEAN,
    PACKAGE,
    PACKAGE_TARGETS,
    RELEASE_BUILD,
    SCREENSHOT,
)
from .operations_setup_quality import FORMAT, LINT, SETUP, TEST

OPERATIONS = {
    "setup": SETUP,
    "lint": LINT,
    "format": FORMAT,
    "test": TEST,
    "build": BUILD,
    "run": RUN,
    "package": PACKAGE,
    "release-build": RELEASE_BUILD,
    "clean": CLEAN,
    "benchmark": BENCHMARK,
    "screenshot": SCREENSHOT,
}

STABLE_PACKAGE = ("webui", "swift", "webview", "tauri", "electron")
PROTOTYPE_PACKAGE = tuple(target for target in PACKAGE_TARGETS if target not in STABLE_PACKAGE)

SUITES = {
    "setup": {
        "default": ("dev",),
        "dev": ("devtools",),
        "python": ("textual", "tkinter", "wx", "toga"),
    },
    "lint": {
        "default": ("stable",),
        "stable": ("swift", "typescript", "locales", "bundles", "tools"),
        "all": tuple(LINT),
    },
    "format": {
        "default": ("all",),
        "all": tuple(FORMAT),
    },
    "test": {
        "stable": ("swift", "webui"),
        "windows": ("windows-core", "webui"),
        "python": ("python",),
        "rust": ("gtk4", "slint", "raygui", "imgui", "iced", "makepad", "egui", "xilem-vello", "gpui"),
        "kotlin": ("compose", "android"),
        "all": (
            "swift",
            "webui",
            "python",
            "mojo",
            "flutter",
            "compose",
            "android",
            "gtk4",
            "slint",
            "raygui",
            "imgui",
            "iced",
            "makepad",
            "egui",
            "xilem-vello",
            "gpui",
            "qt-qml",
            "avalonia",
            "fyne",
        ),
    },
    "build": {
        "stable": ("cli", "webui", "swiftui-macos", "webview-shell", "tauri"),
        "windows": ("windows", "dioxus"),
        "rust": ("dioxus", "gtk4", "slint", "raygui", "imgui", "iced", "makepad", "egui", "xilem-vello", "gpui"),
        "all": tuple(BUILD),
    },
    "run": {
        "stable": ("swiftui-macos", "webui", "tui"),
    },
    "package": {
        "stable": STABLE_PACKAGE,
        "windows": ("webui", "electron", "dioxus", "gio", "slint", "imgui", "windows-bootstrap"),
        "prototypes": PROTOTYPE_PACKAGE,
        "all": PACKAGE_TARGETS,
    },
    "release-build": {
        "stable": STABLE_PACKAGE,
        "windows": ("windows", "windows-readytorun", "windows-bootstrap"),
        "prototypes": PROTOTYPE_PACKAGE,
        "all": tuple(RELEASE_BUILD),
    },
    "clean": {
        "default": ("all",),
    },
    "benchmark": {
        "default": ("list",),
    },
    "screenshot": {
        "default": ("macos",),
    },
}
