import 'dart:convert';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/download_list_page.dart';
import 'package:fluxdo/pages/my_browser_page.dart';

import 'support/final4_11c1_support.dart';
import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 38）：我的 › 网页浏览首页——地址栏 + 收藏 / 浏览历史 / 下载管理。
// 收藏存在 SharedPreferences 的 mock 里，不联网、不真的打开内置浏览器。

String _bookmarks(int n) => jsonEncode([
  for (var i = 0; i < n; i++)
    {
      'url': 'https://example.com/$i',
      'title': '示例收藏 $i',
      'createdAt': '2026-10-30T10:00:00.000',
    },
]);

void main() {
  setUpAll(loadUiFonts);

  Future<List<String>> openPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    final (_, overrides) = await fakeStore(prefs);
    final opened = <String>[];
    await pumpUi(
      tester,
      MyBrowserPage(onOpenUrl: (context, url) => opened.add(url)),
      overrides: overrides,
    );
    return opened;
  }

  testUi('首页：地址栏占位 + 三行入口（带说明）+ 页脚', (tester) async {
    await openPage(tester);
    expect(find.text('网页浏览'), findsOneWidget);
    expect(find.text('输入网址'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('0 个收藏'), findsOneWidget);
    expect(find.text('浏览历史'), findsOneWidget);
    expect(find.text('查看浏览过的网页'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('查看下载的文件'), findsOneWidget);
    expect(find.text('这里只记录应用内置浏览器的网页；论坛的书签和浏览历史在「我的」里。'), findsOneWidget);
    expectNoUiException(tester);
  });

  testUi('收藏条数跟着存储走', (tester) async {
    await openPage(tester, prefs: {'web_bookmarks': _bookmarks(2)});
    expect(find.text('2 个收藏'), findsOneWidget);
  });

  testUi('地址栏：点右侧箭头打开，没写协议的补 https://', (tester) async {
    final opened = await openPage(tester);
    await tester.enterText(find.byType(TextField), '  example.com/a ');
    await tester.tap(find.byIcon(AppIcons.forward));
    await tester.pump();
    expect(opened, ['https://example.com/a']);
  });

  testUi('地址栏：键盘「前往」同样打开，写了协议的原样带走', (tester) async {
    final opened = await openPage(tester);
    await tester.enterText(find.byType(TextField), 'http://a.b/x');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(opened, ['http://a.b/x']);
  });

  testUi('地址栏：空输入或只有空格不打开', (tester) async {
    final opened = await openPage(tester);
    await tester.tap(find.byIcon(AppIcons.forward));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(AppIcons.forward));
    await tester.pump();
    expect(opened, isEmpty);
  });

  testUi('点「收藏」进收藏列表，点「浏览历史」进历史页', (tester) async {
    await openPage(tester, prefs: {'web_bookmarks': _bookmarks(2)});

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('示例收藏 0'), findsOneWidget);
    expect(find.text('示例收藏 1'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('浏览历史'));
    await tester.pumpAndSettle();
    expect(find.text('还没有浏览记录'), findsOneWidget);
  });

  testUi('点「下载管理」进下载列表', (tester) async {
    await openPage(tester);
    await tester.tap(find.text('下载管理'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DownloadListPage), findsOneWidget);
  });

  test('网址补全：去空白、补 https://、空输入返回 null', () {
    expect(normalizeBrowserInput('example.com'), 'https://example.com');
    expect(normalizeBrowserInput('  example.com  '), 'https://example.com');
    expect(normalizeBrowserInput('https://a.b'), 'https://a.b');
    expect(normalizeBrowserInput('http://a.b'), 'http://a.b');
    expect(normalizeBrowserInput('   '), isNull);
    expect(normalizeBrowserInput(''), isNull);
  });
}
