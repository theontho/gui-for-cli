#!/usr/bin/env python3
"""Dev tool: lint GUI-for-CLI bundle localization TOML files.

Usage:
  scripts/lint-locales.py [--strict] [--json] [--update-source-hashes] [PATH ...]

- PATH may be a bundle directory (containing strings/strings.<code>.toml),
  a strings folder, a specific strings.<code>.toml file, or omitted to
  auto-scan Sources/GUIForCLICore/Resources/BuiltinStrings/ plus
  Examples/*/strings/ in the cwd.
- Reports parse errors, missing/extra/empty/duplicate keys, missing built-in
  keys (only required of the BuiltinStrings folder), invalid layoutDirection,
  and likely-untranslated values (target string identical to source).
- Detects translation drift: when a translated line carries an
  `i18n-source-hash:<hex>` annotation whose hash no longer matches the
  current source value, emits a `source-changed` warning.
- `--update-source-hashes` rewrites locale files in place, stamping each
  translated line with the current source hash. Use this after retranslating.
- Exits non-zero if any errors are found. With --strict, warnings also fail.
- To intentionally suppress an "untranslated" warning on a line (e.g. a proper
  noun reused verbatim), append a trailing `# i18n-ignore` comment, e.g.:
      "bundle.displayName" = "WGS Extract"  # i18n-ignore
"""

from __future__ import annotations

import argparse
import hashlib
import json as jsonlib
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# --- Built-in keys ---------------------------------------------------------

# Keys the runtime always looks up via BundleLocalizationLabels and the default
# exit-code reference table. Locales should provide all of these even if the
# source strings.toml does not.
BUILTIN_REQUIRED_KEYS: list[str] = [
    "language.code",
    "language.name",
    "language.setting.title",
    "language.setting.label",
    "language.setting.searchPlaceholder",
    "language.setting.systemDefault",
    "language.layoutDirection",
    "app.standardOptions.title",
    "app.iconSet.label",
    "app.iconSet.sfSymbols",
    "app.iconSet.bootstrapIcons",
    "app.iconSet.emoji",
    "app.colorTheme.label",
    "app.colorTheme.system",
    "app.colorTheme.light",
    "app.colorTheme.dark",
    "app.terminal.mainTab.title",
    "app.terminal.commandOutput.label",
    "app.terminal.showOutput.label",
    "app.terminal.hideOutput.label",
    "app.terminal.closeTab.labelFormat",
    "app.terminal.exitCode.titleFormat",
    "app.terminal.exitCode.detailFormat",
    "app.terminal.nonzeroExit.summary",
    "app.terminal.processError.title",
    "app.terminal.processError.summary",
    "app.pathPicker.chooseButton.title",
    "app.pathPicker.error.title",
    "app.settingsFile.label",
    "app.loadButton.title",
    "app.saveButton.title",
    "app.actionsColumn.title",
    "app.loading.title",
    "app.refreshing.title",
    "app.retryButton.title",
    "app.error.loadWebUI.title",
    "app.library.empty",
    "app.action.missingInputs.format",
    "app.action.unavailable.title",
    "app.config.loaded.format",
    "app.config.loadError.format",
    "app.config.saved.format",
    "app.config.saveError.format",
    "app.action.precheck.diskSpace.title",
    "app.action.precheck.diskSpace.messageFormat",
    "app.action.precheck.diskSpace.infoTitle",
    "app.action.precheck.diskSpace.infoFormat",
    "library.status.installed",
    "library.status.unindexed",
    "library.status.incomplete",
    "library.status.missing",
    "library.tags.recommended",
    "exitCodes.default.1.title",
    "exitCodes.default.1.summary",
    "exitCodes.default.2.title",
    "exitCodes.default.2.summary",
    "exitCodes.default.126.title",
    "exitCodes.default.126.summary",
    "exitCodes.default.127.title",
    "exitCodes.default.127.summary",
    "exitCodes.default.130.title",
    "exitCodes.default.130.summary",
]

VALID_LAYOUT_DIRECTIONS: set[str] = {"ltr", "rtl"}


# --- TOML parsing (line-aware) --------------------------------------------


@dataclass
class ParsedEntry:
    key: str
    value: str
    line: int
    ignore_untranslated: bool
    # Recorded source hash from a trailing `i18n-source-hash:<hex>` annotation, if present.
    recorded_source_hash: Optional[str]


