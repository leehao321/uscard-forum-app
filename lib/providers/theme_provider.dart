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

  /// 强调色预设：只替换 brand/primary 与 brand/button
  final AccentPreset accent;

  const ThemeState({
    required this.mode,
    this.fontFamily = AppFontFamily.system,
    this.accent = AccentPreset.meika,
  });

  /// 获取实际用于 ThemeData 的 fontFamily 字符串
  String? get fontFamilyName {
    switch (fontFamily) {
      case AppFontFamily.miSans:
        return 'MiSans';
      case AppFontFamily.system:
        return null;
    }
  }

  ThemeState copyWith({
    ThemeMode? mode,
    AppFontFamily? fontFamily,
    AccentPreset? accent,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      fontFamily: fontFamily ?? this.fontFamily,
      accent: accent ?? this.accent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeState &&
      other.mode == mode &&
      other.fontFamily == fontFamily &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(mode, fontFamily, accent);
}

/// App Theme Notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = 'theme_mode';
  static const String _fontFamilyKey = 'font_family';
  static const String _accentPresetKey = 'accent_preset';

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

  Future<void> setFontFamily(AppFontFamily fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily);
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
