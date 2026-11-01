import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/home/top_period_bar.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 补充稿 05「首页 · 排行榜」：标题菜单选「排行榜」后，分类条下加时间段分段控件
// （日 / 周 / 月 / 季 / 年 / 全部），切换后列表按新的时间段重新请求。
// 论坛请求是假服务，按请求里的 period 返回不同标题的话题。

/// 某个时间段对应的那条话题标题（用来看列表到底换没换）
String _titleFor(String period) => '【$period 榜】Chase Sapphire 开卡奖励汇总';

TopicListResponse _responseFor(String period) => TopicListResponse.fromJson({
  'users': fixtureUsersJson,
  'topic_list': {
    'topics': [
      {
        'id': 5000 + period.length,
        'title': _titleFor(period),
        'slug': 'top-$period',
        'posts_count': 12,
        'reply_count': 11,
        'views': 300,
        'like_count': 20,
        'created_at': fixtureTime(const Duration(days: 2)),
        'last_posted_at': fixtureTime(const Duration(hours: 3)),
        'last_poster_username': 'amex_plat',
        'category_id': 1,
        'highest_post_number': 12,
        'posters': [
          {'user_id': 2, 'description': '原始发帖人, 最新发帖人'},
        ],
      },
    ],
  },
});

class _FakeService implements DiscourseService {
  /// 每次取话题的 (filter, period, page)
  final requests = <(String, String?, int)>[];

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
    requests.add((filter, period, page));
    return _responseFor(period ?? 'none');
  }

  @override
  Future<TopicListResponse> getLatestTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async => _responseFor('latest');

  @override
  Future<TopicListResponse> getHotTopics({
    int page = 0,
    String? order,
    bool? ascending,
  }) async => _responseFor('hot');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