@dataclass
class ParsedFile:
    path: Path
    entries: list[ParsedEntry] = field(default_factory=list)
    duplicate_keys: list[tuple[str, int, int]] = field(default_factory=list)  # key, line, prev_line
    parse_errors: list[tuple[int, str]] = field(default_factory=list)
    key_index: dict[str, int] = field(default_factory=dict)

    def value_for(self, key: str) -> Optional[str]:
        idx = self.key_index.get(key)
        return self.entries[idx].value if idx is not None else None

    def line_for(self, key: str) -> Optional[int]:
        idx = self.key_index.get(key)
        return self.entries[idx].line if idx is not None else None


def parse_toml_file(path: Path) -> ParsedFile:
    parsed = ParsedFile(path=path)
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        parsed.parse_errors.append((0, "Could not read file as UTF-8"))
        return parsed

    lines = text.split("\n")
    i = 0
    while i < len(lines):
        raw_line = lines[i]
        line_number = i + 1
        i += 1
        trimmed = raw_line.strip()
        if not trimmed or trimmed.startswith("#"):
            continue

        eq = trimmed.find("=")
        if eq < 0:
            parsed.parse_errors.append((line_number, f"Missing `=` separator: {trimmed}"))
            continue

        raw_key = trimmed[:eq].strip()
        raw_value_and_comment = trimmed[eq + 1 :].strip()
        key = unquote_key(raw_key)
        if not key:
            parsed.parse_errors.append((line_number, "Empty key"))
            continue

        # Multiline strings (""" ... """) — collect across lines, no comment support.
        if raw_value_and_comment.startswith('"""'):
            body = raw_value_and_comment[3:]
            collected: list[str] = []
            end_in_body = body.find('"""')
            if end_in_body >= 0:
                collected.append(body[:end_in_body])
            else:
                collected.append(body)
                found_end = False
                while i < len(lines):
                    nxt = lines[i]
                    i += 1
                    end = nxt.find('"""')
                    if end >= 0:
                        collected.append(nxt[:end])
                        found_end = True
                        break
                    collected.append(nxt)
                if not found_end:
                    parsed.parse_errors.append(
                        (line_number, f"Unterminated multiline string for key {key}")
                    )
                    continue
            if collected and collected[0] == "":
                collected.pop(0)
            if collected and collected[-1] == "":
                collected.pop()
            value = "\n".join(collected)
            _record(parsed, key, value, line_number, False, None)
            continue

        # Single-line "value"  optionally followed by `# comment`.
        value_literal, comment = split_value_and_comment(raw_value_and_comment)
        value_literal = value_literal.strip()
        if not (value_literal.startswith('"') and value_literal.endswith('"') and len(value_literal) >= 2):
            parsed.parse_errors.append(
                (line_number, f"Value must be a double-quoted string: {value_literal}")
            )
            continue
        inner = value_literal[1:-1]
        value = unescape(inner)
        ignore_untranslated = "i18n-ignore" in comment.lower()
        recorded_hash = extract_source_hash(comment)
        _record(parsed, key, value, line_number, ignore_untranslated, recorded_hash)

    return parsed


def _record(
    parsed: ParsedFile,
    key: str,
    value: str,
    line: int,
    ignore_untranslated: bool,
    recorded_source_hash: Optional[str],
) -> None:
    if key in parsed.key_index:
        prev = parsed.entries[parsed.key_index[key]].line
        parsed.duplicate_keys.append((key, line, prev))
    parsed.key_index[key] = len(parsed.entries)
    parsed.entries.append(
        ParsedEntry(
            key=key,
            value=value,
            line=line,
            ignore_untranslated=ignore_untranslated,
            recorded_source_hash=recorded_source_hash,
        )
    )


_SOURCE_HASH_RE = re.compile(r"i18n-source-hash:([0-9a-fA-F]+)", re.IGNORECASE)


def extract_source_hash(comment: str) -> Optional[str]:
    """Extract the hex hash from `i18n-source-hash:<hex>` markers in a comment."""
    match = _SOURCE_HASH_RE.search(comment)
    return match.group(1).lower() if match else None


def split_value_and_comment(raw: str) -> tuple[str, str]:
    """Split a TOML right-hand side into value literal and trailing `# comment`.

    Walks the string honoring escaped quotes; first unescaped `#` outside the
    closing quote starts a trailing comment.
    """
    in_string = False
    escaped = False
    split_at: Optional[int] = None
    for idx, ch in enumerate(raw):
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if ch == "#" and not in_string:
            split_at = idx
            break
    if split_at is None:
        return raw, ""
    return raw[:split_at].strip(), raw[split_at:].strip()


