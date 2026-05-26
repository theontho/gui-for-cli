from __future__ import annotations

import os
import subprocess

from tools.devconfig import get_path


def env_value(*names: str) -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return ""


def config_value(*path: str) -> str:
    value = get_path(*path, default="")
    return value if isinstance(value, str) else ""


def distribution_team_id() -> str:
    return (
        env_value("APPLE_DEVELOPMENT_TEAM", "APPLE_TEAM_ID")
        or config_value("apple", "signing", "development_team")
        or config_value("apple", "signing", "team_id")
    )


def distribution_signing_identity() -> str:
    return env_value("APPLE_SIGNING_IDENTITY") or config_value("apple", "signing", "signing_identity")


def available_developer_id_identities() -> list[tuple[str, str]]:
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    identities: list[tuple[str, str]] = []
    for line in result.stdout.splitlines():
        marker = '"Developer ID Application:'
        if marker not in line:
            continue
        parts = line.split()
        identity_hash = parts[1] if len(parts) > 1 else ""
        try:
            name = line.split('"', 2)[1]
        except IndexError:
            continue
        identities.append((identity_hash, name))
    return identities


def detected_developer_id_identity(team_id: str) -> str:
    return select_detected_developer_id_identity(team_id, available_developer_id_identities())


def select_detected_developer_id_identity(team_id: str, identities: list[tuple[str, str]]) -> str:
    candidates = [name for _, name in identities]
    if team_id:
        team_candidates = [candidate for candidate in candidates if f"({team_id})" in candidate]
        if team_candidates:
            return team_candidates[0]
        raise RuntimeError(f"No Developer ID Application identity was found for Apple team {team_id}.")
    return candidates[0] if candidates else ""


def resolved_signing_identity() -> str:
    return select_signing_identity(
        team_id=distribution_team_id(),
        configured_identity=distribution_signing_identity(),
        identities=available_developer_id_identities(),
    )


def select_signing_identity(
    *,
    team_id: str,
    configured_identity: str,
    identities: list[tuple[str, str]],
) -> str:
    if configured_identity:
        for identity_hash, identity_name in identities:
            if configured_identity in {identity_hash, identity_name}:
                return configured_identity
        raise RuntimeError(
            f"Configured signing identity was not found in the keychain: {configured_identity}. "
            "Import a Developer ID Application .p12 or update APPLE_SIGNING_IDENTITY."
        )
    return select_detected_developer_id_identity(team_id, identities)


def should_sign() -> bool:
    return bool(distribution_team_id() or distribution_signing_identity())


def should_notarize() -> bool:
    try:
        from .macos_distribution_signing import notarytool_auth_args
    except ImportError:  # pragma: no cover - script execution path
        from macos_distribution_signing import notarytool_auth_args

    return bool(notarytool_auth_args())


def require_notarization() -> bool:
    for env_name in ("PACKAGE_REQUIRE_NOTARIZATION", "REQUIRE_NOTARIZATION"):
        env_setting = os.environ.get(env_name)
        if env_setting:
            return parse_bool_setting(env_setting, env_name)
    return parse_bool_setting(
        get_path("apple", "signing", "require_notarization", default=False),
        "apple.signing.require_notarization",
    )


def parse_bool_setting(value: object, name: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and value in {0, 1}:
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"", "0", "false", "no", "off"}:
            return False
    raise ValueError(f"{name} must be a boolean value: true/false, 1/0, yes/no, or on/off")
