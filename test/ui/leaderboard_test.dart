import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/site_customization.dart';
import 'package:fluxdo/config/sites/uscard.dart';
import 'package:fluxdo/models/badge.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/home/category_bar.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/leaderboard_provider.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.6：首页分类条「全部 · 精彩 · 难绷 | 分类…」与徽章榜单。
// 论坛请求一律是假服务，不碰真站。

class _FakeService implements DiscourseService {
  _FakeService(this.script);

  final Future<BadgeTopicsPage> Function(int badgeId, int offset) script;
  final calls = <(int, int)>[];

  @override
  Future<BadgeTopicsPage> getBadgeTopicsPage({
    required int badgeId,
    int offset = 0,
    int limit = BadgeTopicsPage.pageSize,
  }) {
    calls.add((badgeId, offset));
    return script(badgeId, offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId);

  @override
  Future<List<Topic>> build() async => fixtureTopics();
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

BadgeTopicEntry _entry(int id, {String? author = '小李'}) => BadgeTopicEntry(
  topicId: id,
  title: '第 $id 个精彩的话题：Chase Sapphire Reserve 新开卡奖励 125k，附申请时间线',
  postNumber: 1,
  author: author,
  grantedAt: DateTime(2026, 10, 1).add(Duration(hours: id)),
  postsCount: id + 1,
);

BadgeTopicsPage _page(Iterable<int> ids, {required bool hasMore}) =>
    BadgeTopicsPage(
      entries: [for (final id in ids) _entry(id)],
      fetchedCount: ids.length,
      hasMore: hasMore,
    );

List<Override> _overrides(SharedPreferences prefs, _FakeService service) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(service),
  topicListProvider.overrideWith2((_) => _FakeTopicList(null)),
  categoryMapProvider.overrideWithValue(
    AsyncData({for (final c in fixtureCategories()) c.id: c}),
  ),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

Future<_FakeService> _pumpHome(
  WidgetTester tester,
  Future<BadgeTopicsPage> Function(int badgeId, int offset) script, {
  UiVariant variant = UiVariant.lightDefault,
}) async {
  SharedPreferences.setMockInitialValues({
    'pinned_category_ids': ['1', '2', '3'],
  });
  final prefs = await SharedPreferences.getInstance();
  final service = _FakeService(script);
  await pumpUi(
    tester,
    Scaffold(body: TopicsPage(onCreateTopic: () {})),
    variant: variant,
    overrides: _overrides(prefs, service),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return service;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

LeaderboardKind? _mode(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(TopicsPage)),
).read(homeBrowseModeProvider);

/// 分类条里选中的是第几项
int _barIndex(WidgetTester tester) =>
    tester.widget<FilterTabs>(find.byType(FilterTabs)).selectedIndex;

void main() {
  setUpAll(loadUiFonts);

  group('解析', () {
    test('跳过没有话题的记录；offset 按服务端返回条数推进；回复数不含首帖', () {
      final page = BadgeTopicsPage.fromJson({
        'topics': [
          {'id': 11, 'title': '甲', 'posts_count': 8},
          {'id': 12, 'title': '乙', 'posts_count': 1},
        ],
        'users': [
          {'id': 1, 'username': 'lee', 'name': '小李'},
          {'id': 2, 'username': 'wang', 'name': ''},
        ],
        'user_badge_info': {
          'user_badges': [
            {
              'id': 1,
              'topic_id': 11,
              'post_number': 3,
              'user_id': 1,
              'granted_at': '2026-10-01T08:00:00.000Z',
            },
            // 看不到的话题：服务端不带 topic_id
            {'id': 2, 'user_id': 1, 'granted_at': '2026-10-01T08:00:00.000Z'},
            {
              'id': 3,
              'topic_id': 12,
              'user_id': 2,
              'granted_at': '2026-09-30T08:00:00.000Z',
            },
          ],
        },
      }, limit: 3);
      expect(page.fetchedCount, 3);
      expect(page.hasMore, isTrue);
      expect(page.entries.map((e) => e.topicId), [11, 12]);
      expect(page.entries[0].author, '小李');
      expect(page.entries[0].postNumber, 3);
      expect(page.entries[0].replyCount, 7);
      // 没有显示名时退回用户名
      expect(page.entries[1].author, 'wang');
      expect(page.entries[1].replyCount, 0);
    });

    test('不满一页就没有下一页', () {
      final page = BadgeTopicsPage.fromJson({
        'user_badge_info': {'user_badges': <dynamic>[]},
      });
      expect(page.hasMore, isFalse);
      expect(page.entries, isEmpty);
    });
  });

  group('隐藏项与去重', () {
    test('站点没配徽章的榜单不出现（分类条和菜单都读这个），都没有就只剩「全部」', () {
      expect(leaderboardsFor(const SiteCustomization()), isEmpty);
      expect(leaderboardsFor(const SiteCustomization(greatTopicBadgeId: 20)), [
        LeaderboardKind.great,
      ]);
      expect(leaderboardsFor(const SiteCustomization(funnyTopicBadgeId: 115)), [
        LeaderboardKind.funny,
      ]);
      expect(leaderboardsFor(uscardCustomization), [
        LeaderboardKind.great,
        LeaderboardKind.funny,
      ]);
      expect(uscardCustomization.greatTopicBadgeId, 20);
      expect(uscardCustomization.funnyTopicBadgeId, 115);
    });

    test('按 topic_id 去重，保留先出现的', () {
      final merged = LeaderboardNotifier.mergeUnique(
        [_entry(1), _entry(2)],
        [_entry(2), _entry(3)],
      );
      expect(merged.map((e) => e.topicId), [1, 2, 3]);
    });
  });

  group('首页模式切换', () {
    testUi('分类条：全部 · 精彩 · 难绷 | 分类…，竖线在难绷后', (tester) async {
      await _pumpHome(tester, (b, o) async => _page([1], hasMore: false));
      final tabs = tester.widget<FilterTabs>(find.byType(FilterTabs));
      expect(tabs.labels.take(3), ['全部', '精彩', '难绷']);
      expect(tabs.labels.length, 3 + 3);
      expect(tabs.dividerAfter, 2);
      expect(tabs.selectedIndex, 0);
      expect(find.byType(HomeCategoryBar), findsOneWidget);
      await _unmount(tester);
    });

    testUi('选精彩：列表换成徽章 #20 的榜单；选分类回到普通列表；再选难绷用 #115', (tester) async {
      final service = await _pumpHome(
        tester,
        (b, o) async => _page([1, 2, 3], hasMore: false),
      );
      // 没选榜单之前不请求
      expect(service.calls, isEmpty);

      await tester.tap(find.text('精彩'));
      await _settle(tester);
      expect(service.calls, [(20, 0)]);
      expect(_mode(tester), LeaderboardKind.great);
      expect(_barIndex(tester), 1);
      expect(find.byType(TopicRow), findsNWidgets(3));
      // 行：meta 是「作者 · 获得于 日期 · N 回复」，不显示赞 / 回复数
      expect(find.textContaining('小李 · 获得于 '), findsWidgets);
      expect(find.textContaining('1 回复'), findsOneWidget);
      expect(find.byIcon(AppIcons.heart), findsNothing);

      // 再选难绷：换成徽章 #115
      await tester.tap(find.text('难绷'));
      await _settle(tester);
      expect(service.calls.last, (115, 0));
      expect(_mode(tester), LeaderboardKind.funny);
      expect(_barIndex(tester), 2);

      // 选分类：回到普通列表（榜单不再请求）
      final cat = fixtureCategories().firstWhere((c) => c.id == 1).name;
      await tester.tap(find.text(cat).first);
      await _settle(tester);
      expect(_mode(tester), isNull);
      expect(_barIndex(tester), 3);
      expect(find.textContaining('获得于'), findsNothing);
      expect(service.calls.length, 2);

      // 分类条选中分类后会滚到该项，先拖回最左再点「全部」
      await tester.drag(find.byType(FilterTabs), const Offset(800, 0));
      await _settle(tester);
      await tester.tap(find.text('全部').first);
      await _settle(tester);
      expect(_mode(tester), isNull);
      expect(_barIndex(tester), 0);
      await _unmount(tester);
    });

    testUi('标题菜单的「浏览方式」和分类条同一个状态', (tester) async {
      await _pumpHome(tester, (b, o) async => _page([1], hasMore: false));
      // 菜单里选精彩 → 分类条跟着选中
      await tester.tap(find.text('最新'));
      await tester.pump(const Duration(milliseconds: 400));
      final inMenu = find.descendant(
        of: find.byType(AppMenuPanel<Object>),
        matching: find.text('精彩'),
      );
      expect(inMenu, findsOneWidget);
      await tester.tap(inMenu);
      await _settle(tester);
      expect(_mode(tester), LeaderboardKind.great);
      expect(_barIndex(tester), 1);

      // 分类条选难绷 → 菜单里打勾的是难绷，且榜单模式下菜单只剩这一组
      await tester.tap(find.text('难绷'));
      await _settle(tester);
      await tester.tap(find.text('最新'));
      await tester.pump(const Duration(milliseconds: 400));
      final panel = tester.widget<AppMenuPanel<Object>>(
        find.byType(AppMenuPanel<Object>),
      );
      expect(panel.sections.length, 1);
      expect(
        [for (final i in panel.sections.first) (i.label, i.checked)],
        [('全部', false), ('精彩', false), ('难绷', true)],
      );
      // 菜单里选「全部」→ 回到普通列表、分类条选中全部
      await tester.tap(
        find.descendant(
          of: find.byType(AppMenuPanel<Object>),
          matching: find.text('全部'),
        ),
      );
      await _settle(tester);
      expect(_mode(tester), isNull);
      expect(_barIndex(tester), 0);
      await _unmount(tester);
    });
  });

  group('分页与刷新', () {
    testUi('拖到底才请求下一页，offset 按返回条数推进，重复的话题只留一条', (tester) async {
      final service = await _pumpHome(tester, (badge, offset) async {
        if (offset == 0) {
          return _page(List.generate(96, (i) => i + 1), hasMore: true);
        }
        // 第二页：前两条和第一页重复
        return _page([95, 96, 97, 98], hasMore: false);
      });
      await tester.tap(find.text('精彩'));
      await _settle(tester);
      expect(service.calls, [(20, 0)]);

      final scrollable = find.byType(Scrollable).last;
      for (var i = 0; i < 40 && service.calls.length < 2; i++) {
        await tester.drag(scrollable, const Offset(0, -2000));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _settle(tester);
      expect(service.calls, [(20, 0), (20, 96)]);

      final state = ProviderScope.containerOf(
        tester.element(find.byType(TopicsPage)),
      ).read(leaderboardProvider(LeaderboardKind.great)).requireValue;
      expect(state.entries.length, 98);
      expect(state.offset, 100);
      expect(state.hasMore, isFalse);
      await _unmount(tester);
    });

    testUi('下拉刷新从第一页重取', (tester) async {
      final service = await _pumpHome(
        tester,
        (b, o) async => _page([1, 2, 3], hasMore: false),
      );
      await tester.tap(find.text('精彩'));
      await _settle(tester);
      expect(service.calls, [(20, 0)]);

      await tester.fling(
        find.byType(Scrollable).last,
        const Offset(0, 400),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      expect(service.calls.length, greaterThan(1));
      expect(service.calls.every((c) => c == (20, 0)), isTrue);
      await _unmount(tester);
    });
  });

  group('状态', () {
    testUi('出错显示共享错误状态，没登录时给登录入口，重试会再请求', (tester) async {
      var fail = true;
      final service = await _pumpHome(tester, (badge, offset) async {
        if (fail) throw StateError('boom');
        return _page([1], hasMore: false);
      });
      await tester.tap(find.text('精彩'));
      await _settle(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('重试'));
      await _settle(tester);
      expect(service.calls.length, 2);
      expect(find.byType(ErrorView), findsNothing);
      expect(find.textContaining('第 1 个'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('空榜单显示说明', (tester) async {
      await _pumpHome(
        tester,
        (b, o) async =>
            const BadgeTopicsPage(entries: [], fetchedCount: 0, hasMore: false),
      );
      await tester.tap(find.text('难绷'));
      await _settle(tester);
      expect(find.text('榜上还没有帖子'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('3 秒还没响应就出「正在等待论坛响应」', (tester) async {
      final completer = Completer<BadgeTopicsPage>();
      await _pumpHome(tester, (b, o) => completer.future);
      await tester.tap(find.text('精彩'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('正在等待论坛响应'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('正在等待论坛响应'), findsOneWidget);
      completer.complete(_page([1], hasMore: false));
      await tester.pump(const Duration(milliseconds: 100));
      await _unmount(tester);
    });

    testUi('行的朗读：标题、作者、获得日期、回复数', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(tester, (b, o) async => _page([5], hasMore: false));
      await tester.tap(find.text('精彩'));
      await _settle(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'小李 · 获得于 .* · 5 回复')),
        findsOneWidget,
      );
      handle.dispose();
      await _unmount(tester);
    });
  });

  group('全矩阵（选中精彩 / 难绷）', () {
    for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
      testUi('不溢出且可访问（${variant.label}）', (tester) async {
        await _pumpHome(
          tester,
          (b, o) async => _page([1, 2, 3, 4, 5, 6], hasMore: false),
          variant: variant,
        );
        final label = variant.brightness == Brightness.light ? '精彩' : '难绷';
        await tester.tap(find.text(label));
        await _settle(tester);
        expectNoUiException(tester);
        await expectUiAccessibility(tester, textContrast: false);
        await uiShot(tester, 'leaderboard_home_${variant.label}');
        await _unmount(tester);
      });
    }
  });
}