def unquote_key(key: str) -> str:
    if len(key) >= 2 and key.startswith('"') and key.endswith('"'):
        return key[1:-1]
    return key


_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}


def unescape(value: str) -> str:
    result: list[str] = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch != "\\":
            result.append(ch)
            i += 1
            continue
        if i + 1 >= len(value):
            result.append("\\")
            break
        nxt = value[i + 1]
        replacement = _ESCAPES.get(nxt)
        if replacement is not None:
            result.append(replacement)
        else:
            result.append("\\")
            result.append(nxt)
        i += 2
    return "".join(result)


# --- Findings --------------------------------------------------------------


@dataclass
class Finding:
    severity: str  # "error" | "warning"
    code: str
    line: Optional[int]
    key: Optional[str]
    message: str


@dataclass
class LocaleReport:
    bundle_name: str
    locale_code: str
    path: Path
    total_keys: int
    findings: list[Finding]

    @property
    def error_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == "error")

    @property
    def warning_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == "warning")


# --- Linter ----------------------------------------------------------------


def lint_locale(
    source: ParsedFile,
    target: ParsedFile,
    bundle_name: str,
    locale_code: str,
    requires_builtin: bool,
) -> LocaleReport:
    findings: list[Finding] = []

    for line, message in target.parse_errors:
        findings.append(Finding("error", "parse-error", line, None, message))
    for key, line, prev_line in target.duplicate_keys:
        findings.append(
            Finding(
                "error",
                "duplicate-key",
                line,
                key,
                f"Duplicate key (previously defined on line {prev_line})",
            )
        )

    source_keys = {e.key for e in source.entries}
    target_keys = {e.key for e in target.entries}
    builtin_set = set(BUILTIN_REQUIRED_KEYS) if requires_builtin else set()
    required_keys = source_keys | builtin_set

    for missing in sorted(required_keys - target_keys):
        is_builtin = missing in builtin_set and missing not in source_keys
        label = "missing-builtin-key" if is_builtin else "missing-key"
        detail = (
            "Required built-in key not provided"
            if is_builtin
            else "Key present in source is missing"
        )
        findings.append(Finding("error", label, None, missing, detail))

    for extra in sorted(target_keys - required_keys):
        findings.append(
            Finding(
                "warning",
                "extra-key",
                target.line_for(extra),
                extra,
                "Key not present in source strings file"
                + (" or built-in list" if requires_builtin else ""),
            )
        )

    for entry in target.entries:
        if not entry.value.strip():
            findings.append(
                Finding("error", "empty-value", entry.line, entry.key, "Empty translation value")
            )

        if entry.key == "language.layoutDirection":
            normalized = entry.value.strip().lower()
            if normalized not in VALID_LAYOUT_DIRECTIONS:
                findings.append(
                    Finding(
                        "error",
                        "invalid-layout-direction",
                        entry.line,
                        entry.key,
                        f'language.layoutDirection must be "ltr" or "rtl" (got "{entry.value}")',
                    )
                )
            continue

        if entry.key == "language.code":
            trimmed = entry.value.strip()
            if trimmed != locale_code:
                findings.append(
                    Finding(
                        "error",
                        "language-code-mismatch",
                        entry.line,
                        entry.key,
                        f'language.code is "{trimmed}" but file is "strings.{locale_code}.toml"',
                    )
                )
            continue

        if entry.key == "language.name":
            continue

        source_value = source.value_for(entry.key)
        if (
            source_value is not None
            and source_value == entry.value
            and not entry.ignore_untranslated
            and entry.value.strip()
        ):
            findings.append(
                Finding(
                    "warning",
                    "untranslated",
                    entry.line,
                    entry.key,
                    "Value matches English source verbatim (add `# i18n-ignore` if intentional)",
                )
            )

        if (
            source_value is not None
            and entry.recorded_source_hash is not None
            and entry.recorded_source_hash != short_source_hash(source_value)
        ):
            findings.append(
                Finding(
                    "warning",
                    "source-changed",
                    entry.line,
                    entry.key,
                    "Source string has changed since translation; "
                    "retranslate then run --update-source-hashes",
                )
            )

    return LocaleReport(
        bundle_name=bundle_name,
        locale_code=locale_code,
        path=target.path,
        total_keys=len(target.entries),
        findings=findings,
    )


# --- Discovery -------------------------------------------------------------