List<Override> _overrides(SharedPreferences prefs, _FakeService service) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(service),
  categoryMapProvider.overrideWithValue(
    AsyncData({for (final c in fixtureCategories()) c.id: c}),
  ),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  Future<_FakeService> pumpHome(
    WidgetTester tester, {
    Map<String, Object> prefs = const {'topic_sort_filter': 'top'},
    UiVariant variant = UiVariant.lightDefault,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await SharedPreferences.getInstance();
    final service = _FakeService();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      variant: variant,
      overrides: _overrides(store, service),
    );
    // 用例失败时也先卸载页面（后注册的先执行，要赶在 pumpUi 还原桌面标记之前），
    // 否则页面在桌面标记还原后才销毁，会连带弄坏后面的用例
    addTearDown(() => _unmount(tester));
    await tester.pump(const Duration(milliseconds: 300));
    return service;
  }

  for (final brightness in Brightness.values) {
    testUi('排行榜：分类条下是 日/周/月/季/年/全部 分段控件，默认选中「周」（${brightness.name}）', (
      tester,
    ) async {
      final service = await pumpHome(
        tester,
        variant: UiVariant(brightness, 1, UiDevice.pro),
      );
      expectNoUiException(tester);
      final bar = find.byType(TopPeriodBar);
      expect(bar, findsOneWidget);
      for (final label in ['日', '周', '月', '季', '年', '全部']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: '分段「$label」',
        );
      }
      // 第一次请求是排行榜 + 默认的「周」
      expect(service.requests, [('top', 'weekly', 0)]);
      expect(find.text(_titleFor('weekly')), findsOneWidget);

      // 几何：外框左右 20、上下 8，底 40 高 surface/grouped；选中的块是 surface/page
      final colors = tester.element(bar).tokens.colors;
      final barRect = tester.getRect(bar);
      final track = tester.getRect(
        find.byKey(const ValueKey('top-period-track')),
      );
      expect(track.height, 40);
      expect(track.left - barRect.left, 20);
      expect(barRect.right - track.right, 20);
      expect(track.top - barRect.top, 8);
      final trackBox = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('top-period-track')),
      );
      expect((trackBox.decoration as BoxDecoration).color, colors.surfaceGrouped);
      Color? fillOf(String name) =>
          (tester
                      .widget<DecoratedBox>(find.byKey(ValueKey('top-period-$name')))
                      .decoration
                  as BoxDecoration)
              .color;
      expect(fillOf('weekly'), colors.surfacePage);
      expect(fillOf('monthly'), Colors.transparent);
      // 控件在分类条下面、列表上面
      expect(
        barRect.top,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(FilterTabs)).dy),
      );
      expect(
        barRect.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TopicRow).first).dy),
      );
      await uiShot(tester, 'home_top_period_${brightness.name}');
    });
  }

  testUi('点「月」：选中块换到「月」，列表按月榜重新请求并显示月榜话题，选择被记住', (tester) async {
    final service = await pumpHome(tester);
    expect(find.text(_titleFor('weekly')), findsOneWidget);

    await tester.tap(find.text('月'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.requests.last, ('top', 'monthly', 0));
    expect(service.requests, hasLength(2));
    expect(find.text(_titleFor('monthly')), findsOneWidget);
    expect(find.text(_titleFor('weekly')), findsNothing);
    final colors = tester.element(find.byType(TopPeriodBar)).tokens.colors;
    Color? fillOf(String name) =>
        (tester
                    .widget<DecoratedBox>(find.byKey(ValueKey('top-period-$name')))
                    .decoration
                as BoxDecoration)
            .color;
    expect(fillOf('monthly'), colors.surfacePage);
    expect(fillOf('weekly'), Colors.transparent);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TopPeriodBar)),
    );
    expect(container.read(topPeriodProvider), TopPeriod.monthly);
    expect(
      (await SharedPreferences.getInstance()).getString('topic_top_period'),
      'monthly',
    );
  });

  testUi('每一段都对应各自的 period 参数；再点已选的一段不重复请求', (tester) async {
    final service = await pumpHome(tester);
    for (final (label, period) in [
      ('日', 'daily'),
      ('季', 'quarterly'),
      ('年', 'yearly'),
      ('全部', 'all'),
      ('周', 'weekly'),
    ]) {
      await tester.tap(find.descendant(
        of: find.byType(TopPeriodBar),
        matching: find.text(label),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.requests.last, ('top', period, 0), reason: '点「$label」');
      expect(find.text(_titleFor(period)), findsOneWidget);
    }
    final before = service.requests.length;
    await tester.tap(find.text('周'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.requests, hasLength(before), reason: '再点已选的一段不重新请求');
  });

  testUi('上次选的时间段会带回来', (tester) async {
    final service = await pumpHome(
      tester,
      prefs: const {'topic_sort_filter': 'top', 'topic_top_period': 'yearly'},
    );
    expect(service.requests, [('top', 'yearly', 0)]);
    expect(find.text(_titleFor('yearly')), findsOneWidget);
  });

  testUi('不是排行榜时没有分段控件（最新、热门都没有）', (tester) async {
    await pumpHome(tester, prefs: const {'topic_sort_filter': 'latest'});
    expect(find.byType(TopPeriodBar), findsNothing);
    await _unmount(tester);
    await pumpHome(tester, prefs: const {'topic_sort_filter': 'hot'});
    expect(find.byType(TopPeriodBar), findsNothing);
  });

  // 补充稿 04「首页 · 热门」：标题菜单选「热门」后的列表，结构同「最新」
  for (final brightness in Brightness.values) {
    testUi('标题菜单选「热门」：标题变「热门」，列表换成热门话题，没有时间段控件（${brightness.name}）', (
      tester,
    ) async {
      await pumpHome(
        tester,
        prefs: const {},
        variant: UiVariant(brightness, 1, UiDevice.pro),
      );
      expect(find.text(_titleFor('latest')), findsOneWidget);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('热门'));
      await tester.pumpAndSettle();
      expect(find.text('热门'), findsOneWidget, reason: '标题已经是「热门」');
      expect(find.text('最新'), findsNothing);
      expect(find.text(_titleFor('hot')), findsOneWidget);
      expect(find.byType(TopPeriodBar), findsNothing);
      expect(find.byType(TopicRow), findsWidgets);
      await uiShot(tester, 'home_hot_${brightness.name}');
    });
  }

  testUi('标题菜单选「排行榜」：出现分段控件，列表按默认的「周」取排行榜', (tester) async {
    final service = await pumpHome(tester, prefs: const {});
    expect(find.byType(TopPeriodBar), findsNothing);
    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(find.byType(TopPeriodBar), findsOneWidget);
    expect(service.requests.last, ('top', 'weekly', 0));
    expect(find.text(_titleFor('weekly')), findsOneWidget);
  });
}
