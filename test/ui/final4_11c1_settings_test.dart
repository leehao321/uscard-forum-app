import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/reading_settings_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 33 / 34）：设置里的新交互。
// 偏好存在 SharedPreferences 的 mock 里，不联网。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

/// 返回假偏好存储和覆盖项；[prefs] 用来断言「选择后真的写进存储」
Future<(SharedPreferences, List<Override>)> _fakeStore([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return (
    prefs,
    <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      currentUserProvider.overrideWith(_FakeUser.new),
      currentUsernameProvider.overrideWith((ref) async => null),
    ],
  );
}

void main() {
  setUpAll(loadUiFonts);

  group('34 阅读 · 标签页打开方式', () {
    testUi('「交互」组里有一行「标签页打开方式」，当前值默认', (tester) async {
      final (_, overrides) = await _fakeStore();
      await pumpUi(
        tester,
        const ReadingSettingsPage(),
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('交互'), findsOneWidget);
      expect(find.text('标签页打开方式'), findsOneWidget);
      // 行右侧写当前值
      expect(find.text('默认'), findsOneWidget);
    });

    testUi('点按弹单选对话框，当前项打勾；选中即生效并写进存储', (tester) async {
      final (prefs, overrides) = await _fakeStore();
      await pumpUi(
        tester,
        const ReadingSettingsPage(),
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('标签页打开方式'));
      await tester.pump(const Duration(milliseconds: 400));
      // 对话框，不是半屏
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(AppSheetScaffold), findsNothing);
      expect(find.text('默认打开标签页方式'), findsOneWidget);
      expect(find.text('标签页模式'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      // 当前项（默认）打勾，另一项没有
      final defaultRow = find.ancestor(
        of: find.text('默认').last,
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: defaultRow.first, matching: find.byIcon(AppIcons.check)),
        findsOneWidget,
      );
      expect(find.byIcon(AppIcons.check), findsOneWidget);

      await tester.tap(find.text('标签页模式'));
      await tester.pump(const Duration(milliseconds: 400));
      // 对话框关闭，行右侧改成「标签页模式」，存储里写入了新值
      expect(find.byType(AppAlertDialog), findsNothing);
      expect(find.text('标签页模式'), findsOneWidget);
      expect(prefs.getString('pref_bookmarks_open_mode'), 'tabbedWorkspace');

      // 再点开：勾跟着换到「标签页模式」
      await tester.tap(find.text('标签页打开方式'));
      await tester.pump(const Duration(milliseconds: 400));
      final tabbedRow = find.ancestor(
        of: find.text('标签页模式').last,
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: tabbedRow.first, matching: find.byIcon(AppIcons.check)),
        findsOneWidget,
      );
    });

    testUi('点「取消」不改值', (tester) async {
      final (prefs, overrides) = await _fakeStore();
      await pumpUi(
        tester,
        const ReadingSettingsPage(),
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('标签页打开方式'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppAlertDialog), findsNothing);
      expect(prefs.getString('pref_bookmarks_open_mode'), isNull);
    });

    testUi('存储里已是标签页模式时，行右侧显示「标签页模式」', (tester) async {
      final (_, overrides) = await _fakeStore({
        'pref_bookmarks_open_mode': BookmarksOpenMode.tabbedWorkspace.name,
      });
      await pumpUi(
        tester,
        const ReadingSettingsPage(),
        overrides: overrides,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('标签页模式'), findsOneWidget);
    });
  });
}