@dataclass
class BundleTarget:
    name: str
    directory: Path
    source_path: Path
    source_code: str
    locales: list[tuple[str, Path]]  # (code, path)
    requires_builtin: bool


_BUILTIN_DIR = Path("Sources/GUIForCLICore/Resources/BuiltinStrings")


def _read_default_locale_code(bundle_root: Path) -> str:
    manifest_path = bundle_root / "manifest.json"
    if manifest_path.exists():
        try:
            data = jsonlib.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, jsonlib.JSONDecodeError):
            return "en"
        code = data.get("defaultLocalizationCode")
        if isinstance(code, str) and code.strip():
            return code.strip()
    return "en"


def _build_target(strings_dir: Path, *, requires_builtin: bool, bundle_root: Path) -> Optional[BundleTarget]:
    if not strings_dir.is_dir():
        return None
    source_code = "en" if requires_builtin else _read_default_locale_code(bundle_root)
    source_path = strings_dir / f"strings.{source_code}.toml"
    if not source_path.exists():
        sys.stderr.write(
            f"Source file {source_path} not found (expected for default locale {source_code!r}).\n"
        )
        return None
    locales: list[tuple[str, Path]] = []
    for entry in sorted(strings_dir.iterdir(), key=lambda p: p.name):
        name = entry.name
        if not (name.startswith("strings.") and name.endswith(".toml")):
            continue
        inner = name[len("strings.") : -len(".toml")]
        if inner == source_code:
            continue
        locales.append((inner, entry))
    bundle_name = "BuiltinStrings" if requires_builtin else strings_dir.parent.name
    return BundleTarget(
        name=bundle_name,
        directory=strings_dir,
        source_path=source_path,
        source_code=source_code,
        locales=locales,
        requires_builtin=requires_builtin,
    )


def discover_bundles(paths: list[str]) -> list[BundleTarget]:
    bundles: list[BundleTarget] = []
    cwd = Path.cwd()

    if not paths:
        builtin_dir = cwd / _BUILTIN_DIR
        if builtin_dir.is_dir():
            target = _build_target(
                builtin_dir, requires_builtin=True, bundle_root=builtin_dir.parent
            )
            if target is not None:
                bundles.append(target)
        examples = cwd / "Examples"
        if examples.is_dir():
            for entry in sorted(examples.iterdir(), key=lambda p: str(p)):
                if not entry.is_dir():
                    continue
                strings_dir = entry / "strings"
                target = _build_target(
                    strings_dir, requires_builtin=False, bundle_root=entry
                )
                if target is not None:
                    bundles.append(target)
        return bundles

    for raw in paths:
        p = Path(raw)
        if not p.exists():
            sys.stderr.write(f"Path does not exist: {raw}\n")
            continue
        if p.is_dir():
            # Direct path to a strings/ folder, a bundle folder, or the
            # BuiltinStrings folder (which has no parent manifest).
            if p.name == "strings" and (p.parent / "manifest.json").exists():
                strings_dir = p
                bundle_root = p.parent
                requires_builtin = False
            elif (p / "manifest.json").exists():
                strings_dir = p / "strings"
                bundle_root = p
                requires_builtin = False
            else:
                strings_dir = p
                bundle_root = p.parent
                requires_builtin = strings_dir.resolve().match(str(_BUILTIN_DIR.resolve())) or (
                    "BuiltinStrings" in strings_dir.parts
                )
            target = _build_target(
                strings_dir, requires_builtin=requires_builtin, bundle_root=bundle_root
            )
            if target is None:
                sys.stderr.write(f"Could not lint strings folder at {p}\n")
            else:
                bundles.append(target)
        else:
            # User pointed at a specific strings.<code>.toml file: treat its
            # parent folder as the strings directory.
            strings_dir = p.parent
            bundle_root = strings_dir.parent
            requires_builtin = "BuiltinStrings" in strings_dir.parts
            target = _build_target(
                strings_dir, requires_builtin=requires_builtin, bundle_root=bundle_root
            )
            if target is not None:
                bundles.append(target)

    return bundles


# --- Reporting -------------------------------------------------------------


_IS_TTY = sys.stdout.isatty()


def color(text: str, ansi: str) -> str:
    return f"\033[{ansi}m{text}\033[0m" if _IS_TTY else text


