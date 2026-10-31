import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/main.dart' show buildAppThemeForTest;
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/theme/app_theme.dart';
import 'package:m3e_ui/m3e_ui.dart';

// 应用主题装配：ColorScheme / TextTheme 由 v2 token 生成，全平台一套
// （0.4.0 计划 P2、§3.1、§3.3），以及接入主题的共用组件。

ThemeData _theme(
  Brightness brightness, {
  TargetPlatform platform = TargetPlatform.iOS,
  ThemeState themeState = const ThemeState(mode: ThemeMode.system),
}) => buildAppThemeForTest(
  brightness,
  platform: platform,
  themeState: themeState,
);

void main() {
  group('ColorScheme 角色（计划 §3.1）', () {
    for (final b in Brightness.values) {
      test(b.name, () {
        final c = AppColors.resolve(b, AccentPreset.meika);
        final s = appColorScheme(c, b);
        expect(s.brightness, b);
        expect(s.primary, c.brandPrimary);
        expect(s.secondary, c.brandPrimary);
        expect(s.tertiary, c.brandPrimary);
        expect(
          s.onPrimary,
          b == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        );
        expect(s.primaryContainer, c.brandButton);
        expect(s.onPrimaryContainer, const Color(0xFFFFFFFF));
        expect(s.onSurface, c.textPrimary);
        expect(s.onSurfaceVariant, c.textMeta);
        expect(s.error, c.textDestructive);
        expect(s.surface, c.surfacePage);
        expect(s.surfaceContainerLowest, c.surfacePage);
        expect(s.surfaceContainerLow, c.surfaceGrouped);
        expect(s.surfaceContainer, c.surfaceGrouped);
        expect(s.surfaceContainerHigh, c.surfaceElevated);
        expect(s.surfaceContainerHighest, c.surfaceElevated);
        expect(s.outlineVariant, c.separator);
        expect(s.outline, c.quoteRule);
        expect(s.secondaryContainer, c.avatarFill);
        expect(s.surfaceTint.a, 0);
      });
    }
  });

  group('应用主题装配', () {
    test('页面底、分隔线、文字跟 token 走；正文控件 17', () {
      for (final b in Brightness.values) {
        final theme = _theme(b);
        final c = theme.extension<AppTokens>()!.colors;
        expect(theme.scaffoldBackgroundColor, c.surfacePage);
        expect(theme.canvasColor, c.surfacePage);
        expect(theme.dividerColor, c.separator);
        expect(theme.textTheme.bodyMedium!.fontSize, 17);
        expect(theme.textTheme.bodySmall!.fontSize, 13);
        expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w600);
        expect(theme.textTheme.bodyMedium!.color, c.textPrimary);
        expect(theme.iconTheme.color, c.textPrimary);
        expect(theme.iconTheme.size, 24);
        expect(theme.textSelectionTheme.cursorColor, c.brandPrimary);
      }
    });

    test('全平台一套：配色、组件主题、扩展相同（只有各平台的系统字体不同）', () {
      final ios = _theme(Brightness.light);
      final android = _theme(Brightness.light, platform: TargetPlatform.android);
      expect(android.colorScheme, ios.colorScheme);
      expect(android.appBarTheme, ios.appBarTheme);
      expect(android.listTileTheme, ios.listTileTheme);
      expect(android.dialogTheme, ios.dialogTheme);
      expect(android.bottomSheetTheme, ios.bottomSheetTheme);
      expect(android.switchTheme, ios.switchTheme);
      expect(android.cardTheme, ios.cardTheme);
      expect(android.extensions, ios.extensions);
      expect(
        android.textTheme.bodyMedium!.fontSize,
        ios.textTheme.bodyMedium!.fontSize,
      );
    });

    test('两次装配相等：主题重建不会被当成换主题', () {
      expect(_theme(Brightness.light), _theme(Brightness.light));
      expect(_theme(Brightness.dark), _theme(Brightness.dark));
    });

    test('强调色只改 brand 两色', () {
      final navy = _theme(
        Brightness.light,
        themeState: const ThemeState(
          mode: ThemeMode.system,
          accent: AccentPreset.navy,
        ),
      );
      expect(navy.colorScheme.primary, const Color(0xFF1F3A5F));
      expect(navy.colorScheme.primaryContainer, const Color(0xFF2F5A8A));
      expect(navy.colorScheme.surface, AppColors.light.surfacePage);
    });

    test('组件文字样式带上用户字体与中文回退', () {
      final theme = _theme(
        Brightness.light,
        themeState: const ThemeState(
          mode: ThemeMode.system,
          fontFamily: AppFontFamily.miSans,
        ),
      );
      for (final style in [
        theme.appBarTheme.titleTextStyle!,
        theme.listTileTheme.titleTextStyle!,
        theme.dialogTheme.titleTextStyle!,
        theme.textTheme.bodyMedium!,
      ]) {
        expect(style.fontFamily, 'MiSans');
        expect(style.fontFamilyFallback, isNotEmpty);
      }
    });

    test('导航栏、列表行、对话框、半屏、开关', () {
      final theme = _theme(Brightness.light);
      final c = AppColors.light;
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(theme.appBarTheme.backgroundColor, c.surfacePage);
      expect(theme.appBarTheme.titleTextStyle!.fontSize, 17);
      expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w600);
      expect(theme.listTileTheme.minTileHeight, 48);
      expect(
        theme.listTileTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: 12),
      );
      expect(theme.listTileTheme.titleTextStyle!.fontSize, 17);
      expect(theme.listTileTheme.subtitleTextStyle!.color, c.textMeta);
      expect(
        theme.dialogTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
      expect(theme.dialogTheme.barrierColor, AppMaterials.scrim);
      expect(
        theme.bottomSheetTheme.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      );
      expect(theme.bottomSheetTheme.dragHandleSize, const Size(36, 5));
      expect(
        theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
        c.brandPrimary,
      );
      expect(theme.switchTheme.trackColor!.resolve({}), c.avatarFill);
      expect(theme.dividerTheme.thickness, 0.5);
    });

    test('深色半屏底是 surface/grouped，菜单是 surface/elevated', () {
      final theme = _theme(Brightness.dark);
      expect(theme.bottomSheetTheme.backgroundColor, AppColors.dark.surfaceGrouped);
      expect(theme.popupMenuTheme.color, AppColors.dark.surfaceElevated);
    });

    test('扩展：token、关闭 M3E、分组列表与半屏外壳取 v2 值', () {
      for (final b in Brightness.values) {
        final theme = _theme(b);
        expect(theme.extension<AppTokens>()!.brightness, b);
        expect(theme.extension<M3eFlags>()!.enabled, isFalse);
        final group = theme.extension<SegmentedCardGroupStyle>()!;
        expect(group.insetGrouped, isTrue);
        expect(group.radius, 12);
        expect(group.separatorIndent, 12);
        // 组内图标 20：12 + 20 + 12
        expect(group.leadingSeparatorIndent, 44);
        // 底色不写死，取 cardTheme（半屏里换成 elevated）
        expect(group.cellColor, isNull);
        expect(
          theme.cardTheme.color,
          AppColors.resolve(b, AccentPreset.meika).surfaceGrouped,
        );
        final sheet = theme.extension<AppSheetShellStyle>()!;
        expect(sheet.topRadius, 16);
        expect(sheet.titleStyle!.fontSize, 17);
        expect(sheet.titleStyle!.fontWeight, FontWeight.w400);
      }
    });

    test('明暗扩展对称，ThemeData.lerp 不丢扩展', () {
      final light = _theme(Brightness.light);
      final dark = _theme(Brightness.dark);
      expect(light.extensions.keys.toSet(), dark.extensions.keys.toSet());
      final mid = ThemeData.lerp(light, dark, 0.5);
      expect(mid.extensions.keys.toSet(), light.extensions.keys.toSet());
    });
  });

  group('接入应用主题的组件', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}：SegmentedCardGroup 是 inset-grouped，组底 surface/grouped', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(Brightness.light, platform: platform),
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
        expect(material.color, AppColors.light.surfaceGrouped);
        expect(
          material.shape,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
      });
    }

    testWidgets('iOS 上 Switch.adaptive 开是 brand/primary、关是 avatar/fill（不是系统绿）', (
      tester,
    ) async {
      for (final value in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(Brightness.light),
            home: Scaffold(
              body: Switch.adaptive(value: value, onChanged: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final painter = find.byType(Switch);
        expect(
          painter,
          paints..rrect(
            color: value ? AppColors.light.brandPrimary : AppColors.light.avatarFill,
          ),
          reason: value ? '开' : '关',
        );
      }
    });

    testWidgets('显式 color 优先于主题的组底色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light),
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

    testWidgets('iOS 半屏外壳：顶角 16、36×5 抓手、标题 17 Regular 左对齐', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 800,
                child: AppSheetScaffold(title: '标题', child: Text('内容')),
              ),
            ),
          ),
        ),
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
        const BorderRadius.vertical(top: Radius.circular(16)),
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints ==
                  const BoxConstraints.tightFor(width: 36, height: 5),
        ),
        findsOneWidget,
      );
      final title = tester.widget<Text>(find.text('标题'));
      expect(title.style?.fontSize, 17);
      expect(title.style?.fontWeight, FontWeight.w400);
      // v2（M2）：头行标题左对齐页边距 20，右侧是关闭按钮（「分享」半屏画板）
      expect(tester.getTopLeft(find.text('标题')).dx, 20);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
    });
  });
}
