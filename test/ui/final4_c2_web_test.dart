import 'dart:convert';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/web_bookmark.dart';
import 'package:fluxdo/pages/download_list_page.dart';
import 'package:fluxdo/pages/my_browser_page.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 补充稿 46 / 47 / 50 / 51：网页浏览的收藏、浏览历史、下载管理空态，以及添加收藏对话框。

class _Env {
  _Env(this.prefs);
  final SharedPreferences prefs;

  List<Override> get overrides => [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

Future<_Env> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return _Env(await SharedPreferences.getInstance());
}

/// 空态里的 48 大图标（不带圆底）
Finder _bareIcon(IconData icon) =>
    find.byWidgetPredicate((w) => w is Icon && w.icon == icon && w.size == 48);

void main() {
  setUpAll(loadUiFonts);

  Future<void> openBookmarks(WidgetTester tester, _Env h) async {
    await pumpUi(tester, const MyBrowserPage(), overrides: h.overrides);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
  }

  testUi('收藏空态：48 星形图标 + 标题 + 说明，右上有 +', (tester) async {
    final h = await _prefs();
    await openBookmarks(tester, h);
    expect(_bareIcon(AppIcons.star), findsOneWidget);
    expect(find.text('还没有收藏的网页'), findsOneWidget);
    expect(find.text('在内置浏览器里点「收藏」，或点右上角 + 手动添加网址'), findsOneWidget);
    expect(find.byType(AppStateView), findsOneWidget);
    expect(find.byIcon(AppIcons.add), findsOneWidget);
    expectNoUiException(tester);
  });

  testUi('浏览历史空态：48 图标 + 标题 + 说明', (tester) async {
    final h = await _prefs();
    await pumpUi(tester, const MyBrowserPage(), overrides: h.overrides);
    await tester.tap(find.text('浏览历史'));
    await tester.pumpAndSettle();
    expect(_bareIcon(AppIcons.history), findsOneWidget);
    expect(find.text('还没有浏览记录'), findsOneWidget);
    expect(find.text('用内置浏览器打开过的网页会显示在这里'), findsOneWidget);
    expectNoUiException(tester);
  });

  testUi('下载管理空态：48 下载图标 + 标题 + 说明', (tester) async {
    final h = await _prefs();
    await pumpUi(tester, const DownloadListPage(), overrides: h.overrides);
    expect(_bareIcon(AppIcons.download), findsOneWidget);
    expect(find.text('还没有下载记录'), findsOneWidget);
    expect(find.text('在内置浏览器里下载的文件会显示在这里'), findsOneWidget);
    expectNoUiException(tester);
  });

  testUi('添加收藏对话框：网址预填 https://，标题选填；确定后写入收藏', (tester) async {
    final h = await _prefs();
    await openBookmarks(tester, h);
    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    // 对话框：标题靠左，两个带标签的填充输入框
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(find.byType(AppFilledField), findsNWidgets(2));
    expect(find.text('网址'), findsOneWidget);
    expect(find.text('标题（选填）'), findsOneWidget);
    expect(find.text('留空时使用网页标题'), findsOneWidget);
    final urlField = find.descendant(
      of: find.byType(AppFilledField).first,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(urlField).controller!.text, 'https://');
    expectNoUiException(tester);

    await tester.enterText(urlField, 'https://example.com/a');
    await tester.enterText(
      find.descendant(
        of: find.byType(AppFilledField).last,
        matching: find.byType(TextField),
      ),
      '示例页',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.byType(AppAlertDialog), findsNothing);
    final saved = h.prefs.getString('web_bookmarks')!;
    expect(saved, contains('https://example.com/a'));
    expect(saved, contains('示例页'));
    // 列表里出现这条收藏，空态消失
    expect(find.text('示例页'), findsOneWidget);
    expect(find.byType(AppStateView), findsNothing);
  });

  testUi('添加收藏对话框：网址必填，只剩 https:// 前缀时不添加、对话框保留', (tester) async {
    final h = await _prefs();
    await openBookmarks(tester, h);
    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(h.prefs.getString('web_bookmarks'), isNull);

    // 清空后同样不添加
    await tester.enterText(
      find.descendant(
        of: find.byType(AppFilledField).first,
        matching: find.byType(TextField),
      ),
      '',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(h.prefs.getString('web_bookmarks'), isNull);
  });

  testUi('添加收藏对话框：取消关闭且不添加；没写协议的网址补 https://', (tester) async {
    final h = await _prefs();
    await openBookmarks(tester, h);

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AppFilledField).first,
        matching: find.byType(TextField),
      ),
      'https://cancel.example',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(h.prefs.getString('web_bookmarks'), isNull);

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AppFilledField).first,
        matching: find.byType(TextField),
      ),
      'example.org',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final list = WebBookmark.fromJson(
      (jsonDecode(h.prefs.getString('web_bookmarks')!) as List).first
          as Map<String, dynamic>,
    );
    expect(list.url, 'https://example.org');
    expect(list.title, '');
  });
}
