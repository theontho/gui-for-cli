part of '../main.dart';

extension _BundleHomePageStateTextDirection on _BundleHomePageState {
  TextDirection get _bundleTextDirection {
    final code =
        _bundleState.localizationCode ?? _manifest?.defaultLocalizationCode;
    return isRTLLanguageCode(code) ? TextDirection.rtl : TextDirection.ltr;
  }

  TextDirection get _terminalTextDirection =>
      _manifest?.terminalTextDirection == 'rtl'
          ? TextDirection.rtl
          : TextDirection.ltr;
}

bool isRTLLanguageCode(String? code) {
  final language = (code ?? '').split(RegExp('[-_]')).first.toLowerCase();
  return const {'ar', 'fa', 'he', 'ur'}.contains(language);
}
