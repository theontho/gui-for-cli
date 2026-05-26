from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    from .macos_distribution_config import config_value, env_value
except ImportError:  # pragma: no cover - script execution path
    from macos_distribution_config import config_value, env_value


CODE_BUNDLE_SUFFIXES = {".app", ".appex", ".framework", ".xpc"}

CODE_FILE_SUFFIXES = {".dylib", ".so"}

MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf",
    b"\xbf\xba\xfe\xca",
}


def verify_codesign(path: Path) -> None:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path)], check=True)


def sign_app(path: Path, signing_identity: str) -> None:
    for nested_path in nested_code_paths(path):
        sign_code_path(nested_path, signing_identity)
    sign_code_path(path, signing_identity)


def nested_code_paths(app_path: Path) -> list[Path]:
    contents = app_path / "Contents"
    if not contents.exists():
        return []

    nested_bundles: set[Path] = set()
    nested_files: set[Path] = set()
    for candidate in contents.rglob("*"):
        if candidate == app_path:
            continue
        if candidate.is_dir() and candidate.suffix in CODE_BUNDLE_SUFFIXES:
            nested_bundles.add(candidate)
            continue
        if candidate.is_file() and is_signable_code_file(candidate):
            nested_files.add(candidate)

    ordered = sorted(nested_bundles | nested_files, key=lambda candidate: len(candidate.parts), reverse=True)
    return ordered


def is_signable_code_file(path: Path) -> bool:
    if path.suffix in CODE_FILE_SUFFIXES:
        return True
    try:
        with path.open("rb") as handle:
            return handle.read(4) in MACHO_MAGICS
    except OSError:
        return False


def sign_code_path(path: Path, signing_identity: str) -> None:
    subprocess.run(
        [
            "codesign",
            "--force",
            "--sign",
            signing_identity,
            "--options",
            "runtime",
            "--timestamp",
            str(path),
        ],
        check=True,
    )


def ad_hoc_sign_app(path: Path) -> None:
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(path)], check=True)


def sign_dmg(path: Path, signing_identity: str) -> None:
    subprocess.run(["codesign", "--force", "--sign", signing_identity, "--timestamp", str(path)], check=True)
    subprocess.run(["codesign", "--verify", "--verbose=2", str(path)], check=True)


def assess_spctl(path: Path, assessment_type: str) -> None:
    subprocess.run(["spctl", "--assess", "--verbose=4", "--type", assessment_type, str(path)], check=True)


def notarize_app(path: Path) -> None:
    archive = path.with_suffix(".notary.zip")
    archive.unlink(missing_ok=True)
    try:
        subprocess.run(
            ["ditto", "-c", "-k", "--keepParent", path.name, archive.name],
            cwd=path.parent,
            check=True,
        )
        notarize(archive)
    finally:
        archive.unlink(missing_ok=True)


def notarytool_auth_args() -> list[str]:
    profile = env_value("APPLE_NOTARY_PROFILE") or config_value("apple", "signing", "notary_profile")
    if profile:
        return ["--keychain-profile", profile]

    api_key_path = env_value("APPLE_API_KEY_PATH")
    api_key_id = env_value("APPLE_API_KEY_ID")
    api_issuer = env_value("APPLE_API_ISSUER")
    if api_key_path and api_key_id and api_issuer:
        return ["--key", api_key_path, "--key-id", api_key_id, "--issuer", api_issuer]

    apple_id = env_value("APPLE_ID") or config_value("apple", "signing", "apple_id")
    password = env_value("APPLE_APP_SPECIFIC_PASSWORD", "APPLE_PASSWORD") or config_value(
        "apple", "signing", "app_specific_password"
    )
    team_id = (
        env_value("APPLE_TEAM_ID", "APPLE_DEVELOPMENT_TEAM")
        or config_value("apple", "signing", "team_id")
        or config_value("apple", "signing", "development_team")
    )
    if apple_id and password and team_id:
        raise RuntimeError(
            "notarytool_auth_args refuses to pass app-specific passwords on the command line. "
            "Run `xcrun notarytool store-credentials` and set APPLE_NOTARY_PROFILE or "
            "apple.signing.notary_profile instead."
        )

    return []


def notarize(path: Path) -> None:
    auth_args = notarytool_auth_args()
    if not auth_args:
        return
    result = subprocess.run(
        ["xcrun", "notarytool", "submit", str(path), "--wait", *auth_args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)

    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    statuses = re.findall(r"^\s*status:\s*([A-Za-z]+)", output, re.MULTILINE)
    final_status = statuses[-1] if statuses else ""
    if final_status and final_status != "Accepted":
        job_id = notary_submission_id(output)
        if job_id:
            print_notary_log(job_id, auth_args)
        raise RuntimeError(f"Apple notarization failed for {path}: {final_status}")


def notary_submission_id(output: str) -> str:
    match = re.search(
        r"id:\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})",
        output,
    )
    return match.group(1) if match else ""


def print_notary_log(job_id: str, auth_args: list[str]) -> None:
    result = subprocess.run(
        ["xcrun", "notarytool", "log", job_id, *auth_args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)


def staple(path: Path) -> None:
    subprocess.run(["xcrun", "stapler", "staple", "-v", str(path)], check=True)


def validate_staple(path: Path) -> None:
    subprocess.run(["xcrun", "stapler", "validate", "-v", str(path)], check=True)
