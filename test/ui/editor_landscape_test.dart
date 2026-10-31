import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/create_topic_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse_cook_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/widgets/post/reply_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 编辑器横屏（设计 §5.6）：正文列限宽 640 居中；底部工具条的背景横跨整个屏宽
// （由 editor_icons_test 的通栏断言覆盖），里面的按钮按 640 栏左右对齐。竖屏不受影响。
// 数据全是假的，不请求论坛。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWith(_FakeUser.new),
    categoriesProvider.overrideWith((ref) async => fixtureCategories()),
    tagsProvider.overrideWith((ref) async => const ['chase']),
  ];
}

Future<void> _setupEditor(WidgetTester tester) => tester.runAsync(() async {
  if (!PreloadedDataService().isLoaded) {
    await PreloadedDataService().hydrateFromHtml(
      '<meta id="data-discourse-setup"><script id="data-preloaded" type="application/json">${jsonEncode({
        'currentUser': {'id': 1, 'username': 'tester'},
        'siteSettings': {'min_post_length': 1, 'max_post_length': 10000},
        'site': {'categories': [], 'top_tags': []},
      })}</script>',
    );
    await DiscourseCookService().ensureInitialized();
  }
});

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  final variants = [
    for (final b in Brightness.values)
      for (final d in [UiDevice.landscape, UiDevice.landscapePro])
        UiVariant(b, 1, d),
  ];

  for (final v in variants) {
    testUi('发帖页：正文列 640 居中，工具条背景通栏（${v.label}）', (tester) async {
      await _setupEditor(tester);
      await pumpUi(
        tester,
        const CreateTopicPage(
          initialTitle: '分享最近的开发体验',
          initialContent: '最近重新整理了写作环境。',
        ),
        variant: v,
        overrides: await _overrides(),
        settle: false,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expectNoUiException(tester);
      expectEditorColumn(tester, v);

      // 正文输入区居中：左右留白相等（误差 1）
      final screen = v.device.size;
      final fields = find.byType(EditableText).evaluate().map(
        (e) => tester.getRect(find.byWidget(e.widget)),
      );
      expect(fields, isNotEmpty);
      for (final r in fields) {
        expect(r.left - (screen.width - r.right), closeTo(0, 1));
      }
      // 工具条背景横跨整个屏宽
      final island = find.byKey(const ValueKey('composer-island-surface'));
      if (island.evaluate().isNotEmpty) {
        expect(tester.getSize(island.first).width, screen.width);
      }
      await uiShot(tester, 'editor_create_${v.label}');
      await _unmount(tester);
    });

    testUi('回复半屏：正文列 640（${v.label}）', (tester) async {
      await _setupEditor(tester);
      await pumpUi(
        tester,
        ReplySheet(topicId: 1001, preloadedDraftFuture: Future.value(null)),
        variant: v,
        overrides: await _overrides(),
        settle: false,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expectNoUiException(tester);
      expectEditorColumn(tester, v);
      await uiShot(tester, 'editor_reply_${v.label}');
      await _unmount(tester);
    });
  }

  // 竖屏不受影响：393 宽下输入区就是整宽减页边距，不被 640 限制
  testUi('竖屏不受影响（393）', (tester) async {
    await _setupEditor(tester);
    const v = UiVariant(Brightness.light, 1, UiDevice.pro);
    await pumpUi(
      tester,
      const CreateTopicPage(initialTitle: '标题', initialContent: '正文'),
      variant: v,
      overrides: await _overrides(),
      settle: false,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expectNoUiException(tester);
    var widest = 0.0;
    for (final e in find.byType(EditableText).evaluate()) {
      final w = tester.getSize(find.byWidget(e.widget)).width;
      if (w > widest) widest = w;
    }
    expect(widest, greaterThan(300));
    expect(widest, lessThanOrEqualTo(393));
    await _unmount(tester);
  });
}
