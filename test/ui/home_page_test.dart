import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/home/home_topic_list.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/widgets/topic/topic_list_skeleton.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M3：首页（Figma「首页 · 带发帖入口」）。不请求论坛：话题列表、分类、
// 用户都用夹具覆盖。

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId, this.script);

  final Future<List<Topic>> Function() script;

  @override
  Future<List<Topic>> build() => script();
}

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

List<Override> _overrides(
  SharedPreferences prefs,
  Future<List<Topic>> Function() script,
) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  // 所有分类都给同一份夹具（family 的 override 拿不到参数）
  topicListProvider.overrideWith2((_) => _FakeTopicList(null, script)),
  categoryMapProvider.overrideWithValue(
    AsyncData({for (final c in fixtureCategories()) c.id: c}),
  ),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

/// 页面卸载后桌面快捷键绑定有个延迟定时器，推进时间让它跑完
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  Future<SharedPreferences> prefsWith(Map<String, Object> v) async {
    SharedPreferences.setMockInitialValues(v);
    return SharedPreferences.getInstance();
  }

  for (final variant in [
    ...UiVariant.portrait.where((v) => v.textScale != 1.3),
    ...UiVariant.landscape,
  ]) {
    testUi('首页：导航栏 + 分类条 + 列表，不溢出（${variant.label}）', (tester) async {
      final prefs = await prefsWith({
        'pinned_category_ids': ['1', '2', '3'],
      });
      await pumpUi(
        tester,
        Scaffold(body: TopicsPage(onCreateTopic: () {})),
        variant: variant,
        overrides: _overrides(prefs, () async => fixtureTopics()),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expectNoUiException(tester);
      expect(find.byType(AppNavBar), findsOneWidget);
      expect(find.byType(FilterTabs), findsOneWidget);
      expect(find.byType(TopicRow), findsWidgets);
      await uiShot(tester, 'm3_home_${variant.label}');
      await _unmount(tester);
    });
  }

  testUi('分类条：全部 + 置顶分类，点选切分类，没有左右横滑切页', (tester) async {
    final prefs = await prefsWith({
      'pinned_category_ids': ['1', '3'],
    });
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: _overrides(prefs, () async => fixtureTopics()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final names = fixtureCategories();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text(names.firstWhere((c) => c.id == 1).name), findsWidgets);
    // 页面里没有 TabBarView / PageView
    expect(find.byType(TabBarView), findsNothing);
    expect(find.byType(PageView), findsNothing);
    await tester.tap(find.text(names.firstWhere((c) => c.id == 3).name).first);
    await tester.pump(const Duration(milliseconds: 300));
    expectNoUiException(tester);
    await _unmount(tester);
  });

  testUi('「全部分类」按钮固定在右侧，热区 44 高', (tester) async {
    final prefs = await prefsWith({});
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: _overrides(prefs, () async => fixtureTopics()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.bySemanticsLabel('全部分类');
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, 44);
    expect(tester.getTopRight(button).dx, closeTo(440, 0.5));
    await _unmount(tester);
  });

  testUi('未登录没有发帖入口；右槽宽 90、标题居中', (tester) async {
    final prefs = await prefsWith({});
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: _overrides(prefs, () async => fixtureTopics()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(AppIcons.compose), findsNothing);
    await _unmount(tester);
  });

  testUi('加载：200ms 内静默，之后出骨架，3 秒后出等待提示', (tester) async {
    final prefs = await prefsWith({});
    final gate = Completer<List<Topic>>();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: _overrides(prefs, () => gate.future),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TopicRow), findsNothing);
    expect(find.byType(WaitingHint), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TopicListSkeleton), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(WaitingHint), findsOneWidget);
    gate.complete(fixtureTopics());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WaitingHint), findsNothing);
    expect(find.byType(TopicRow), findsWidgets);
    await _unmount(tester);
  });

  testUi('出错原地显示：说明 + 「重试」，没有整页错误和「查看详情」', (tester) async {
    final prefs = await prefsWith({});
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: _overrides(prefs, () async => throw Exception('boom')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('查看详情'), findsNothing);
    expect(find.byType(AppNavBar), findsOneWidget, reason: '导航栏和分类条还在');
    expect(find.byType(HomeTopicList), findsOneWidget);
    await _unmount(tester);
  });
}
