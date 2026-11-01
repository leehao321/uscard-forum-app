import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/about_page.dart';
import 'package:fluxdo/pages/open_source_licenses_page.dart';

import 'support/ui_harness.dart';

// 补充稿 54 / 55：开源许可列表与单个包详情。重点：许可数量对。

LicenseEntry _entry(List<String> packages, String text) =>
    LicenseEntryWithLineBreaks(packages, text);

/// 假数据：ai 3 份、abseil-cpp 2 份、accessibility 16 份、angle 58 份，
/// 另有一条同时属于 angle 和 ansi_styles 的许可，包名大小写混排。
List<LicenseEntry> _fakeEntries() => [
  _entry(['_fe_analyzer_shared'], 'fe license'),
  for (var i = 0; i < 2; i++) _entry(['abseil-cpp'], 'abseil license $i'),
  for (var i = 0; i < 16; i++) _entry(['accessibility'], 'a11y license $i'),
  _entry(['aFileChooser'], 'afc license'),
  _entry(['ai'], 'Copyright 2025, the Dart project authors.'),
  _entry(['ai'], 'Copyright (c) 2025, the Dart project authors. Second.'),
  _entry(['ai'], 'Third license text.'),
  _entry(['analyzer'], 'analyzer license'),
  for (var i = 0; i < 57; i++) _entry(['angle'], 'angle license $i'),
  // 一条许可列了两个包：两个包各记一份
  _entry(['angle', 'ansi_styles'], 'shared by angle and ansi_styles'),
];

Future<List<PackageLicenses>> _load() =>
    loadPackageLicenses(source: Stream.fromIterable(_fakeEntries()));

Widget _page({Future<List<PackageLicenses>> Function()? loader}) =>
    OpenSourceLicensesPage(
      appName: 'USCard Forum',
      appVersion: '0.3.1',
      loader: loader ?? _load,
    );

