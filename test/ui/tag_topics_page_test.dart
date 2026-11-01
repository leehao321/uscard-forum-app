import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/tag_notification_level.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/tag_topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:fluxdo/providers/topic_list/sort_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/topic/sort_and_tags_bar.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 补充稿 06「标签话题列表 · #amex」：点按标签进入的话题列表，复用分类话题页的结构：
// 导航中间是标签名（#amex），右侧订阅 + 搜索；筛选胶囊行（最新 · 默认排序）；列表行带分类名。
// 服务是假的，不联网。

class _FakeService implements DiscourseService {
  /// 每次取话题的 (filter, tags, order)
  final requests = <(String, List<String>?, String?)>[];

  @override
  Future<TopicListResponse> getFilteredTopics({
    required String filter,
    int? categoryId,
    String? categorySlug,
    String? parentCategorySlug,
    List<String>? tags,
    String? period,
    int page = 0,
    String? order,
    bool? ascending,
    String? subset,
    List<int>? topicIds,
  }) async {
    requests.add((filter, tags, order));
    return TopicListResponse(topics: fixtureTopics(), tags: const []);
  }

  @override
  Future<TagNotificationLevel> getTagNotificationLevel(String tagName) async =>
      TagNotificationLevel.regular;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLoggedIn extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

List<Override> _overrides(SharedPreferences prefs, _FakeService service) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(service),
  categoryMapProvider.overrideWithValue(
    AsyncData({for (final c in fixtureCategories()) c.id: c}),
  ),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeLoggedIn.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  Future<_FakeService> pumpPage(
    WidgetTester tester, {
    UiVariant variant = UiVariant.lightDefault,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService();
    await pumpUi(
      tester,
      const TagTopicsPage(tagName: 'amex'),
      variant: variant,
      overrides: _overrides(prefs, service),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    addTearDown(() => _unmount(tester));
    return service;
  }

  for (final brightness in Brightness.values) {
    testUi('标签话题列表：标题是标签名，请求带这个标签，列表行带分类名（${brightness.name}）', (
      tester,
    ) async {
      final service = await pumpPage(
        tester,
        variant: UiVariant(brightness, 1, UiDevice.proMax),
      );
      expectNoUiException(tester);
      // 导航标题 = #标签名；请求的标签就是它
      expect(find.text('#amex'), findsOneWidget);
      expect(service.requests.first.$1, 'latest');
      expect(service.requests.first.$2, ['amex']);
      expect(find.byType(TopicRow), findsWidgets);
      // 行里的元信息带分类名（标签下的话题来自各个分类）
      expect(find.textContaining('信用卡'), findsWidgets);
      await uiShot(tester, 'tag_topics_${brightness.name}');
    });
  }

  testUi('筛选胶囊行：「最新」「默认排序」两个 32 高胶囊，左边距 20，间距 8', (tester) async {
    await pumpPage(tester);
    final bar = find.byType(SortAndTagsBar);
    expect(bar, findsOneWidget);
    final pills = find.descendant(of: bar, matching: find.byType(FilterPill));
    expect(pills, findsNWidgets(2), reason: '标签页没有「标签」胶囊');
    final first = find.widgetWithText(FilterPill, '最新');
    final second = find.widgetWithText(FilterPill, '默认排序');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    // 胶囊本体 32 高（FilterPill 外面上下各 6 的透明热区，整体 44）
    expect(tester.getSize(first).height, 44);
    final pillBody = find.descendant(
      of: first,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.minWidth == 44,
      ),
    );
    expect(tester.getSize(pillBody).height, 32);
    expect(tester.getTopLeft(first).dx, 20, reason: '左边距 20');
    expect(
      tester.getTopLeft(second).dx - tester.getTopRight(first).dx,
      8,
      reason: '胶囊间距 8',
    );
    await _unmount(tester);
  });

  testUi('选「创建时间」排序：胶囊换成「创建时间 ↓」并变 brand 色，请求带 order', (tester) async {
    final service = await pumpPage(tester);
    expect(
      tester
          .widget<FilterPill>(find.widgetWithText(FilterPill, '默认排序'))
          .selected,
      isFalse,
    );
    await tester.tap(find.widgetWithText(FilterPill, '默认排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建时间'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    final pill = find.widgetWithText(FilterPill, '创建时间 ↓');
    expect(pill, findsOneWidget);
    expect(tester.widget<FilterPill>(pill).selected, isTrue);
    expect(find.text('默认排序'), findsNothing);
    expect(service.requests.last.$3, TopicSortOrder.created.apiValue);
    await _unmount(tester);
  });

  testUi('选「热门」筛选：胶囊文字换成「热门」，请求按热门取', (tester) async {
    final service = await pumpPage(tester);
    await tester.tap(find.widgetWithText(FilterPill, '最新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('热门'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.widgetWithText(FilterPill, '热门'), findsOneWidget);
    expect(service.requests.last.$1, TopicListFilter.hot.filterName);
    await _unmount(tester);
  });

  testUi('传了添加标签入口时，筛选胶囊行末尾出现「标签」胶囊（分类页用）', (tester) async {
    var taps = 0;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpUi(
      tester,
      Scaffold(
        body: SortAndTagsBar(
          currentFilter: TopicListFilter.latest,
          isLoggedIn: true,
          onFilterChanged: (_) {},
          currentSubset: NewSubset.all,
          onSubsetChanged: (_) {},
          currentOrder: TopicSortOrder.defaultOrder,
          ascending: false,
          onOrderChanged: (_) {},
          onToggleAscending: () {},
          selectedTags: const [],
          onTagRemoved: (_) {},
          onAddTag: () => taps++,
        ),
      ),
      overrides: _overrides(prefs, _FakeService()),
    );
    final pills = find.byType(FilterPill);
    expect(pills, findsNWidgets(3));
    expect(find.widgetWithText(FilterPill, '标签'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterPill, '标签'));
    expect(taps, 1);
  });
}
