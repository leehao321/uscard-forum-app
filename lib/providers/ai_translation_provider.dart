import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_provider.dart';
import 'preferences_provider.dart';

/// 可选目标语言（代码 → 本语言显示名）。
const aiTranslationLanguages = <String, String>{
  'zh-CN': '简体中文',
  'zh-TW': '繁體中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'ru': 'Русский',
};

/// 偏好优先；未设置时跟随应用语言。
final aiTranslationTargetLanguageProvider = Provider<String>((ref) {
  final preferred = ref.watch(
    preferencesProvider.select((p) => p.aiTranslationTargetLanguage),
  );
  if (preferred != null && preferred.isNotEmpty) return preferred;
  final locale = ref.watch(localeProvider);
  final tag = locale?.toLanguageTag() ?? 'zh-CN';
  if (tag.startsWith('zh')) {
    return tag.contains('TW') || tag.contains('HK') || tag.contains('Hant')
        ? 'zh-TW'
        : 'zh-CN';
  }
  final short = tag.split('-').first;
  return aiTranslationLanguages.containsKey(short) ? short : 'en';
});

String aiTranslationLanguageLabel(String code) =>
    aiTranslationLanguages[code] ?? code;
