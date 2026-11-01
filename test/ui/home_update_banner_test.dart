import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
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
import 'package:fluxdo/providers/message_bus/topic_list_events.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/widgets/topic/topic_list_update_banner.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 补充稿 02「首页 · 新话题提示条」：有新的或更新的话题时出现在分类条下方，文案不显示数量，
// 点按后加载新话题、插到列表最前并回到顶部。不碰网络：话题列表、分类、用户都是假数据。

/// 新话题（点按后插入的那条）
const _freshTitle = '刚刚有人发的新话题：Citi 新卡首刷奖励';

List<Topic> _freshTopics() => TopicListResponse.fromJson({
  'users': fixtureUsersJson,
  'topic_list': {
    'topics': [
      {
        'id': 2001,
        'title': _freshTitle,
        'slug': 'fresh',
        'posts_count': 1,
        'reply_count': 0,
        'views': 1,
        'like_count': 0,
        'created_at': fixtureTime(const Duration(seconds: 10)),
        'last_posted_at': fixtureTime(const Duration(seconds: 10)),
        'last_poster_username': 'Wanderer',
        'category_id': 2,
        'highest_post_number': 1,
        'posters': [
          {'user_id': 4, 'description': '原始发帖人, 最新发帖人'},
        ],
      },
    ],
  },
}).topics;

/// 凑够一屏以上的行，列表才能滚动
List<Topic> _fillerTopics(int count) => TopicListResponse.fromJson({
  'users': fixtureUsersJson,
  'topic_list': {
    'topics': [
      for (var i = 0; i < count; i++)
        {
          'id': 3000 + i,
          'title': '凑数话题 $i：信用卡申请经验分享',
          'slug': 'filler-$i',
          'posts_count': 3,
          'reply_count': 2,
          'views': 10,
          'like_count': 1,
          'created_at': fixtureTime(Duration(days: 5 + i)),
          'last_posted_at': fixtureTime(Duration(days: 4 + i)),
          'last_poster_username': 'Wanderer',
          'category_id': 2,
          'highest_post_number': 3,
          'posters': [
            {'user_id': 4, 'description': '原始发帖人, 最新发帖人'},
          ],
        },
    ],
  },
}).topics;

/// 记录 loadBefore 调用、可以用 [gate] 卡住它的话题列表
class _Probe {
  final calls = <List<int>>[];
  Completer<void>? gate;
}

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId, this.probe);

  final _Probe probe;

  @override
  Future<List<Topic>> build() async => [
    ...fixtureTopics(),
    ..._fillerTopics(15),
  ];

  @override
  Future<List<int>?> loadBefore(List<int> topicIds) async {
    probe.calls.add(topicIds);
    await probe.gate?.future;
    final fresh = _freshTopics();
    state = AsyncData([...fresh, ...state.value!]);
    return [for (final t in fresh) t.id];
  }
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

List<Override> _overrides(SharedPreferences prefs, _Probe probe) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  topicListProvider.overrideWith2((id) => _FakeTopicList(null, probe)),
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

/// 模拟论坛推来一条新话题消息（和 MessageBus 收到后的效果一样）
void _publishNewTopic(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeTopicList)),
  );
  container
      .read(topicListEventsProvider.notifier)
      .publish(
        const TopicListEvent(topicId: 2001, type: 'latest', categoryId: 2),
      );
}

