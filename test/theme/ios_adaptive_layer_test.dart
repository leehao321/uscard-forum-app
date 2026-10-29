import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/theme/app_adaptive_theme.dart';
import 'package:fluxdo/theme/design_tokens.dart';
import 'package:m3e_ui/m3e_ui.dart';

// 测试用任意种子色(适配层本身不含任何品牌色)
const _seed = Color(0xFF3366CC);

ColorScheme _scheme(Brightness b) =>
    ColorScheme.fromSeed(seedColor: _seed, brightness: b);

AppDesignTokens _tokens(
  TargetPlatform platform, {
  Brightness brightness = Brightness.light,
  AppDensity density = AppDensity.standard,
  AppRadiusTier radius = AppRadiusTier.medium,
}) => AppDesignTokens.resolve(
  platform: platform,
  scheme: _scheme(brightness),
  density: density,
  radius: radius,
);

ThemeData _appTheme(
  TargetPlatform platform,
  Brightness brightness, {
  AppFontFamily font = AppFontFamily.system,
}) => buildAppThemeForTest(
  _scheme(brightness),
  ThemeState(mode: ThemeMode.system, seedColor: _seed, fontFamily: font),
  platform: platform,
);

void main() {
  group('AppDesignTokens.resolve', () {
    test('iOS 基准值', () {
      final t = _tokens(TargetPlatform.iOS);
      expect(
        [t.space1, t.space2, t.space3, t.space4, t.space5, t.space6],
        [4, 8, 12, 16, 20, 24],
      );
      expect(t.pageMargin, 16);
      expect([t.radiusS, t.radiusM, t.radiusL], [6, 10, 14]);
      expect(t.radiusSheet, 12);
      expect(t.rowMinHeight, 44);
      expect(t.useHairlineSeparators, isTrue);
      expect(t.typeScale.headline.fontSize, 17);
      expect(t.typeScale.headline.fontWeight, FontWeight.w600);
    });

    test('iOS 字阶:字号/字重,且不带颜色与 fontFamily', () {
      final s = _tokens(TargetPlatform.iOS).typeScale;
      final expected = <TextStyle, (double, FontWeight)>{
        s.largeTitle: (34, FontWeight.w700),
        s.title1: (28, FontWeight.w700),
        s.title2: (22, FontWeight.w700),
        s.title3: (20, FontWeight.w600),
        s.headline: (17, FontWeight.w600),
        s.body: (17, FontWeight.w400),
        s.callout: (16, FontWeight.w400),
        s.subheadline: (15, FontWeight.w400),
        s.footnote: (13, FontWeight.w400),
        s.caption: (12, FontWeight.w400),
      };
      for (final e in expected.entries) {
        expect(e.key.fontSize, e.value.$1);
        expect(e.key.fontWeight, e.value.$2);
        expect(e.key.color, isNull);
        expect(e.key.fontFamily, isNull);
        expect(e.key.fontFamilyFallback, isNull);
        expect(e.key.height, inInclusiveRange(1.2, 1.4));
      }
      expect(s.body.height, 1.35);
    });

    test('非 iOS 沿用现有 SegmentedCardGroup/卡片外观', () {
      for (final p in [TargetPlatform.android, TargetPlatform.windows]) {
        final t = _tokens(p);
        expect([t.radiusS, t.radiusM, t.radiusL], [5, 12, 20]);
        expect(t.radiusSheet, 20);
        expect(t.rowMinHeight, 48);
        expect(t.pageMargin, 16);
        expect(t.useHairlineSeparators, isFalse);
        // 应用 cardTheme 各平台都是 elevation 0：卡片不带阴影
        expect(t.materials.cardShadows, isFalse);
        // 字阶是 Material 档位,字号不同于 iOS
        expect(t.typeScale.body.fontSize, 16);
      }
    });

    test('密度档:间距 ×0.75/1/1.25 取整,iOS 行高 40/44/52', () {
      final compact = _tokens(TargetPlatform.iOS, density: AppDensity.compact);
      expect(
        [
          compact.space1,
          compact.space2,
          compact.space3,
          compact.space4,
          compact.space5,
          compact.space6,
        ],
        [3, 6, 9, 12, 15, 18],
      );
      expect(compact.pageMargin, 12);
      expect(compact.rowMinHeight, 40);

      final comfy = _tokens(
        TargetPlatform.iOS,
        density: AppDensity.comfortable,
      );
      expect(
        [
          comfy.space1,
          comfy.space2,
          comfy.space3,
          comfy.space4,
          comfy.space5,
          comfy.space6,
        ],
        [5, 10, 15, 20, 25, 30],
      );
      expect(comfy.rowMinHeight, 52);

      // 非 iOS 同样的增减量
      expect(
        _tokens(TargetPlatform.android, density: AppDensity.compact)
            .rowMinHeight,
        44,
      );
      expect(
        _tokens(TargetPlatform.android, density: AppDensity.comfortable)
            .rowMinHeight,
        56,
      );
      // 密度不动圆角
      expect(compact.radiusM, 10);
    });

    test('圆角档:×0.7/1/1.3 取整', () {
      final small = _tokens(TargetPlatform.iOS, radius: AppRadiusTier.small);
      expect([small.radiusS, small.radiusM, small.radiusL], [4, 7, 10]);
      expect(small.radiusSheet, 8);

      final large = _tokens(TargetPlatform.iOS, radius: AppRadiusTier.large);
      expect([large.radiusS, large.radiusM, large.radiusL], [8, 13, 18]);
      expect(large.radiusSheet, 16);

      // 圆角档不动间距/行高
      expect(small.space4, 16);
      expect(large.rowMinHeight, 44);
    });
  });

  group('动效 / 材质 / 语义色', () {
    test('AppMotion:时长与曲线,全平台一致', () {
      for (final p in TargetPlatform.values) {
        final m = _tokens(p).motion;
        expect(m.fast, const Duration(milliseconds: 150));
        expect(m.standard, const Duration(milliseconds: 250));
        expect(m.slow, const Duration(milliseconds: 350));
        expect(m.curves.standard, Curves.easeInOutCubic);
        expect(m.curves.enter, Curves.easeOutCubic);
        expect(m.curves.exit, Curves.easeInCubic);
        expect(m.curves.emphasized, Curves.fastEaseInToSlowEaseOut);
      }
      const a = AppMotion();
      const b = AppMotion(fast: Duration(milliseconds: 100));
      expect(AppMotion.lerp(a, b, 0.49), same(a));
      expect(AppMotion.lerp(a, b, 0.5), same(b));
    });

    test('AppMaterials:三档模糊 + iOS 悬浮阴影(明暗不同)', () {
      final light = _tokens(TargetPlatform.iOS).materials;
      expect((light.thin.sigma, light.thin.surfaceAlpha), (10, 0.72));
      expect((light.regular.sigma, light.regular.surfaceAlpha), (20, 0.80));
      expect((light.thick.sigma, light.thick.surfaceAlpha), (30, 0.88));
      expect(light.cardShadows, isFalse);
      expect(light.floatingShadow.offset, const Offset(0, 2));
      expect(light.floatingShadow.blurRadius, 8);
      expect(light.floatingShadow.color.a, closeTo(0.08, 0.005));
      expect(light.floatingShadow.color.r, 0);

      final dark = _tokens(
        TargetPlatform.iOS,
        brightness: Brightness.dark,
      ).materials;
      expect(dark.floatingShadow.color.a, closeTo(0.30, 0.005));

      // 非 iOS:模糊档位一致;卡片同样无阴影(cardTheme elevation 0)
      final android = _tokens(TargetPlatform.android).materials;
      expect(android.regular.sigma, 20);
      expect(android.cardShadows, isFalse);
    });

    test('AppColorRoles:只从 ColorScheme 派生', () {
      for (final b in Brightness.values) {
        final scheme = _scheme(b);
        final c = _tokens(TargetPlatform.iOS, brightness: b).colors;
        expect(c.label, scheme.onSurface);
        expect(c.secondaryLabel, scheme.onSurfaceVariant);
        expect(c.separator, scheme.outlineVariant);
        expect(c.tint, scheme.primary);
        expect(c.tertiaryLabel.a, closeTo(0.6, 0.005));
        expect(c.tertiaryLabel.r, scheme.onSurfaceVariant.r);
        expect(c.tertiaryLabel.g, scheme.onSurfaceVariant.g);
        expect(c.tertiaryLabel.b, scheme.onSurfaceVariant.b);
        if (b == Brightness.light) {
          expect(c.groupedBackground, scheme.surfaceContainer);
          expect(c.groupedCell, scheme.surfaceContainerLowest);
        } else {
          expect(c.groupedBackground, scheme.surface);
          expect(c.groupedCell, scheme.surfaceContainerHigh);
        }
      }
      final light = _tokens(TargetPlatform.iOS).colors;
      final dark = _tokens(
        TargetPlatform.iOS,
        brightness: Brightness.dark,
      ).colors;
      expect(light.groupedCell, isNot(dark.groupedCell));
    });

    test('contrastRatio:WCAG 2.x 已知值', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(AppColorRoles.contrastRatio(black, white), closeTo(21.0, 1e-9));
      expect(AppColorRoles.contrastRatio(white, black), closeTo(21.0, 1e-9));
      expect(AppColorRoles.contrastRatio(white, white), 1.0);
      const grey = Color(0xFF767676);
      expect(AppColorRoles.contrastRatio(grey, grey), 1.0);
      // #767676 在白底上恰好 AA(4.54:1),#777777 略低于 4.5
      expect(
        AppColorRoles.contrastRatio(grey, white),
        closeTo(4.54, 0.01),
      );
      expect(
        AppColorRoles.contrastRatio(const Color(0xFF777777), white),
        lessThan(4.5),
      );
      expect(
        AppColorRoles.contrastRatio(const Color(0xFFFF0000), white),
        closeTo(4.0, 0.01),
      );
    });
  });

  group('AppDesignTokens 扩展行为', () {
    test('copyWith 只改指定字段', () {
      final t = _tokens(TargetPlatform.iOS);
      final c = t.copyWith(radiusM: 99, rowMinHeight: 60);
      expect(c.radiusM, 99);
      expect(c.rowMinHeight, 60);
      expect(c.radiusL, t.radiusL);
      expect(c.colors, same(t.colors));
      expect(c.typeScale, same(t.typeScale));
    });

    test('字段不覆盖 ThemeExtension.type(否则 extensions 的 key 会错)', () {
      final t = _tokens(TargetPlatform.iOS);
      expect(t.type, AppDesignTokens);
      final theme = ThemeData(extensions: [t]);
      expect(theme.extension<AppDesignTokens>(), same(t));
    });

    test('lerp 端点与中点', () {
      final ios = _tokens(TargetPlatform.iOS);
      final android = _tokens(TargetPlatform.android);

      final at0 = ios.lerp(android, 0);
      expect(at0.radiusM, ios.radiusM);
      expect(at0.rowMinHeight, ios.rowMinHeight);
      expect(at0.useHairlineSeparators, isTrue);

      final at1 = ios.lerp(android, 1);
      expect(at1.radiusM, android.radiusM);
      expect(at1.rowMinHeight, android.rowMinHeight);
      expect(at1.useHairlineSeparators, isFalse);
      expect(at1.materials.cardShadows, android.materials.cardShadows);

      final mid = ios.lerp(android, 0.5);
      expect(mid.radiusM, closeTo(11, 1e-9));
      expect(mid.rowMinHeight, closeTo(46, 1e-9));
      expect(mid.typeScale.body.fontSize, closeTo(16.5, 1e-9));
      expect(mid.motion, isNotNull);

      // 非同类/空 other 返回自身
      expect(ios.lerp(null, 0.5), same(ios));
    });

    test('明暗之间 lerp 颜色在两端之间', () {
      final light = _tokens(TargetPlatform.iOS);
      final dark = _tokens(TargetPlatform.iOS, brightness: Brightness.dark);
      final mid = light.lerp(dark, 0.5);
      expect(mid.colors.groupedCell, isNot(light.colors.groupedCell));
      expect(mid.colors.groupedCell, isNot(dark.colors.groupedCell));
      expect(light.lerp(dark, 1).colors.groupedCell, dark.colors.groupedCell);
    });

    testWidgets('AppDesignTokens.of:未注册时按主题平台就地解析', (tester) async {
      late AppDesignTokens fromIos;
      late AppDesignTokens fromAndroid;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (c) {
              fromIos = AppDesignTokens.of(c);
              return Theme(
                data: ThemeData(platform: TargetPlatform.android),
                child: Builder(
                  builder: (c2) {
                    fromAndroid = AppDesignTokens.of(c2);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(fromIos.radiusM, 10);
      expect(fromAndroid.radiusM, 12);
    });

    testWidgets('AppDesignTokens.of:已注册时取主题里的实例', (tester) async {
      final custom = _tokens(TargetPlatform.iOS).copyWith(radiusM: 42);
      late AppDesignTokens got;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [custom]),
          home: Builder(
            builder: (c) {
              got = AppDesignTokens.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(got.radiusM, 42);
    });
  });

  group('应用主题装配(_buildAppTheme)', () {
    for (final brightness in Brightness.values) {
      final label = brightness.name;

      test('iOS $label:图标/AppBar/ListTile/Dialog 适配 + 扩展齐全', () {
        final theme = _appTheme(TargetPlatform.iOS, brightness);
        final tokens = theme.extension<AppDesignTokens>()!;

        expect(theme.iconTheme.weight, 300);
        expect(theme.primaryIconTheme.weight, 300);

        expect(theme.appBarTheme.centerTitle, isTrue);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.titleTextStyle?.fontSize, 17);
        expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w600);
        expect(
          theme.appBarTheme.titleTextStyle?.color,
          theme.colorScheme.onSurface,
        );

        final tile = theme.listTileTheme;
        expect(tile.minTileHeight, 44);
        expect(tile.contentPadding, const EdgeInsets.symmetric(horizontal: 16));
        expect(tile.titleTextStyle?.fontSize, 17);
        expect(tile.titleTextStyle?.color, theme.colorScheme.onSurface);
        expect(tile.subtitleTextStyle?.fontSize, 13);
        expect(
          tile.subtitleTextStyle?.color,
          theme.colorScheme.onSurfaceVariant,
        );
        expect(tile.horizontalTitleGap, 12);
        expect(tile.minLeadingWidth, 28);

        final dialog = theme.dialogTheme;
        expect(
          dialog.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        );
        expect(dialog.titleTextStyle?.fontSize, 17);
        expect(dialog.contentTextStyle?.fontSize, 15);
        expect(
          dialog.contentTextStyle?.color,
          theme.colorScheme.onSurfaceVariant,
        );

        // 扩展:M3eFlags 仍在,token 与两个包级样式都已注册
        expect(theme.extension<M3eFlags>(), isNotNull);
        expect(tokens.radiusM, 10);
        expect(tokens.rowMinHeight, 44);
        final group = theme.extension<SegmentedCardGroupStyle>()!;
        expect(group.insetGrouped, isTrue);
        expect(group.radius, tokens.radiusM);
        expect(group.separatorIndent, 16);
        expect(group.separatorColor, theme.colorScheme.outlineVariant);
        // 页面底色还没换成 groupedBackground 之前，单元格沿用卡片色
        expect(group.cellColor, isNull);
        final sheet = theme.extension<AppSheetShellStyle>()!;
        expect(sheet.topRadius, 12);
        expect(sheet.titleStyle?.fontSize, 17);
      });

      test('Android $label:视觉保持原样,只多一个 token 扩展', () {
        final theme = _appTheme(TargetPlatform.android, brightness);

        expect(theme.iconTheme.weight, 400);
        expect(theme.primaryIconTheme.weight, 400);
        expect(theme.appBarTheme.centerTitle, isNull);
        expect(theme.appBarTheme.scrolledUnderElevation, isNull);
        expect(theme.appBarTheme.titleTextStyle, isNull);
        expect(theme.listTileTheme.minTileHeight, isNull);
        expect(theme.listTileTheme.contentPadding, isNull);
        expect(theme.listTileTheme.titleTextStyle, isNull);
        expect(theme.dialogTheme.shape, isNull);
        expect(theme.dialogTheme.titleTextStyle, isNull);

        expect(theme.extension<SegmentedCardGroupStyle>(), isNull);
        expect(theme.extension<AppSheetShellStyle>(), isNull);
        expect(theme.extension<M3eFlags>(), isNotNull);
        final tokens = theme.extension<AppDesignTokens>()!;
        expect([tokens.radiusS, tokens.radiusM, tokens.radiusL], [5, 12, 20]);
        expect(theme.extensions.length, 2);

        // 卡片/菜单仍是原有设置
        expect(
          theme.cardTheme.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
      });
    }

    test('桌面平台同样不受 iOS 适配影响', () {
      for (final p in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final theme = _appTheme(p, Brightness.light);
        expect(theme.iconTheme.weight, 400);
        expect(theme.extension<SegmentedCardGroupStyle>(), isNull);
        expect(theme.listTileTheme.minTileHeight, isNull);
      }
    });

    test('light/dark 扩展对称,ThemeData.lerp 不丢扩展', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
        final light = _appTheme(p, Brightness.light);
        final dark = _appTheme(p, Brightness.dark);
        expect(
          light.extensions.keys.toSet(),
          dark.extensions.keys.toSet(),
          reason: '$p 明暗两侧注册的 extension 必须一致',
        );
        final mid = ThemeData.lerp(light, dark, 0.5);
        expect(mid.extension<AppDesignTokens>(), isNotNull);
        expect(
          mid.extension<SegmentedCardGroupStyle>() != null,
          p == TargetPlatform.iOS,
        );
      }
    });

    test('iOS 明暗 token 里的 groupedCell 不同', () {
      final light = _appTheme(TargetPlatform.iOS, Brightness.light);
      final dark = _appTheme(TargetPlatform.iOS, Brightness.dark);
      expect(
        light.extension<AppDesignTokens>()!.colors.groupedCell,
        isNot(dark.extension<AppDesignTokens>()!.colors.groupedCell),
      );
    });

    test('iOS 组件文字样式带上用户字体与中文 fallback', () {
      final theme = _appTheme(
        TargetPlatform.iOS,
        Brightness.light,
        font: AppFontFamily.miSans,
      );
      for (final style in [
        theme.listTileTheme.titleTextStyle,
        theme.listTileTheme.subtitleTextStyle,
        theme.appBarTheme.titleTextStyle,
        theme.dialogTheme.titleTextStyle,
        theme.dialogTheme.contentTextStyle,
      ]) {
        expect(style?.fontFamily, 'MiSans');
        expect(style?.fontFamilyFallback, SystemChineseFont.fontFamilyFallback);
      }
    });

    test('非 iOS:适配层除追加 token 扩展外,ThemeData 与 base 完全相等', () {
      final scheme = _scheme(Brightness.light);
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final base = ThemeData(
          colorScheme: scheme,
          platform: p,
          extensions: const [M3eFlags(enabled: true)],
        );
        final out = applyAppAdaptiveLayer(base, scheme: scheme, platform: p);
        expect(out.extension<AppDesignTokens>(), isNotNull);
        expect(out.copyWith(extensions: base.extensions.values), base);
      }
    });

    test('applyAppAdaptiveLayer 不改全局 textTheme', () {
      final scheme = _scheme(Brightness.light);
      final base = ThemeData(
        colorScheme: scheme,
        platform: TargetPlatform.iOS,
      );
      final out = applyAppAdaptiveLayer(
        base,
        scheme: scheme,
        platform: TargetPlatform.iOS,
      );
      expect(out.textTheme.bodyLarge?.fontSize, base.textTheme.bodyLarge?.fontSize);
      expect(out.textTheme.titleLarge?.fontSize, base.textTheme.titleLarge?.fontSize);
    });
  });

  group('接入应用主题的组件', () {
    testWidgets('iOS 主题下 SegmentedCardGroup 是 inset-grouped，单元格沿用卡片色', (
      tester,
    ) async {
      final theme = _appTheme(TargetPlatform.iOS, Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SegmentedCardGroup(
              children: [Text('a'), Text('b'), Text('c')],
            ),
          ),
        ),
      );
      final group = find.byType(SegmentedCardGroup);
      expect(
        find.descendant(of: group, matching: find.byType(Divider)),
        findsNWidgets(2),
      );
      final material = tester.widget<Material>(
        find.descendant(of: group, matching: find.byType(Material)),
      );
      // 页面底色换成 groupedBackground 之前不用 groupedCell（见 app_adaptive_theme）
      expect(
        material.color,
        theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
      );
      expect(
        material.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
    });

    testWidgets('iOS 主题下显式 color 优先于 groupedCell', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _appTheme(TargetPlatform.iOS, Brightness.light),
          home: const Scaffold(
            body: SegmentedCardGroup(
              color: Color(0xFF123456),
              children: [Text('a'), Text('b')],
            ),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(SegmentedCardGroup),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, const Color(0xFF123456));
    });

    testWidgets('Android 主题下 SegmentedCardGroup 仍是带缝隙的分段卡片', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _appTheme(TargetPlatform.android, Brightness.light),
          home: const Scaffold(
            body: SegmentedCardGroup(
              children: [Text('a'), Text('b'), Text('c')],
            ),
          ),
        ),
      );
      final group = find.byType(SegmentedCardGroup);
      expect(find.descendant(of: group, matching: find.byType(Divider)), findsNothing);
      expect(
        find.descendant(of: group, matching: find.byType(Material)),
        findsNWidgets(3),
      );
    });

    group('AppSheetScaffold', () {
      Future<void> pumpSheet(WidgetTester tester, ThemeData theme) {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        return tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                // 底部弹框实际拿到的是撑满屏宽的紧约束
                child: SizedBox(
                  width: 800,
                  child: AppSheetScaffold(title: '标题', child: Text('内容')),
                ),
              ),
            ),
          ),
        );
      }

      Finder handle(double w, double h) => find.byWidgetPredicate(
        (wd) =>
            wd is Container &&
            wd.constraints == BoxConstraints.tightFor(width: w, height: h),
      );

      testWidgets('iOS:圆角 12、36×5 抓手、标题 17/w600 居中', (tester) async {
        await pumpSheet(tester, _appTheme(TargetPlatform.iOS, Brightness.light));

        final shell = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppSheetScaffold),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          shell.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(12)),
        );

        expect(handle(36, 5), findsOneWidget);
        final handleBox = tester.widget<Container>(handle(36, 5));
        final deco = handleBox.decoration as BoxDecoration;
        expect(deco.borderRadius, BorderRadius.circular(2.5));
        expect(deco.color!.a, closeTo(0.4, 0.005));

        final title = tester.widget<Text>(find.text('标题'));
        expect(title.style?.fontSize, 17);
        expect(title.style?.fontWeight, FontWeight.w600);
        expect(title.textAlign, TextAlign.center);
        // 有关闭按钮时标题仍相对整条栏居中
        expect(tester.getCenter(find.text('标题')).dx, closeTo(400, 0.5));
      });

      testWidgets('iOS 未注册 AppSheetShellStyle 时回退 HIG 默认', (tester) async {
        await pumpSheet(tester, ThemeData(platform: TargetPlatform.iOS));
        final shell = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppSheetScaffold),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          shell.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(12)),
        );
        expect(handle(36, 5), findsOneWidget);
      });

      testWidgets('Android:圆角 20、32×4 抓手、标题左对齐(原样)', (tester) async {
        await pumpSheet(
          tester,
          _appTheme(TargetPlatform.android, Brightness.light),
        );
        final shell = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppSheetScaffold),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          shell.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(20)),
        );
        expect(handle(32, 4), findsOneWidget);
        expect(handle(36, 5), findsNothing);
        // 左对齐:标题左缘距外壳 16(原标题栏左内边距)
        expect(tester.getTopLeft(find.text('标题')).dx, 16);
      });
    });
  });

  group('相等性', () {
    test('同样输入解析出的 token 相等：主题重建不会被当成换主题', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
        final a = _appTheme(p, Brightness.light);
        final b = _appTheme(p, Brightness.light);
        expect(
          a.extension<AppDesignTokens>(),
          b.extension<AppDesignTokens>(),
        );
        expect(
          a.extension<AppDesignTokens>().hashCode,
          b.extension<AppDesignTokens>().hashCode,
        );
        // 整个 ThemeData 相等，AnimatedTheme 才不会空跑插值动画
        expect(a, b);
      }
    });

    test('明暗不同时 token 不相等', () {
      expect(
        _appTheme(TargetPlatform.iOS, Brightness.light)
            .extension<AppDesignTokens>(),
        isNot(
          _appTheme(TargetPlatform.iOS, Brightness.dark)
              .extension<AppDesignTokens>(),
        ),
      );
    });
  });
}
