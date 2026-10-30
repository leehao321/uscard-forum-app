import 'package:common_ui/common_ui.dart'
    show
        AppearancePreset,
        AppearanceTiers,
        DensityTier,
        FontTier,
        LineHeightTier,
        RadiusTier,
        TranslucencyTier;
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// 外观 › 微调的五个档位（0.4.0 计划 §3.6）。设置界面在 M8 做。
class AppearanceNotifier extends StateNotifier<AppearanceTiers> {
  static const String fontTierKey = 'appearance_font_tier';
  static const String lineHeightTierKey = 'appearance_line_height_tier';
  static const String densityTierKey = 'appearance_density_tier';
  static const String radiusTierKey = 'appearance_radius_tier';
  static const String translucencyTierKey = 'appearance_translucency_tier';

  /// 旧版阅读设置里的正文字号（0.4.0 前），只读来迁移成字号档
  static const String legacyContentFontScaleKey = 'pref_content_font_scale';

  final SharedPreferences _prefs;

  AppearanceNotifier(this._prefs) : super(load(_prefs));

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.asNameMap()[name] ?? fallback;

  static AppearanceTiers load(SharedPreferences prefs) {
    final savedFont = prefs.getString(fontTierKey);
    final legacyScale = prefs.getDouble(legacyContentFontScaleKey);
    final font = savedFont != null
        ? _byName(FontTier.values, savedFont, FontTier.standard)
        : legacyScale != null
        ? FontTier.fromLegacyScale(legacyScale)
        : FontTier.standard;
    return AppearanceTiers(
      font: font,
      lineHeight: _byName(
        LineHeightTier.values,
        prefs.getString(lineHeightTierKey),
        LineHeightTier.standard,
      ),
      density: _byName(
        DensityTier.values,
        prefs.getString(densityTierKey),
        DensityTier.standard,
      ),
      radius: _byName(
        RadiusTier.values,
        prefs.getString(radiusTierKey),
        RadiusTier.standard,
      ),
      translucency: _byName(
        TranslucencyTier.values,
        prefs.getString(translucencyTierKey),
        TranslucencyTier.standard,
      ),
    );
  }

  Future<void> setTiers(AppearanceTiers tiers) async {
    state = tiers;
    await Future.wait([
      _prefs.setString(fontTierKey, tiers.font.name),
      _prefs.setString(lineHeightTierKey, tiers.lineHeight.name),
      _prefs.setString(densityTierKey, tiers.density.name),
      _prefs.setString(radiusTierKey, tiers.radius.name),
      _prefs.setString(translucencyTierKey, tiers.translucency.name),
    ]);
  }

  Future<void> applyPreset(AppearancePreset preset) =>
      setTiers(preset.tiers.copyWith(translucency: state.translucency));
}

final appearanceProvider =
    StateNotifierProvider<AppearanceNotifier, AppearanceTiers>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return AppearanceNotifier(prefs);
    });