ScrollPosition _listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(HomeTopicList),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  setUpAll(loadUiFonts);

  Future<_Probe> pumpHome(
    WidgetTester tester, {
    UiVariant variant = UiVariant.lightDefault,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final probe = _Probe();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      variant: variant,
      overrides: _overrides(prefs, probe),
    );
    // 用例失败时也先卸载页面（后注册的先执行，要赶在 pumpUi 还原桌面标记之前），
    // 否则页面在桌面标记还原后才销毁，会连带弄坏后面的用例
    addTearDown(() => _unmount(tester));
    await tester.pump(const Duration(milliseconds: 300));
    return probe;
  }

  for (final brightness in Brightness.values) {
    testUi('新话题消息到达：出现 40 高胶囊提示条，文案不显示数量（${brightness.name}）', (
      tester,
    ) async {
      await pumpHome(tester, variant: UiVariant(brightness, 1, UiDevice.pro));
      expect(find.byType(TopicListUpdateBanner), findsNothing);
      _publishNewTopic(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      final banner = find.byType(TopicListUpdateBanner);
      expect(banner, findsOneWidget);
      expect(find.text('有新的或更新的话题，点按查看'), findsOneWidget);
      // 数量不出现在文案里
      expect(find.textContaining('查看 1'), findsNothing);
      expect(find.textContaining('1 个'), findsNothing);

      final colors = tester.element(banner).tokens.colors;
      final rect = tester.getRect(banner);
      final pillFinder = find.descendant(
        of: banner,
        matching: find.byType(DecoratedBox),
      );
      final pill = tester.getRect(pillFinder);
      // 外框左右 20、上下 8；胶囊 40 高、圆角 20、surface/grouped 底
      expect(pill.height, 40);
      expect(pill.left - rect.left, 20);
      expect(rect.right - pill.right, 20);
      expect(pill.top - rect.top, 8);
      expect(rect.bottom - pill.bottom, 8);
      final decoration =
          tester.widget<DecoratedBox>(pillFinder).decoration as BoxDecoration;
      expect(decoration.color, colors.surfaceGrouped);
      expect(decoration.borderRadius, BorderRadius.circular(20));

      // 上箭头 16 + 13 号 medium brand 文字
      final text = tester.widget<Text>(
        find.descendant(
          of: banner,
          matching: find.text('有新的或更新的话题，点按查看'),
        ),
      );
      expect(text.style!.fontSize, 13);
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.color, colors.brandPrimary);
      final icon = tester.widget<Icon>(
        find.descendant(of: banner, matching: find.byType(Icon)),
      );
      expect(icon.size, 16);
      expect(icon.color, colors.brandPrimary);

      // 紧贴分类条下方：胶囊在列表最上面一行
      expect(rect.top, lessThan(tester.getTopLeft(find.byType(TopicRow).first).dy));
      await uiShot(tester, 'home_update_banner_${brightness.name}');
      await _unmount(tester);
    });
  }

  testUi('点按提示条：加载新话题并插到最前，列表回到顶部，提示条消失', (tester) async {
    final probe = await pumpHome(tester);
    _publishNewTopic(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TopicListUpdateBanner), findsOneWidget);

    // 列表先往下滚一点（提示条还露着一截），点按后必须回到顶部
    _listPosition(tester).jumpTo(20);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_listPosition(tester).pixels, 20);

    await tester.tap(find.byType(TopicListUpdateBanner));
    await tester.pumpAndSettle();

    expect(probe.calls, [
      [2001],
    ], reason: '点按后按待更新的话题 id 去加载一次');
    expect(find.byType(TopicListUpdateBanner), findsNothing);
    expect(find.text(_freshTitle), findsOneWidget);
    expect(_listPosition(tester).pixels, 0, reason: '加载完成后回到列表顶部');
    // 新话题排在第一行
    expect(
      tester.getTopLeft(find.text(_freshTitle)).dy,
      lessThan(tester.getTopLeft(find.text('Amex 白金卡年费上涨后还值不值得留？')).dy),
    );
    expectNoUiException(tester);
    await _unmount(tester);
  });

  testUi('加载期间提示条显示菊花、文案隐藏，重复点按不会再发请求', (tester) async {
    final probe = await pumpHome(tester);
    probe.gate = Completer<void>();
    _publishNewTopic(tester);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(TopicListUpdateBanner));
    await tester.pump(const Duration(milliseconds: 100));
    expect(probe.calls, hasLength(1));
    final banner = find.byType(TopicListUpdateBanner);
    expect(
      find.descendant(of: banner, matching: find.byType(CupertinoActivityIndicator)),
      findsOneWidget,
    );
    expect(find.text('有新的或更新的话题，点按查看'), findsNothing);

    await tester.tap(banner);
    await tester.pump(const Duration(milliseconds: 100));
    expect(probe.calls, hasLength(1), reason: '加载中再点不重复请求');

    probe.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TopicListUpdateBanner), findsNothing);
    expect(find.text(_freshTitle), findsOneWidget);
    await _unmount(tester);
  });
}