void main() {
  setUpAll(loadUiFonts);

  group('按包归并许可', () {
    test('每个包的许可数 = 条目里出现它的次数；多包条目每个包各记一份', () async {
      final packages = await _load();
      final counts = {for (final p in packages) p.name: p.count};
      expect(counts, {
        '_fe_analyzer_shared': 1,
        'abseil-cpp': 2,
        'accessibility': 16,
        'aFileChooser': 1,
        'ai': 3,
        'analyzer': 1,
        'angle': 58,
        'ansi_styles': 1,
      });
      // 条目 82 条，多包条目给两个包各记一份，所以包-许可对数是 83
      expect(packages.fold<int>(0, (a, p) => a + p.count), 83);
    });

    test('按包名排序，不分大小写', () async {
      final names = (await _load()).map((p) => p.name).toList();
      expect(names, [
        '_fe_analyzer_shared',
        'abseil-cpp',
        'accessibility',
        'aFileChooser',
        'ai',
        'analyzer',
        'angle',
        'ansi_styles',
      ]);
    });

    test('每份许可保留段落，顺序不变', () async {
      final ai = (await _load()).firstWhere((p) => p.name == 'ai');
      expect(ai.licenses, hasLength(3));
      expect(
        ai.licenses[0].first.text,
        'Copyright 2025, the Dart project authors.',
      );
      expect(ai.licenses[2].first.text, 'Third license text.');
    });

    test('没有条目：空列表', () async {
      expect(await loadPackageLicenses(source: const Stream.empty()), isEmpty);
    });

    test('默认读 LicenseRegistry', () async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      LicenseRegistry.addLicense(
        () => Stream.fromIterable([
          _entry(['reg_pkg'], 'one'),
          _entry(['reg_pkg'], 'two'),
        ]),
      );
      final packages = await loadPackageLicenses();
      expect(packages.single.name, 'reg_pkg');
      expect(packages.single.count, 2);
    });
  });

  group('开源许可列表', () {
    testUi('标题、应用名 + 版本 + 说明、分组列表；每行副标题的许可数和数据一致', (tester) async {
      await pumpUi(tester, _page());

      expect(find.text('开源许可'), findsOneWidget); // 导航标题
      expect(find.text('USCard Forum'), findsOneWidget);
      expect(find.text('版本 0.3.1'), findsOneWidget);
      expect(find.text('非官方美卡论坛客户端 · 基于 Flutter'), findsOneWidget);
      expect(find.text('第三方组件 · 按名称排序'), findsOneWidget);

      // 每行：包名 + 「N 份许可」，数量和假数据逐个对上
      final expected = {
        '_fe_analyzer_shared': 1,
        'abseil-cpp': 2,
        'accessibility': 16,
        'aFileChooser': 1,
        'ai': 3,
        'analyzer': 1,
        'angle': 58,
        'ansi_styles': 1,
      };
      for (final entry in expected.entries) {
        final row = find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(AppPressable),
        );
        expect(row, findsOneWidget, reason: entry.key);
        expect(
          find.descendant(of: row, matching: find.text('${entry.value} 份许可')),
          findsOneWidget,
          reason: '${entry.key} 应显示 ${entry.value} 份许可',
        );
        // 行尾 chevron
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(AppIcons.chevronRight),
          ),
          findsOneWidget,
        );
      }
      // 行按包名排序（从上到下）
      final tops = [
        for (final n in expected.keys) tester.getTopLeft(find.text(n)).dy,
      ];
      expect(tops, [...tops]..sort());
      // 行高 64
      final row = find.ancestor(
        of: find.text('ai'),
        matching: find.byType(AppPressable),
      );
      expect(tester.getSize(row).height, 64);
      expectNoUiException(tester);
    });

    testUi('读取中显示转圈，不显示包行', (tester) async {
      final never = Completer<List<PackageLicenses>>();
      await pumpUi(tester, _page(loader: () => never.future), settle: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(AppPressable), findsNothing);
      expect(find.text('USCard Forum'), findsOneWidget);
    });

    testUi('点一个包进详情页', (tester) async {
      await pumpUi(tester, _page());
      await tester.tap(find.text('ai'));
      await tester.pumpAndSettle();
      expect(find.byType(PackageLicensePage), findsOneWidget);
      // 回列表
      await tester.tap(find.byIcon(AppIcons.back));
      await tester.pumpAndSettle();
      expect(find.byType(PackageLicensePage), findsNothing);
      expect(find.text('第三方组件 · 按名称排序'), findsOneWidget);
    });
  });

  group('单个包详情', () {
    testUi('标题区「包名 + 3 份许可」，每份许可一张卡片，组页眉「许可 n / 3」', (tester) async {
      await pumpUi(tester, _page());
      await tester.tap(find.text('ai'));
      await tester.pumpAndSettle();

      // 导航标题 + 标题区各一个包名
      expect(find.text('ai'), findsNWidgets(2));
      expect(find.text('3 份许可'), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(find.text('许可 $n / 3'), findsOneWidget);
      }
      expect(find.text('许可 4 / 3'), findsNothing);
      // 三份许可正文各在自己的卡片里
      for (final t in [
        'Copyright 2025, the Dart project authors.',
        'Copyright (c) 2025, the Dart project authors. Second.',
        'Third license text.',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // 每份正文在自己的 surface/grouped 卡片里：三张不同的卡片
      final grouped = tester
          .element(find.text('Third license text.'))
          .tokens
          .colors
          .surfaceGrouped;
      Widget cardOf(String text) => tester
          .widgetList(
            find.ancestor(
              of: find.text(text),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).color == grouped,
              ),
            ),
          )
          .first;
      final cards = {
        cardOf('Copyright 2025, the Dart project authors.'),
        cardOf('Copyright (c) 2025, the Dart project authors. Second.'),
        cardOf('Third license text.'),
      };
      expect(cards, hasLength(3));
      final first = tester.getTopLeft(
        find.text('Copyright 2025, the Dart project authors.'),
      );
      final third = tester.getTopLeft(find.text('Third license text.'));
      expect(first.dy < third.dy, isTrue);
      // 组页眉在对应卡片上方
      expect(tester.getTopLeft(find.text('许可 1 / 3')).dy < first.dy, isTrue);
      expect(
        tester.getTopLeft(find.text('许可 3 / 3')).dy <
            tester.getTopLeft(find.text('Third license text.')).dy,
        isTrue,
      );
      expectNoUiException(tester);
    });

    testUi('只有一份许可：「1 份许可」「许可 1 / 1」', (tester) async {
      await pumpUi(tester, _page());
      await tester.tap(find.text('analyzer'));
      await tester.pumpAndSettle();
      expect(find.text('1 份许可'), findsOneWidget);
      expect(find.text('许可 1 / 1'), findsOneWidget);
      expect(find.text('analyzer license'), findsOneWidget);
    });

    testUi('许可很多的包（58 份）：n / N 一直数到 58，正文可滚动到最后一份', (tester) async {
      await pumpUi(tester, _page());
      await tester.scrollUntilVisible(
        find.text('angle'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('angle'));
      await tester.pumpAndSettle();
      expect(find.text('58 份许可'), findsOneWidget);
      expect(find.text('许可 1 / 58'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('shared by angle and ansi_styles'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('许可 58 / 58'), findsOneWidget);
      expect(find.text('shared by angle and ansi_styles'), findsOneWidget);
    });

    testUi('段落缩进、居中标题段', (tester) async {
      final package = PackageLicenses('demo', [
        [
          LicenseParagraph('Centered title', LicenseParagraph.centeredIndent),
          LicenseParagraph('plain paragraph', 0),
          LicenseParagraph('indented once', 1),
          LicenseParagraph('indented twice', 2),
        ],
      ]);
      await pumpUi(tester, PackageLicensePage(package: package));
      final plain = tester.getTopLeft(find.text('plain paragraph')).dx;
      final once = tester.getTopLeft(find.text('indented once')).dx;
      final twice = tester.getTopLeft(find.text('indented twice')).dx;
      expect(once - plain, 16);
      expect(twice - plain, 32);
      // 居中段：文字块撑满卡片宽，居中显示
      final title = tester.widget<Text>(find.text('Centered title'));
      expect(title.textAlign, TextAlign.center);
      expect(
        tester.widget<Text>(find.text('plain paragraph')).textAlign,
        TextAlign.start,
      );
    });
  });

  testUi('关于页的「开源许可」进的是新页面，不再是 Flutter 默认许可页', (tester) async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(
      () => Stream.fromIterable([
        _entry(['reg_pkg'], 'one'),
        _entry(['reg_pkg'], 'two'),
      ]),
    );
    await pumpUi(tester, const AboutPage());
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenSourceLicensesPage), findsOneWidget);
    expect(find.byType(LicensePage), findsNothing);
    expect(find.text('reg_pkg'), findsOneWidget);
    expect(find.text('2 份许可'), findsOneWidget);
    expect(find.text('第三方组件 · 按名称排序'), findsOneWidget);
  });
}