def print_text_report(
    bundles: list[tuple[BundleTarget, list[LocaleReport], list[Finding]]], strict: bool
) -> bool:
    had_error = False
    for bundle, locales, source_findings in bundles:
        print(color(f"=== {bundle.name} ({bundle.directory})", "1;36"))
        if source_findings:
            print(color(f"  source {bundle.source_path.name}:", "1"))
            for finding in source_findings:
                print_finding(finding, indent="    ")
                if finding.severity == "error" or strict:
                    had_error = True
        if not locales:
            print("  (no locale files found)")
            continue
        for report in locales:
            summary = (
                f"  [{report.locale_code}] {report.total_keys} keys, "
                f"{report.error_count} errors, {report.warning_count} warnings"
            )
            if report.error_count:
                colored_summary = color(summary, "31")
            elif report.warning_count:
                colored_summary = color(summary, "33")
            else:
                colored_summary = color(summary, "32")
            print(colored_summary)
            for finding in report.findings:
                print_finding(finding, indent="    ")
            if report.error_count:
                had_error = True
            if strict and report.warning_count:
                had_error = True
    return had_error


def print_finding(finding: Finding, indent: str) -> None:
    if finding.severity == "error":
        tag = color("error", "31")
    else:
        tag = color("warn ", "33")
    location = f":{finding.line}" if finding.line is not None else ""
    key_part = f" [{finding.key}]" if finding.key else ""
    print(f"{indent}{tag} {finding.code}{location}{key_part} — {finding.message}")


def emit_json(
    bundles: list[tuple[BundleTarget, list[LocaleReport], list[Finding]]], strict: bool
) -> bool:
    had_error = False
    bundles_payload: list[dict] = []
    for bundle, locales, source_findings in bundles:
        for finding in source_findings:
            if finding.severity == "error" or strict:
                had_error = True
        locales_payload: list[dict] = []
        for report in locales:
            if report.error_count:
                had_error = True
            if strict and report.warning_count:
                had_error = True
            locales_payload.append(
                {
                    "code": report.locale_code,
                    "path": str(report.path),
                    "totalKeys": report.total_keys,
                    "errors": report.error_count,
                    "warnings": report.warning_count,
                    "findings": [_finding_dict(f) for f in report.findings],
                }
            )
        bundles_payload.append(
            {
                "name": bundle.name,
                "path": str(bundle.directory),
                "source": str(bundle.source_path),
                "sourceFindings": [_finding_dict(f) for f in source_findings],
                "locales": locales_payload,
            }
        )
    payload = {"bundles": bundles_payload, "ok": not had_error}
    print(jsonlib.dumps(payload, indent=2, sort_keys=True))
    return had_error


def _finding_dict(finding: Finding) -> dict:
    out: dict = {"severity": finding.severity, "code": finding.code, "message": finding.message}
    if finding.line is not None:
        out["line"] = finding.line
    if finding.key is not None:
        out["key"] = finding.key
    return out


# --- Source-file checks ----------------------------------------------------


def lint_source(source: ParsedFile, requires_builtin: bool) -> list[Finding]:
    findings: list[Finding] = []
    for line, message in source.parse_errors:
        findings.append(Finding("error", "parse-error", line, None, message))
    for key, line, prev_line in source.duplicate_keys:
        findings.append(
            Finding(
                "error",
                "duplicate-key",
                line,
                key,
                f"Duplicate key (previously defined on line {prev_line})",
            )
        )
    keys = {e.key for e in source.entries}
    if requires_builtin:
        for required in BUILTIN_REQUIRED_KEYS:
            if required not in keys:
                findings.append(
                    Finding(
                        "error",
                        "missing-builtin-key",
                        None,
                        required,
                        "Source file is missing required built-in key",
                    )
                )
    for entry in source.entries:
        if not entry.value.strip():
            findings.append(
                Finding(
                    "error", "empty-value", entry.line, entry.key, "Empty value in source file"
                )
            )
        if entry.key == "language.layoutDirection":
            normalized = entry.value.strip().lower()
            if normalized not in VALID_LAYOUT_DIRECTIONS:
                findings.append(
                    Finding(
                        "error",
                        "invalid-layout-direction",
                        entry.line,
                        entry.key,
                        'language.layoutDirection must be "ltr" or "rtl"',
                    )
                )
    return findings


# --- Source hash -----------------------------------------------------------


def short_source_hash(value: str) -> str:
    """Return the first 8 hex chars of SHA-1(value)."""
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]


