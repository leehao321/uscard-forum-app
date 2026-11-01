import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/badge.dart' as badge_model;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/category_topics_page.dart';
import 'package:fluxdo/pages/my_topics_page.dart';
import 'package:fluxdo/pages/private_messages_page.dart';
import 'package:fluxdo/pages/tag_topics_page.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/filter_active_dot.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/pages/topics_screen.dart'
    show invalidateTopicListsAfterCreate;
import 'package:fluxdo/providers/bookmark_sync_controller.dart';
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/services/network/quiet_request.dart';
import 'package:fluxdo/pages/badge_page.dart';
import 'package:fluxdo/pages/follow_list_page.dart';
import 'package:fluxdo/pages/user_profile_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/post/post_item/segmented_long_post.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// Gemini 审阅核实 B（第二批）：L-3 分段长帖长按菜单、M-3 徽章页、L-4 关注页空状态、
// M-4 用户主页大字号。服务一律是假的，不碰论坛。

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

List<Override> _base(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  categoriesProvider.overrideWith((ref) async => fixtureCategories()),
  currentUserProvider.overrideWith(_FakeUser.new),
  messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
  topicTrackingStateProvider.overrideWith(_FakeTracking.new),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

// ---------------- 假服务 ----------------

class _BadgeService implements DiscourseService {
  _BadgeService({this.fail = false, this.gate});

  final bool fail;
  final Completer<void>? gate;

  @override
  Future<badge_model.Badge> getBadge({required int badgeId}) async {
    await gate?.future;
    if (fail) throw Exception('断网');
    return badge_model.Badge.fromJson({
      'id': badgeId,
      'name': '精彩的话题',
      'description': '话题获得了很多赞',
      'badge_type_id': 3,
      'grant_count': 2,
    });
  }

  @override
  Future<badge_model.BadgeDetailResponse> getBadgeUsers({
    required int badgeId,
    String? username,
    int offset = 0,
    QuietRequest? quiet,
  }) async {
    return badge_model.BadgeDetailResponse.fromJson({
      'badges': [
        {
          'id': badgeId,
          'name': '精彩的话题',
          'description': '话题获得了很多赞',
          'badge_type_id': 3,
          'grant_count': 2,
        },
      ],
      'users': [
        {
          'id': 1,
          'username': 'alice',
          'avatar_template': '',
          'trust_level': 1,
        },
      ],
      'user_badge_info': {
        'grant_count': 2,
        'user_badges': [
          {
            'id': 10,
            'badge_id': badgeId,
            'user_id': 1,
            'granted_at': '2026-10-01T00:00:00.000Z',
          },
          // 授予人 id 对不上 grantedBies：不能拿第一个无关的人顶替
          {
            'id': 11,
            'badge_id': badgeId,
            'user_id': 99,
            'granted_at': '2026-10-02T00:00:00.000Z',
          },
        ],
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FollowService implements DiscourseService {
  int loads = 0;

  @override
  Future<List<FollowUser>> getFollowing(String username) async {
    loads++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ProfileService implements DiscourseService {
  @override
  Future<User> getUser(String username, {bool isSilent = false, QuietRequest? quiet}) async => User.fromJson({
    'id': 99,
    'username': username,
    'name': '一个名字很长很长很长很长的测试用户',
    'avatar_template': '',
    'trust_level': 2,
    'title': '社区老朋友',
    'location': '纽约',
    'website': 'https://example.com/a/very/long/profile/link',
    'bio_excerpt':
        '玩卡好几年了，主要研究酒店和航司的联名卡，也写一些开卡奖励的时间线。'
        '欢迎私信交流，不接受代办。',
    'created_at': '2020-01-01T00:00:00.000Z',
    'last_seen_at': '2026-10-30T00:00:00.000Z',
    'badge_count': 12,
  });

  @override
  Future<UserSummary> getUserSummary(
    String username, {
    bool forceRefresh = false,
    QuietRequest? quiet,
  }) async => UserSummary.fromJson({'user_summary': <String, dynamic>{}});

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadUiFonts);

  group('L-3 分段长帖：头部 / 空白处长按也有楼层菜单', () {
    testUi('页脚还没滚进来，长按头部就弹出同一份菜单', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final detail = fixtureTopicDetail();
      final post = detail.postStream.posts.first;
      LongPostFooterSegment footer({bool menuOnly = false}) =>
          LongPostFooterSegment(
            menuOnly: menuOnly,
            post: post,
            topicId: detail.id,
            selected: false,
            highlight: false,
            topicHasAcceptedAnswer: false,
            bottomDateSeparatorLabel: null,
            onReply: null,
            onEdit: null,
            onShareAsImage: null,
            onRefreshPost: null,
            onJumpToPost: null,
            onSolutionChanged: null,
          );
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            // 页脚段在很下面，没有被构建
            child: Column(
              children: [
                LongPostHeaderSegment(
                  menuHost: footer(menuOnly: true),
                  post: post,
                  topicId: detail.id,
                  selected: false,
                  highlight: false,
                  isTopicOwner: true,
                  dateSeparatorLabel: null,
                  showDivider: false,
                  onJumpToPost: null,
                ),
                const SizedBox(height: 3000),
              ],
            ),
          ),
        ),
        overrides: _base(prefs),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('分享链接'), findsNothing);

      await tester.longPress(find.text('张三'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('分享链接'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppMenuPanel<VoidCallback>),
          matching: find.text('添加笔记'),
        ),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });

  group('L-3 长帖：两份页脚读同一份状态', () {
    testUi('在页脚里加了书签，长按菜单里立刻是「编辑书签」', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final detail = fixtureTopicDetail();
      final post = detail.postStream.posts.first;
      LongPostFooterSegment footer({bool menuOnly = false}) =>
          LongPostFooterSegment(
            menuOnly: menuOnly,
            post: post,
            topicId: detail.id,
            selected: false,
            highlight: false,
            topicHasAcceptedAnswer: false,
            bottomDateSeparatorLabel: null,
            onReply: null,
            onEdit: null,
            onShareAsImage: null,
            onRefreshPost: null,
            onJumpToPost: null,
            onSolutionChanged: null,
          );
      await pumpUi(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                LongPostHeaderSegment(
                  menuHost: footer(menuOnly: true),
                  post: post,
                  topicId: detail.id,
                  selected: false,
                  highlight: false,
                  isTopicOwner: true,
                  dateSeparatorLabel: null,
                  showDivider: false,
                  onJumpToPost: null,
                ),
                footer(),
              ],
            ),
          ),
        ),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoriesProvider.overrideWith((ref) async => fixtureCategories()),
          messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
          topicTrackingStateProvider.overrideWith(_FakeTracking.new),
          currentUserProvider.overrideWith(_FakeLoggedInUser.new),
          discourseServiceProvider.overrideWithValue(_PostBookmarkService()),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));

      // 先在页脚的「⋯」菜单里加书签
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('添加书签'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      // 书签编辑半屏可能已弹出：关掉
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (navigator.canPop()) navigator.pop();
      await tester.pump(const Duration(milliseconds: 600));

      // 再长按头部：菜单里应该是「编辑书签」，不再是「添加书签」
      await tester.longPress(find.text('张三'));
      await tester.pump(const Duration(milliseconds: 500));
      final menu = find.byType(AppMenuPanel<VoidCallback>);
      expect(menu, findsOneWidget);
      expect(
        find.descendant(of: menu, matching: find.text('编辑书签')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('添加书签')),
        findsNothing,
      );
      await _unmount(tester);
    });
  });

  group('退出页面时 dispose 不抛 StateError', () {
    testUi('用户主页：退出后没有异常，控制器都被释放', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const UserProfilePage(username: 'hao'),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(_ProfileService()),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      // 整页卸载：dispose 里不能再碰 ref（旧代码在这里抛 StateError，
      // 后面的 TabController / ScrollController 也没释放）
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testUi('我的话题：退出后延迟清搜索状态不抛 StateError', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const MyTopicsPage(),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(_ListService()),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // 延迟的 Future 在这里跑：搜索状态已经随页面销毁
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('M-3 徽章页', () {
    testUi('加载中和出错态都有带返回键的导航栏', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<void>();
      await pumpUi(
        tester,
        const BadgePage(badgeId: 20),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(
            _BadgeService(gate: gate),
          ),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppNavBar), findsOneWidget, reason: '加载中');
      gate.complete();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);

      await pumpUi(
        tester,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const BadgePage(badgeId: 20),
          ),
        ),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(
            _BadgeService(fail: true),
          ),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AppNavBar), findsOneWidget, reason: '出错');
      await _unmount(tester);
    });

    testUi('授予人对不上时不拿第一个无关的人顶替；走的是注入的服务', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const BadgePage(badgeId: 20),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(_BadgeService()),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      // 两条记录里只有 user_id = 1 的能对上授予人 alice
      expect(find.text('alice'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('L-4 关注页', () {
    testUi('空状态也能下拉刷新', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = _FollowService();
      await pumpUi(
        tester,
        const FollowListPage(username: 'hao', isFollowing: true),
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(service),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(service.loads, 1);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(service.loads, 2, reason: '下拉应当重新加载');
      await _unmount(tester);
    });
  });

  group('M-4 / ④ 用户主页头部在大字号下', () {
    for (final scale in [1.35, 2.0]) {
      for (final device in [UiDevice.pro, UiDevice.proMax]) {
        testUi('$scale 倍 × ${device.name}：不溢出，内容不顶进状态栏', (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final variant = UiVariant(Brightness.light, scale, device);
          await pumpUi(
            tester,
            const UserProfilePage(username: 'hao'),
            variant: variant,
            overrides: [
              ..._base(prefs),
              discourseServiceProvider.overrideWithValue(_ProfileService()),
            ],
            settle: false,
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
          final ex = tester.takeException();
          expect(ex, isNull);
          // 名字（头部里最上面的一行内容）不能压到顶栏（状态栏 + 56）里
          final name = find.text('一个名字很长很长很长很长的测试用户');
          expect(name, findsWidgets);
          final toolbarBottom = device.padding.top + kToolbarHeight;
          final top = tester.getTopLeft(name.first).dy;
          expect(
            top,
            greaterThanOrEqualTo(toolbarBottom - 1),
            reason: '名字在 $top，顶栏到 $toolbarBottom',
          );
          await uiShot(tester, 'user_profile_${scale}x_${device.name}');
          await _unmount(tester);
        });
      }
    }
  });

  group('M-6 列表页：行的实际左右内边距 = 20（不再叠外层 12）', () {
    Future<void> check(WidgetTester tester, Widget page) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        page,
        overrides: [
          ..._base(prefs),
          discourseServiceProvider.overrideWithValue(_ListService()),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      final row = find.byType(TopicRow);
      expect(row, findsWidgets);
      // 行铺满整宽（外层列表没有水平内边距）；行内左右各 20 的边距由行自己给
      final screen = UiDevice.proMax.size.width;
      expect(tester.getTopLeft(row.first).dx, 0);
      expect(tester.getSize(row.first).width, screen);
      final title = find.descendant(
        of: row.first,
        matching: find.byType(RichText),
      );
      final firstText = tester.getTopLeft(title.first).dx;
      expect(firstText, closeTo(20, 0.5), reason: '行内文字左缘应该是 20');
      await _unmount(tester);
    }

    testUi('我的话题', (tester) => check(tester, const MyTopicsPage()));
    testUi('私信', (tester) => check(tester, const PrivateMessagesPage()));
    testUi(
      '分类详情',
      (tester) => check(
        tester,
        CategoryTopicsPage(category: fixtureCategories().first),
      ),
    );
    testUi(
      '标签详情',
      (tester) => check(tester, const TagTopicsPage(tagName: 'chase')),
    );
  });

  group('M-7 首页', () {
    testUi('加入书签后静默拉一次书签列表第一页', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sync = _CountingBookmarkSync();
      final topics = [
        for (final t in fixtureTopics().where((t) => !t.pinned).take(2)) t,
      ];
      await pumpUi(
        tester,
        Scaffold(body: TopicsPage(onCreateTopic: () {})),
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoriesProvider.overrideWith((ref) async => fixtureCategories()),
          messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
          topicTrackingStateProvider.overrideWith(_FakeTracking.new),
          currentUserProvider.overrideWith(_FakeLoggedIn.new),
          discourseServiceProvider.overrideWithValue(_BookmarkService()),
          topicListProvider.overrideWith2((_) => _FakeTopicList(null, topics)),
          bookmarkSyncControllerProvider.overrideWith(() => sync),
          categoryMapProvider.overrideWithValue(
            AsyncData({for (final c in fixtureCategories()) c.id: c}),
          ),
        ],
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.longPress(
        find.byWidgetPredicate(
          (w) => w is TopicRow && w.topic.id == topics.first.id,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('书签'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sync.pulls, 1, reason: '加书签后要把书签列表第一页拉下来');
      await _unmount(tester);
    });

    testUi('在分类 tab 发帖后，这个分类的列表也刷新', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final builds = <int?, int>{};
      await pumpUi(
        tester,
        Consumer(
          builder: (context, ref, _) {
            return TextButton(
              onPressed: () => invalidateTopicListsAfterCreate(ref, 11),
              child: const Text('发帖完成'),
            );
          },
        ),
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          topicListProvider.overrideWith2(
            (key) => _CountingTopicList(key, () {
              builds[key] = (builds[key] ?? 0) + 1;
            }),
          ),
        ],
        settle: false,
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.text('发帖完成')),
      );
      container.listen(topicListProvider(null), (_, _) {});
      container.listen(topicListProvider(11), (_, _) {});
      await tester.pump();
      expect(builds[null], 1);
      expect(builds[11], 1);
      await tester.tap(find.text('发帖完成'));
      await tester.pump();
      await tester.pump();
      expect(builds[null], 2, reason: '全部 tab 刷新');
      expect(builds[11], 2, reason: '当前分类的列表也要刷新');
      await _unmount(tester);
    });
  });

  group('M-9 阅读页 ⋮', () {
    testUi('筛选开着时右上角亮点，关掉就没有', (tester) async {
      Widget host(bool active) => Scaffold(
        body: Center(
          child: FilterActiveDot(
            active: active,
            child: const SizedBox(width: 44, height: 44),
          ),
        ),
      );
      await pumpUi(tester, host(false), settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('filter-active-dot')), findsNothing);
      await _unmount(tester);
      await pumpUi(tester, host(true), settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('filter-active-dot')), findsOneWidget);
      await _unmount(tester);
    });
  });
}

class _ListService implements DiscourseService {
  TopicListResponse _page() => TopicListResponse(
    topics: fixtureTopics().where((t) => !t.pinned).toList(),
  );

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
  }) async => _page();

  @override
  Future<TopicListResponse> getUserCreatedTopics({int page = 0}) async =>
      _page();

  @override
  Future<TopicListResponse> getPrivateMessages({int page = 0}) async =>
      _page();

  @override
  Future<TopicListResponse> getPrivateMessagesSent({int page = 0}) async =>
      _page();

  @override
  Future<TopicListResponse> getPrivateMessagesArchive({int page = 0}) async =>
      _page();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _BookmarkService implements DiscourseService {
  @override
  Future<int> bookmarkTopic(
    int topicId, {
    String? name,
    DateTime? reminderAt,
    int? autoDeletePreference,
  }) async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingBookmarkSync extends BookmarkSyncController {
  int pulls = 0;

  @override
  Future<void> pullFirstPage() async {
    pulls++;
  }
}

class _FakeLoggedIn extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId, this.topics);

  final List<Topic> topics;

  @override
  Future<List<Topic>> build() async => topics;
}

class _CountingTopicList extends TopicListNotifier {
  _CountingTopicList(super.categoryId, this.onBuild);

  final VoidCallback onBuild;

  @override
  Future<List<Topic>> build() async {
    onBuild();
    return const [];
  }
}

class _FakeLoggedInUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _PostBookmarkService implements DiscourseService {
  @override
  Future<int> bookmarkPost(
    int postId, {
    String? name,
    DateTime? reminderAt,
    int? autoDeletePreference,
  }) async => 77;

  @override
  Future<String?> getUsername() async => 'hao';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
