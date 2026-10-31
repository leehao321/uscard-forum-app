import 'package:common_ui/common_ui.dart' show AccentPreset;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内置字体选项
enum AppFontFamily {
  /// 跟随系统默认字体
  system,

  /// 内置 MiSans 字体
  miSans,
}

/// App Theme State
///
/// 0.4.0 起颜色只有 v2 的 11 色（见 common_ui 的 AppColors），这里只留
/// 主题模式、字体和强调色四选一。旧版的调色板、自定义取色、动态取色、
/// 中性 / 纯黑 / 透明、背景图、M3E 开关等偏好键不再读取，也不删除
/// （降级回旧版本时还能用）。
@immutable
class ThemeState {
  /// 主题模式：浅色 / 深色 / 跟随系统
  final ThemeMode mode;

  final AppFontFamily fontFamily;

  /// 导入字体做界面字体时的 family 名（0.4.0 外观 › 字体）；null = 用 [fontFamily]
  final String? importedUiFamily;

  /// 正文字体：null = 跟随界面字体；否则是 family 名（MiSans 或导入字体）
  final String? bodyFontFamily;

  /// 强调色预设：只替换 brand/primary 与 brand/button
  final AccentPreset accent;

  const ThemeState({
    required this.mode,
    this.fontFamily = AppFontFamily.system,
    this.importedUiFamily,
    this.bodyFontFamily,
    this.accent = AccentPreset.meika,
  });

  /// 获取实际用于 ThemeData 的 fontFamily 字符串
  String? get fontFamilyName {
    if (importedUiFamily != null) return importedUiFamily;
    switch (fontFamily) {
      case AppFontFamily.miSans:
        return 'MiSans';
      case AppFontFamily.system:
        return null;
    }
  }

  /// 正文实际用的字体（供 token 使用）
  String? get bodyFontFamilyName => bodyFontFamily;

  /// 保留 [importedUiFamily] / [bodyFontFamily]；要改它们用 [withImportedUi] /
  /// [withBodyFont]（可以置空）。
  ThemeState copyWith({
    ThemeMode? mode,
    AppFontFamily? fontFamily,
    AccentPreset? accent,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      fontFamily: fontFamily ?? this.fontFamily,
      importedUiFamily: importedUiFamily,
      bodyFontFamily: bodyFontFamily,
      accent: accent ?? this.accent,
    );
  }

  ThemeState withImportedUi(String? family) => ThemeState(
    mode: mode,
    fontFamily: fontFamily,
    importedUiFamily: family,
    bodyFontFamily: bodyFontFamily,
    accent: accent,
  );

  ThemeState withBodyFont(String? family) => ThemeState(
    mode: mode,
    fontFamily: fontFamily,
    importedUiFamily: importedUiFamily,
    bodyFontFamily: family,
    accent: accent,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeState &&
      other.mode == mode &&
      other.fontFamily == fontFamily &&
      other.importedUiFamily == importedUiFamily &&
      other.bodyFontFamily == bodyFontFamily &&
      other.accent == accent;

  @override
  int get hashCode =>
      Object.hash(mode, fontFamily, importedUiFamily, bodyFontFamily, accent);
}

/// App Theme Notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = 'theme_mode';
  static const String _fontFamilyKey = 'font_family';
  static const String _accentPresetKey = 'accent_preset';
  static const String _importedUiFamilyKey = 'font_ui_imported_family';
  static const String _bodyFontFamilyKey = 'font_body_family';

  final SharedPreferences _prefs;

  ThemeNotifier(this._prefs) : super(_loadTheme(_prefs));

  static ThemeState _loadTheme(SharedPreferences prefs) {
    final savedMode = prefs.getString(_themeModeKey);
    ThemeMode mode = ThemeMode.system;
    if (savedMode == 'light') {
      mode = ThemeMode.light;
    } else if (savedMode == 'dark') {
      mode = ThemeMode.dark;
    }

    final fontFamily = prefs.getString(_fontFamilyKey) == 'miSans'
        ? AppFontFamily.miSans
        : AppFontFamily.system;

    return ThemeState(
      mode: mode,
      fontFamily: fontFamily,
      importedUiFamily: prefs.getString(_importedUiFamilyKey),
      bodyFontFamily: prefs.getString(_bodyFontFamilyKey),
      accent: AccentPreset.fromName(prefs.getString(_accentPresetKey)),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    String value = 'system';
    if (mode == ThemeMode.light) {
      value = 'light';
    } else if (mode == ThemeMode.dark) {
      value = 'dark';
    }
    await _prefs.setString(_themeModeKey, value);
  }

  Future<void> setAccent(AccentPreset accent) async {
    state = state.copyWith(accent: accent);
    await _prefs.setString(_accentPresetKey, accent.name);
  }

  /// 界面字体选导入的字体（null = 回到 [setFontFamily] 选的内置字体）
  Future<void> setImportedUiFamily(String? family) async {
    state = state.withImportedUi(family);
    if (family == null) {
      await _prefs.remove(_importedUiFamilyKey);
    } else {
      await _prefs.setString(_importedUiFamilyKey, family);
    }
  }

  /// 正文字体（null = 跟随界面字体）
  Future<void> setBodyFontFamily(String? family) async {
    state = state.withBodyFont(family);
    if (family == null) {
      await _prefs.remove(_bodyFontFamilyKey);
    } else {
      await _prefs.setString(_bodyFontFamilyKey, family);
    }
  }

  Future<void> setFontFamily(AppFontFamily fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily).withImportedUi(null);
    await _prefs.remove(_importedUiFamilyKey);
    switch (fontFamily) {
      case AppFontFamily.miSans:
        await _prefs.setString(_fontFamilyKey, 'miSans');
      case AppFontFamily.system:
        await _prefs.setString(_fontFamilyKey, 'system');
    }
  }
}

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

/// Theme Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});