def update_source_hashes(source: ParsedFile, target_path: Path) -> int:
    """Rewrite target_path so each translatable line carries an
    `i18n-source-hash:<hex>` annotation matching the current source value.

    Returns the number of lines updated.
    """
    try:
        raw = target_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    original_ends_with_newline = raw.endswith("\n")
    lines = raw.split("\n")
    if original_ends_with_newline and lines and lines[-1] == "":
        lines.pop()

    updated = 0
    for idx, line in enumerate(lines):
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#"):
            continue
        eq = trimmed.find("=")
        if eq < 0:
            continue
        raw_key = trimmed[:eq].strip()
        key = unquote_key(raw_key)
        source_value = source.value_for(key)
        if source_value is None:
            continue
        rest = trimmed[eq + 1 :].strip()
        if rest.startswith('"""'):
            continue
        value_part, comment_part = split_value_and_comment(line)
        value_literal = value_part.strip()
        if not value_literal.endswith('"'):
            continue
        hash_hex = short_source_hash(source_value)
        new_comment = merge_source_hash(comment_part, hash_hex)
        # Drop trailing whitespace on the value portion before re-joining.
        value_without_trailing = value_part.rstrip(" \t")
        rebuilt = (
            value_without_trailing
            if not new_comment
            else f"{value_without_trailing}  {new_comment}"
        )
        if rebuilt != line:
            lines[idx] = rebuilt
            updated += 1

    joined = "\n".join(lines)
    if original_ends_with_newline:
        joined += "\n"
    target_path.write_text(joined, encoding="utf-8")
    return updated


def merge_source_hash(comment: str, hash_hex: str) -> str:
    """Merge or replace an `i18n-source-hash:` directive in the given comment."""
    trimmed = comment.strip()
    if not trimmed:
        return f"# i18n-source-hash:{hash_hex}"
    body = trimmed[1:].strip() if trimmed.startswith("#") else trimmed
    pieces = [p for p in body.split(" ") if p]
    kept = [p for p in pieces if not p.lower().startswith("i18n-source-hash:")]
    kept.append(f"i18n-source-hash:{hash_hex}")
    return "# " + " ".join(kept)


# --- Main ------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="lint-locales.py",
        description="Lints localization TOML files for GUI-for-CLI bundles.",
        epilog=(
            "PATH may be a bundle directory containing strings/, a strings folder, a "
            "strings.<code>.toml file, or omitted to auto-scan "
            "Sources/GUIForCLICore/Resources/BuiltinStrings/ plus Examples/*/strings/ "
            "relative to the current working directory.\n\n"
            "Annotate intentional verbatim reuse with a trailing comment:\n"
            '  "bundle.displayName" = "WGS Extract"  # i18n-ignore'
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings (untranslated values, extra keys) as errors.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit a machine-readable JSON report instead of plain text.",
    )
    parser.add_argument(
        "--update-source-hashes",
        action="store_true",
        help="Rewrite locale files in place, stamping each line with the current source hash.",
    )
    parser.add_argument(
        "paths", nargs="*", help="Bundle directories, strings folders, or strings.<code>.toml files."
    )
    args = parser.parse_args()

    bundles = discover_bundles(args.paths)
    if not bundles:
        sys.stderr.write(
            "No bundles found. Pass a bundle path or run from a directory with Examples/.\n"
        )
        return 2

    if args.update_source_hashes:
        total_updated = 0
        for bundle in bundles:
            source = parse_toml_file(bundle.source_path)
            for code, path in bundle.locales:
                count = update_source_hashes(source, path)
                if count:
                    print(f"{bundle.name}/{code}: updated {count} line(s)")
                    total_updated += count
        print(f"Updated {total_updated} line(s) total.")
        return 0

    bundle_results: list[tuple[BundleTarget, list[LocaleReport], list[Finding]]] = []
    for bundle in bundles:
        source = parse_toml_file(bundle.source_path)
        source_findings = lint_source(source, requires_builtin=bundle.requires_builtin)
        locale_reports: list[LocaleReport] = []
        for code, path in bundle.locales:
            target = parse_toml_file(path)
            locale_reports.append(
                lint_locale(
                    source,
                    target,
                    bundle.name,
                    code,
                    requires_builtin=bundle.requires_builtin,
                )
            )
        bundle_results.append((bundle, locale_reports, source_findings))

    if args.json:
        had_error = emit_json(bundle_results, args.strict)
    else:
        had_error = print_text_report(bundle_results, args.strict)
    return 1 if had_error else 0


if __name__ == "__main__":
    sys.exit(main())
