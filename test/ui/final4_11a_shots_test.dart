import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/search_filter.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/models/tag_notification_level.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/home/home_topic_list.dart';
import 'package:fluxdo/pages/search_page.dart';
import 'package:fluxdo/pages/tag_topics_page.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_list_events.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/utils/dialog_utils.dart';
import 'package:fluxdo/widgets/common/tag_selection_sheet.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 第 11 批 11a（补充 · 首页与搜索 01–08）的截图：浅 / 深各一张。
// 设置环境变量 SHOTS_DIR 才出图；不设置时只做不抛异常的检查。
// 设备用 iPhone 16 Pro Max（440 宽），和 Figma 稿的画板宽度一致。
// 论坛请求一律是假的，不联网。

/// 首页话题列表：可以卡住下一次加载（下拉刷新态用）、可以记录 loadBefore
class _Probe {
  Completer<void>? gate;
}

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId, this.probe);

  final _Probe probe;

  @override
  Future<List<Topic>> build() async {
    final gate = probe.gate;
    if (gate != null) await gate.future;
    return fixtureTopics();
  }

  @override
  Future<List<int>?> loadBefore(List<int> topicIds) async => const [];
}

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
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

/// 排行榜 / 热门 / 标签页用：所有话题请求都返回夹具话题
class _FakeService implements DiscourseService {
  TopicListResponse _response() =>
      TopicListResponse(topics: fixtureTopics(), tags: const []);

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
  }) async => _response();

  @override
  Future<TopicListResponse> getLatestTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async => _response();

  @override
  Future<TopicListResponse> getHotTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async => _response();

  @override
  Future<TagNotificationLevel> getTagNotificationLevel(String tagName) async =>
      TagNotificationLevel.regular;

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<SearchResult> search({
    required String query,
    int page = 1,
    String? typeFilter,
  }) async => SearchResult.fromJson({
    'posts': const [],
    'topics': const [],
    'users': const [],
    'grouped_search_result': <String, dynamic>{},
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides(
  SharedPreferences prefs, {
  _Probe? probe,
  bool loggedIn = false,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(_FakeService()),
  if (probe != null)
    topicListProvider.overrideWith2((id) => _FakeTopicList(null, probe)),
  categoryMapProvider.overrideWithValue(
    AsyncData({for (final c in fixtureCategories()) c.id: c}),
  ),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  tagsProvider.overrideWith((ref) async => ['chase', 'csr', 'amex']),
  currentUserProvider.overrideWith(loggedIn ? _FakeLoggedIn.new : _FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// 把 `/tags/filter/search` 拦成「没有任何标签」
void _stubEmptyTags() {
  final dio = DiscourseService().dio;
  final stub = InterceptorsWrapper(
    onRequest: (options, handler) => handler.resolve(
      Response(requestOptions: options, data: {'results': <Object>[]}),
    ),
  );
  dio.interceptors.insert(0, stub);
  addTearDown(() => dio.interceptors.remove(stub));
}

void main() {
  setUpAll(loadUiFonts);

  Future<void> pumpHome(
    WidgetTester tester,
    Brightness brightness, {
    Map<String, Object> prefs = const {},
    _Probe? probe,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await SharedPreferences.getInstance();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      variant: UiVariant(brightness, 1.0, UiDevice.proMax),
      overrides: _overrides(store, probe: probe, loggedIn: true),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // 用例失败时也先卸载页面（后注册的先执行，要赶在 pumpUi 还原桌面标记之前）
    addTearDown(() => _unmount(tester));
  }

  for (final b in Brightness.values) {
    final tag = b.name;

    testUi('01 首页 · 下拉刷新中（$tag）', (tester) async {
      final probe = _Probe();
      await pumpHome(tester, b, probe: probe);
      await tester.pumpAndSettle();
      expect(find.byType(TopicRow), findsWidgets);
      // 下一次加载卡住，保持「刷新中」
      probe.gate = Completer<void>();
      await tester.fling(find.byType(TopicRow).first, const Offset(0, 500), 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 等松手后的回弹走完（刷新还没结束，转圈不会静止，不能 pumpAndSettle）
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await uiShot(tester, '01_下拉刷新_$tag');
      probe.gate!.complete();
      await tester.pumpAndSettle();
    });

    testUi('02 首页 · 新话题提示条（$tag）', (tester) async {
      await pumpHome(tester, b, probe: _Probe());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeTopicList)),
      );
      container
          .read(topicListEventsProvider.notifier)
          .publish(
            const TopicListEvent(topicId: 2001, type: 'latest', categoryId: 2),
          );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await uiShot(tester, '02_新话题提示条_$tag');
    });

    testUi('03 首页 · 添加标签 · 无可用标签（$tag）', (tester) async {
      _stubEmptyTags();
      await pumpHome(tester, b, probe: _Probe());
      await tester.pumpAndSettle();
      showAppBottomSheet<List<String>>(
        context: tester.element(find.byType(TopicsPage)),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const TagSelectionSheet(
          categoryId: 7,
          availableTags: [],
          selectedTags: [],
          maxTags: 99,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await uiShot(tester, '03_添加标签_无可用标签_$tag');
    });

    testUi('04 首页 · 热门（$tag）', (tester) async {
      await pumpHome(tester, b, prefs: const {'topic_sort_filter': 'hot'});
      await tester.pumpAndSettle();
      expect(find.text('热门'), findsOneWidget);
      await uiShot(tester, '04_热门_$tag');
    });

    testUi('05 首页 · 排行榜（$tag）', (tester) async {
      await pumpHome(tester, b, prefs: const {'topic_sort_filter': 'top'});
      await tester.pumpAndSettle();
      expect(find.text('排行榜'), findsOneWidget);
      await uiShot(tester, '05_排行榜_$tag');
    });

    testUi('06 标签话题列表 · #amex（$tag）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const TagTopicsPage(tagName: 'amex'),
        variant: UiVariant(b, 1.0, UiDevice.proMax),
        overrides: _overrides(store, loggedIn: true),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('#amex'), findsOneWidget);
      await uiShot(tester, '06_标签话题列表_$tag');
      addTearDown(() => _unmount(tester));
    });

    Future<void> openFilter(
      WidgetTester tester, {
      SearchFilter? filter,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      PreloadedDataService().debugSeed(siteSettings: const {});
      await pumpUi(
        tester,
        SearchPage(
          initialQuery: 'Chase 5/24 规则 2026 最新数据点汇总',
          initialFilter: filter,
        ),
        variant: UiVariant(b, 1.0, UiDevice.proMax),
        overrides: _overrides(store),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.byIcon(AppIcons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      addTearDown(() => _unmount(tester));
    }

    testUi('07 高级筛选 · 时间 · 自定义入口（$tag）', (tester) async {
      await openFilter(tester);
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await uiShot(tester, '07_高级筛选_自定义时间入口_$tag');
    });

    testUi('08 高级筛选 · 时间 · 自定义已选（$tag）', (tester) async {
      await openFilter(
        tester,
        filter: SearchFilter(
          afterDate: DateTime(2025, 1, 1),
          beforeDate: DateTime(2025, 6, 30),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2025-01-01'), findsOneWidget);
      await uiShot(tester, '08_高级筛选_自定义已选_$tag');
    });
  }
}
