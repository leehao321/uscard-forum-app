import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/settings/definitions/appearance_defs.dart';
import 'package:fluxdo/settings/definitions/bottom_nav_defs.dart';
import 'package:fluxdo/settings/settings_renderer.dart';
import 'package:fluxdo/widgets/settings/appearance_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 0.4.0 M8 外观页：v2 去掉的旧选项（计划 P11）不再出现；预设 / 外观模式 /
// 强调色 / 字体 / 微调 / 语言都在，强调色四个圆可选。

void main() {
  testWidgets('外观页去掉调色板、背景图、玻璃、弹窗模糊等旧选项，强调色可选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    LocaleSettings.setLocaleSync(AppLocale.zh);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    late List<String> ids;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TranslationProvider(
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final groups = buildAppearanceGroups(context);
                  ids = [
                    for (final item in groups.expand((g) => g.items))
                      item.id,
                  ];
                  // 底栏设置里的玻璃入口在 M3 主框架重做时一起处理
                  // 0.4.0 M3：底栏设置里的无字 / 悬浮 / 玻璃入口都去掉了
                  final bottomItems = buildBottomNavGroups(
                    context,
                  ).expand((g) => g.items).toList();
                  for (final removed in [
                    'bottomNavLabelless',
                    'bottomNavFloating',
                    'glassSettings',
                  ]) {
                    expect(
                      bottomItems.any((i) => i.id == removed),
                      isFalse,
                      reason: removed,
                    );
                  }
                  final accent = groups.firstWhere(
                    (g) => g.items.any((i) => i.id == 'accent'),
                  );
                  return ListView(
                    children: [
                      for (final item in accent.items)
                        SettingsRenderer(model: item),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final removed in [
      'neutral',
      'black',
      'customBackground',
      'themeColor',
      'topicCardStyle',
      'm3eStyle',
      'glassEnabled',
      'glassEffectLevel',
      'dialogBlur',
    ]) {
      expect(ids, isNot(contains(removed)), reason: removed);
    }
    expect(
      ids,
      containsAll([
        'presets',
        'themeMode',
        'accent',
        'font',
        'tuneFont',
        'tuneLineHeight',
        'tuneDensity',
        'tuneRadius',
        'tuneTranslucency',
        'language',
      ]),
    );

    // 强调色：四个圆，第二个是海军蓝
    final circles = find.descendant(
      of: find.byType(AppearanceAccentRow),
      matching: find.byType(AppPressable),
    );
    expect(circles, findsNWidgets(4));
    await tester.tap(circles.at(1));
    await tester.pumpAndSettle();
    expect(container.read(themeProvider).accent, AccentPreset.navy);
    expect(prefs.getString('accent_preset'), 'navy');
    expect(tester.takeException(), isNull);
  });
}
