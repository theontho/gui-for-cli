part of '../main.dart';

const _appStringTables = <String, Map<String, String>>{
  'en': {
    'dataSource.loading.message': 'Loading data source...',
    'dataSource.loading.semanticLabel': 'Loading data source',
  },
};

extension _BundleHomePageStateAppStrings on _BundleHomePageState {
  String _appString(String key) {
    final requestedCode =
        (_bundleState.localizationCode ?? _manifest?.defaultLocalizationCode)
            ?.toLowerCase();
    final requestedTable = requestedCode == null
        ? null
        : _appStringTables[requestedCode] ??
            _appStringTables[requestedCode.split(RegExp(r'[-_]')).first];
    return requestedTable?[key] ?? _appStringTables['en']![key] ?? key;
  }
}
