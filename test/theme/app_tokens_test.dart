import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// v2 token 的取值逐项对照设计说明 §2 / §6（docs/uscard/design-v2.md），
// 外加对比度、相等性、插值与外观档位的行为。

void main() {
  group('颜色（设计说明 §2.1）', () {
    test('浅色 11 色', () {
      const c = AppColors.light;
      expect(c.brandPrimary, const Color(0xFF173E31));
      expect(c.brandButton, const Color(0xFF2E6F55));
      expect(c.onBrandButton, const Color(0xFFFFFFFF));
      expect(c.textPrimary, const Color(0xFF1C1C1E));
      expect(c.textMeta, const Color(0xFF636366));
      expect(c.textDestructive, const Color(0xFFD70015));
      expect(c.surfacePage, const Color(0xFFFFFFFF));
      expect(c.surfaceGrouped, const Color(0xFFF2F2F7));
      expect(c.surfaceElevated, const Color(0xFFF2F2F7));
      expect(c.separator, const Color(0xFFC6C6C8));
      expect(c.quoteRule, const Color(0xFFC7C7CC));
      expect(c.avatarFill, const Color(0xFFE5E5EA));
    });

    test('深色 11 色（brand/primary 以 Figma 的 #86C5A4 为准）', () {
      const c = AppColors.dark;
      expect(c.brandPrimary, const Color(0xFF86C5A4));
      expect(c.brandButton, const Color(0xFF2E6F55));
      expect(c.textPrimary, const Color(0xFFFFFFFF));
      expect(c.textMeta, const Color(0xFF98989F));
      expect(c.textDestructive, const Color(0xFFFF453A));
      expect(c.surfacePage, const Color(0xFF000000));
      expect(c.surfaceGrouped, const Color(0xFF1C1C1E));
      expect(c.surfaceElevated, const Color(0xFF2C2C2E));
      expect(c.separator, const Color(0xFF38383A));
      expect(c.quoteRule, const Color(0xFF48484A));
      expect(c.avatarFill, const Color(0xFF3A3A3C));
    });

    test('强调色（§6）只换 brand/primary 与 brand/button', () {
      const expected = {
        AccentPreset.meika: (0xFF173E31, 0xFF86C5A4, 0xFF2E6F55),
        AccentPreset.navy: (0xFF1F3A5F, 0xFF8FB3E0, 0xFF2F5A8A),
        AccentPreset.graphite: (0xFF3A3A3C, 0xFFC7C7CC, 0xFF48484A),
        AccentPreset.wisteria: (0xFF4B3B6B, 0xFFB9A6E0, 0xFF5E4B8A),
      };
      for (final MapEntry(key: preset, value: (light, dark, button))
          in expected.entries) {
        final l = AppColors.resolve(Brightness.light, preset);
        final d = AppColors.resolve(Brightness.dark, preset);
        expect(l.brandPrimary, Color(light), reason: '$preset 浅');
        expect(d.brandPrimary, Color(dark), reason: '$preset 深');
        expect(l.brandButton, Color(button), reason: '$preset 按钮');
        expect(d.brandButton, Color(button), reason: '$preset 按钮');
        // 其余 9 色不变
        expect(
          l.copyWith(
            brandPrimary: AppColors.light.brandPrimary,
            brandButton: AppColors.light.brandButton,
          ),
          AppColors.light,
        );
        expect(
          d.copyWith(
            brandPrimary: AppColors.dark.brandPrimary,
            brandButton: AppColors.dark.brandButton,
          ),
          AppColors.dark,
        );
      }
    });

    test('AccentPreset.fromName：未知值回到美卡绿', () {
      expect(AccentPreset.fromName('navy'), AccentPreset.navy);
      expect(AccentPreset.fromName(null), AccentPreset.meika);
      expect(AccentPreset.fromName('bogus'), AccentPreset.meika);
    });
  });

  group('对比度（WCAG AA ≥ 4.5）', () {
    for (final b in Brightness.values) {
      test('${b.name}：正文与元信息在三种底色上', () {
        final c = AppColors.resolve(b, AccentPreset.meika);
        for (final bg in [c.surfacePage, c.surfaceGrouped, c.surfaceElevated]) {
          expect(
            AppColors.contrastRatio(c.textPrimary, bg),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            AppColors.contrastRatio(c.textMeta, bg),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('${b.name}：四组强调色的主色在页面底上、白字在按钮上', () {
        for (final preset in AccentPreset.values) {
          final c = AppColors.resolve(b, preset);
          expect(
            AppColors.contrastRatio(c.brandPrimary, c.surfacePage),
            greaterThanOrEqualTo(4.5),
            reason: '$preset 主色',
          );
          expect(
            AppColors.contrastRatio(c.onBrandButton, c.brandButton),
            greaterThanOrEqualTo(4.5),
            reason: '$preset 按钮',
          );
        }
      });
    }

    test('contrastRatio：黑白 21、同色 1', () {
      expect(
        AppColors.contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        AppColors.contrastRatio(const Color(0xFF777777), const Color(0xFF777777)),
        closeTo(1, 0.0001),
      );
    });
  });

  group('字号（§2.3：22 / 17 / 13 / 11，只有 w400 与 w600）', () {
    const t = AppTextStyles();

    test('各档字号、字重、行高', () {
      void check(TextStyle s, double size, FontWeight w, double lineHeight) {
        expect(s.fontSize, size);
        expect(s.fontWeight, w);
        expect(s.height! * size, closeTo(lineHeight, 0.001));
        expect(s.color, isNull, reason: '颜色由 AppColors 给');
      }

      check(t.title, 22, FontWeight.w600, 26);
      check(t.headline, 17, FontWeight.w600, 24);
      check(t.body, 17, FontWeight.w400, 17 * 1.75);
      check(t.control, 17, FontWeight.w400, 20);
      check(t.meta, 13, FontWeight.w400, 16);
      check(t.metaStrong, 13, FontWeight.w600, 16);
      check(t.caption, 11, FontWeight.w400, 13);
      check(t.mono, 11, FontWeight.w400, 16);
      check(t.monoUrl, 13, FontWeight.w400, 16);
    });

    test('正文行高跟行高档走，其他档不变', () {
      for (final tier in LineHeightTier.values) {
        final s = AppTextStyles.forTier(tier);
        expect(s.body.height, tier.height);
        expect(s.control, t.control);
      }
      expect(LineHeightTier.values.map((e) => e.height), [1.5, 1.75, 2.0]);
    });

    test('映射到 TextTheme（计划 §3.3）且不带字间距', () {
      final theme = t.applyTo(Typography.material2021().black);
      expect(theme.titleLarge!.fontSize, 22);
      expect(theme.headlineSmall!.fontSize, 22);
      expect(theme.titleMedium!.fontSize, 17);
      expect(theme.titleMedium!.fontWeight, FontWeight.w600);
      expect(theme.bodyLarge!.fontSize, 17);
      expect(theme.bodyMedium!.fontSize, 17);
      expect(theme.labelLarge!.fontSize, 17);
      expect(theme.bodySmall!.fontSize, 13);
      expect(theme.labelMedium!.fontSize, 13);
      expect(theme.titleSmall!.fontWeight, FontWeight.w600);
      expect(theme.labelSmall!.fontSize, 11);
      for (final s in [theme.bodyMedium, theme.titleMedium, theme.labelSmall]) {
        expect(s!.letterSpacing, 0);
      }
    });
  });

  group('间距、尺寸、圆角', () {
    test('4/8 网格与固定尺寸（§2.4、计划 §3.4）', () {
      expect(
        [
          AppSpace.xxs,
          AppSpace.xs,
          AppSpace.s,
          AppSpace.m,
          AppSpace.l,
          AppSpace.xl,
          AppSpace.xxl,
          AppSpace.x32,
          AppSpace.x40,
        ],
        [2, 4, 8, 12, 16, 20, 24, 32, 40],
      );
      expect(AppSpace.pageMargin, 20);
      expect(AppSpace.hairline, 0.5);
      expect(AppSize.hit, 44);
      expect(AppSize.row48, 48);
      expect(AppSize.toolbar, 64);
      expect(AppSize.readableMaxWidth, 640);
      expect([AppSize.avatarS, AppSize.avatarM, AppSize.avatarL], [34, 40, 64]);
      expect([AppSize.iconL, AppSize.iconM, AppSize.iconS], [24, 20, 16]);
      expect(AppSize.dialogWidth, 320);
      expect(AppSize.swipeAction, 72);
    });

    test('圆角（§6）与圆角档 ×0.75 / 1 / 1.25', () {
      const r = AppRadius();
      expect(
        [r.sheet, r.card, r.field, r.table, r.tag, r.handle, r.bar],
        [16, 12, 10, 8, 4, 3, 2],
      );
      final small = AppRadius.forTier(RadiusTier.small);
      final large = AppRadius.forTier(RadiusTier.large);
      expect(small.card, 9);
      expect(large.sheet, 20);
      // 胶囊和 App 图标不随档位变化
      expect(AppRadius.pill(58), 29);
      expect(AppRadius.appIcon96, 22);
      expect(AppRadius.appIcon64, 16);
    });
  });

  group('材质（§2.2）', () {
    test('标准档：浅色工具栏 94% 灰白、胶囊 62% 白；深色胶囊不透明', () {
      final light = AppMaterials.resolve(
        Brightness.light,
        AppColors.light,
        TranslucencyTier.standard,
      );
      expect(light.barFill, const Color(0xF0F9F9F9));
      expect(light.barBlur, 10);
      expect(light.capsuleFill, const Color(0x9EFFFFFF));
      expect(light.capsuleBlur, 12);
      expect(light.sheetFill, AppColors.light.surfacePage);

      final dark = AppMaterials.resolve(
        Brightness.dark,
        AppColors.dark,
        TranslucencyTier.standard,
      );
      expect(dark.barFill, const Color(0xF0000000));
      expect(dark.capsuleFill, const Color(0xFF1C1C1E));
      expect(dark.sheetFill, AppColors.dark.surfaceGrouped);
    });

    test('关：不透明、不模糊；强：半透明的再降 0.1', () {
      final off = AppMaterials.resolve(
        Brightness.light,
        AppColors.light,
        TranslucencyTier.off,
      );
      expect(off.barFill.a, 1);
      expect(off.capsuleFill.a, 1);
      expect(off.barBlurred, isFalse);
      expect(off.capsuleBlurred, isFalse);

      final strong = AppMaterials.resolve(
        Brightness.light,
        AppColors.light,
        TranslucencyTier.strong,
      );
      expect(strong.barFill.a, closeTo(0xF0 / 255 - 0.1, 0.01));
      expect(strong.capsuleFill.a, closeTo(0x9E / 255 - 0.1, 0.01));

      final strongDark = AppMaterials.resolve(
        Brightness.dark,
        AppColors.dark,
        TranslucencyTier.strong,
      );
      expect(strongDark.capsuleFill.a, 1, reason: '深色胶囊本来就不透明');
    });

    test('阴影与遮罩', () {
      expect(AppMaterials.floatingShadow.offset, const Offset(0, 4));
      expect(AppMaterials.floatingShadow.blurRadius, 18);
      expect(AppMaterials.floatingShadow.color.a, closeTo(0.12, 0.005));
      expect(AppMaterials.scrim.a, closeTo(0.32, 0.005));
      expect(AppMaterials.thumbShadow.color.a, closeTo(0.18, 0.005));
      expect(AppMaterials.sigmaOf(10), 5);
    });
  });

  group('AppTokens', () {
    test('同样输入解析出的实例相等：主题重建不会被当成换主题', () {
      final a = AppTokens.resolve(brightness: Brightness.light);
      final b = AppTokens.resolve(brightness: Brightness.light);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == AppTokens.resolve(brightness: Brightness.dark), isFalse);
      expect(
        a ==
            AppTokens.resolve(
              brightness: Brightness.light,
              accent: AccentPreset.navy,
            ),
        isFalse,
      );
    });

    test('密度档决定列表行上下内边距', () {
      for (final d in DensityTier.values) {
        final t = AppTokens.resolve(
          brightness: Brightness.light,
          tiers: AppearanceTiers(density: d),
        );
        expect(t.rowPadV, d.rowPadV);
      }
      expect(DensityTier.values.map((e) => e.rowPadV), [8, 12, 16]);
    });

    test('lerp：颜色平滑过渡，离散值过半切换', () {
      final light = AppTokens.resolve(brightness: Brightness.light);
      final dark = AppTokens.resolve(
        brightness: Brightness.dark,
        tiers: const AppearanceTiers(lineHeight: LineHeightTier.relaxed),
      );
      expect(light.lerp(dark, 0).colors, light.colors);
      expect(light.lerp(dark, 1).colors, dark.colors);
      final mid = light.lerp(dark, 0.5);
      expect(mid.colors.surfacePage.r, closeTo(0.5, 0.01));
      expect(light.lerp(dark, 0.4).text, light.text);
      expect(light.lerp(dark, 0.6).text, dark.text);
      expect(light.lerp(null, 0.5), light);
    });

    testWidgets('of：主题里没注册时按明暗就地解析', (tester) async {
      late AppTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              tokens = context.tokens;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tokens, AppTokens.resolve(brightness: Brightness.dark));
    });
  });

  group('外观档位（计划 §3.6）', () {
    test('字号档系数', () {
      expect(FontTier.values.map((e) => e.factor), [0.88, 1.0, 1.12, 1.24]);
    });

    test('旧正文字号折算到最近的档位', () {
      expect(FontTier.fromLegacyScale(0.8), FontTier.small);
      expect(FontTier.fromLegacyScale(0.94), FontTier.small);
      expect(FontTier.fromLegacyScale(1.0), FontTier.standard);
      expect(FontTier.fromLegacyScale(1.06), FontTier.standard);
      expect(FontTier.fromLegacyScale(1.1), FontTier.large);
      expect(FontTier.fromLegacyScale(1.2), FontTier.extraLarge);
      expect(FontTier.fromLegacyScale(1.4), FontTier.extraLarge);
    });

    test('预设的组合与识别（半透明档不参与）', () {
      expect(AppearancePreset.standard.tiers, const AppearanceTiers());
      expect(
        AppearancePreset.compact.tiers,
        const AppearanceTiers(
          font: FontTier.small,
          lineHeight: LineHeightTier.compact,
          density: DensityTier.compact,
        ),
      );
      for (final p in AppearancePreset.values) {
        expect(AppearancePreset.match(p.tiers), p);
        expect(
          AppearancePreset.match(
            p.tiers.copyWith(translucency: TranslucencyTier.off),
          ),
          p,
        );
      }
      expect(
        AppearancePreset.match(
          const AppearanceTiers(radius: RadiusTier.large),
        ),
        isNull,
        reason: '对不上任何预设就是「自定义」',
      );
    });
  });

  group('TieredTextScaler（计划 §8）', () {
    test('系统字号 × 档位，夹在 0.8–3.2', () {
      expect(
        const TieredTextScaler(TextScaler.linear(1.3), 1.12).scale(10),
        closeTo(14.56, 0.001),
      );
      expect(
        const TieredTextScaler(TextScaler.linear(0.8), 0.88).scale(10),
        closeTo(8, 0.001),
      );
      expect(
        const TieredTextScaler(TextScaler.linear(3), 1.24).scale(10),
        closeTo(32, 0.001),
      );
    });

    testWidgets('TieredTextScaling 不会重复相乘', (tester) async {
      late TextScaler scaler;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: TieredTextScaling(
            factor: 1.12,
            child: TieredTextScaling(
              factor: 1.24,
              child: Builder(
                builder: (context) {
                  scaler = MediaQuery.textScalerOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(scaler.scale(10), closeTo(10 * 1.3 * 1.24, 0.001));
    });
  });
}
