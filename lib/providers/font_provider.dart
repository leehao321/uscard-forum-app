import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/font_import_service.dart';

/// 已导入的字体列表（导入、删除后自动刷新）
final importedFontsProvider = Provider<List<ImportedFont>>((ref) {
  final notifier = FontImportService.instance.fonts;
  void onChanged() => ref.invalidateSelf();
  notifier.addListener(onChanged);
  ref.onDispose(() => notifier.removeListener(onChanged));
  return notifier.value;
});
