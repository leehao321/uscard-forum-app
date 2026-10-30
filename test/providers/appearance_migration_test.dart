import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/appearance_provider.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 0.4.0 升级迁移（计划 §10.3）：旧主题偏好被忽略、旧正文字号折算成字号档。

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// 0.3.x 外观页能写进去的旧键（调色板、自定义取色、中性 / 纯黑 / 透明、
/// 背景图、M3E 开关等）
const _legacyThemePrefs = <String, Object>{
  'theme_mode': 'dark',
  'font_family': 'miSans',
  'theme_neutral': true,
  'theme_black': true,
  'theme_transparent': true,
  'accent_source': 'custom',
  'palette_id': 'ocean',
  'seed_color': 0xFF123456,
  'scheme_variant': 'vibrant',
  'custom_colors': ['4279383126'],
  'm3e_enabled': false,
  'bg_image_path': '/nonexistent/bg.jpg',
  'bg_blur': 12.0,
  'use_dynamic_color': true,
};

void main() {
  group('主题偏好', () {
    test('旧键被忽略：只保留主题模式和字体，强调色回到美卡绿', () async {
      final prefs = await _prefs(_legacyThemePrefs);
      final state = ThemeNotifier(prefs).state;
      expect(
        state,
        const ThemeState(
          mode: ThemeMode.dark,
          fontFamily: AppFontFamily.miSans,
          accent: AccentPreset.meika,
        ),
      );
    });

    test('旧键不删（降级回旧版还能用）', () async {
      final prefs = await _prefs(_legacyThemePrefs);
      final notifier = ThemeNotifier(prefs);
      await notifier.setAccent(AccentPreset.navy);
      await notifier.setThemeMode(ThemeMode.light);
      for (final key in _legacyThemePrefs.keys) {
        expect(prefs.containsKey(key), isTrue, reason: key);
      }
    });

    test('强调色写入新键并能读回', () async {
      final prefs = await _prefs({});
      await ThemeNotifier(prefs).setAccent(AccentPreset.wisteria);
      expect(prefs.getString('accent_preset'), 'wisteria');
      expect(ThemeNotifier(prefs).state.accent, AccentPreset.wisteria);
    });

    test('新键里的未知值回到默认', () async {
      final prefs = await _prefs({'accent_preset': 'rainbow'});
      expect(ThemeNotifier(prefs).state.accent, AccentPreset.meika);
    });
  });

  group('外观档位', () {
    test('全新安装：五个档位都是标准', () async {
      final prefs = await _prefs({});
      expect(AppearanceNotifier(prefs).state, const AppearanceTiers());
    });

    for (final (legacy, tier) in [
      (0.8, FontTier.small),
      (1.0, FontTier.standard),
      (1.1, FontTier.large),
      (1.4, FontTier.extraLarge),
    ]) {
      test('旧正文字号 $legacy → $tier', () async {
        final prefs = await _prefs({'pref_content_font_scale': legacy});
        expect(AppearanceNotifier(prefs).state.font, tier);
      });
    }

    test('已经存过字号档时以新键为准', () async {
      final prefs = await _prefs({
        'pref_content_font_scale': 1.4,
        AppearanceNotifier.fontTierKey: 'small',
      });
      expect(AppearanceNotifier(prefs).state.font, FontTier.small);
    });

    test('写入后能原样读回；应用预设时保留半透明档', () async {
      final prefs = await _prefs({});
      final notifier = AppearanceNotifier(prefs);
      const custom = AppearanceTiers(
        font: FontTier.large,
        lineHeight: LineHeightTier.relaxed,
        density: DensityTier.compact,
        radius: RadiusTier.small,
        translucency: TranslucencyTier.off,
      );
      await notifier.setTiers(custom);
      expect(AppearanceNotifier(prefs).state, custom);

      await notifier.applyPreset(AppearancePreset.comfortable);
      expect(
        notifier.state,
        AppearancePreset.comfortable.tiers.copyWith(
          translucency: TranslucencyTier.off,
        ),
      );
    });

    test('弹窗模糊固定关闭（v2 遮罩不模糊），旧值不删', () async {
      final prefs = await _prefs({'pref_dialog_blur': true});
      expect(PreferencesNotifier(prefs).state.dialogBlur, isFalse);
      expect(prefs.getBool('pref_dialog_blur'), isTrue);
    });

    test('阅读页不再乘旧正文字号（避免和字号档叠乘）', () async {
      final prefs = await _prefs({'pref_content_font_scale': 1.3});
      expect(PreferencesNotifier(prefs).state.contentFontScale, 1.0);
      // 旧值留着，降级回旧版还能用
      expect(prefs.getDouble('pref_content_font_scale'), 1.3);
    });
  });
}
