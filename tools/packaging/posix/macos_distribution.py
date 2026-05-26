from __future__ import annotations

try:
    from .macos_distribution_build import build_swift_distribution, signed_swift_distribution, unsigned_swift_distribution
    from .macos_distribution_config import (
        available_developer_id_identities,
        config_value,
        detected_developer_id_identity,
        distribution_signing_identity,
        distribution_team_id,
        env_value,
        parse_bool_setting,
        require_notarization,
        resolved_signing_identity,
        select_detected_developer_id_identity,
        select_signing_identity,
        should_notarize,
        should_sign,
    )
    from .macos_distribution_dmg import (
        FONT_5X7,
        configure_dmg_window,
        create_dmg,
        distribution_dmg_name,
        dmg_background_enabled,
        write_dmg_background,
        write_png,
    )
    from .macos_distribution_signing import (
        CODE_BUNDLE_SUFFIXES,
        CODE_FILE_SUFFIXES,
        MACHO_MAGICS,
        ad_hoc_sign_app,
        assess_spctl,
        is_signable_code_file,
        nested_code_paths,
        notarize,
        notarize_app,
        notary_submission_id,
        notarytool_auth_args,
        print_notary_log,
        sign_app,
        sign_code_path,
        sign_dmg,
        staple,
        validate_staple,
        verify_codesign,
    )
except ImportError:  # pragma: no cover - script execution path
    from macos_distribution_build import build_swift_distribution, signed_swift_distribution, unsigned_swift_distribution
    from macos_distribution_config import (
        available_developer_id_identities,
        config_value,
        detected_developer_id_identity,
        distribution_signing_identity,
        distribution_team_id,
        env_value,
        parse_bool_setting,
        require_notarization,
        resolved_signing_identity,
        select_detected_developer_id_identity,
        select_signing_identity,
        should_notarize,
        should_sign,
    )
    from macos_distribution_dmg import (
        FONT_5X7,
        configure_dmg_window,
        create_dmg,
        distribution_dmg_name,
        dmg_background_enabled,
        write_dmg_background,
        write_png,
    )
    from macos_distribution_signing import (
        CODE_BUNDLE_SUFFIXES,
        CODE_FILE_SUFFIXES,
        MACHO_MAGICS,
        ad_hoc_sign_app,
        assess_spctl,
        is_signable_code_file,
        nested_code_paths,
        notarize,
        notarize_app,
        notary_submission_id,
        notarytool_auth_args,
        print_notary_log,
        sign_app,
        sign_code_path,
        sign_dmg,
        staple,
        validate_staple,
        verify_codesign,
    )
