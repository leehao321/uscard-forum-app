import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/topics_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/widgets/topic/topic_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.7 / P-3：首页单条「标为已读」只发这一条的 dismiss 请求，只改这一条的
// 本地已读状态，不按分类清零，也不再重取整帖详情。数据与服务全是假的。

class _Service extends Fake implements DiscourseService {
  final List<List<int>> dismissed = [];
  final List<String> others = [];

  @override
  Future<void> dismissTopicPosts(List<int> topicIds) async {
    dismissed.add(topicIds);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    others.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _FakeTopicList extends TopicListNotifier {
  _FakeTopicList(super.categoryId, this.topics);

  final List<Topic> topics;

  @override
  Future<List<Topic>> build() async => topics;
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

Finder _row(Topic t) =>
    find.byWidgetPredicate((w) => w is TopicRow && w.topic.id == t.id);

List<Topic> _topics() {
  final base = fixtureTopics().where((t) => !t.pinned).toList();
  // 前两条同分类，各有 3 条未读；第三条已读
  return [
    base[0].copyWith(unread: 3, highestPostNumber: 10, lastReadPostNumber: 7),
    base[1].copyWith(unread: 3, highestPostNumber: 10, lastReadPostNumber: 7),
    base[2].copyWith(unread: 0),
  ];
}

void main() {
  setUpAll(loadUiFonts);

  testUi('标为已读：只发一次 dismiss、不请求详情、其他话题的未读不受影响', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = _Service();
    final topics = _topics();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        discourseServiceProvider.overrideWithValue(service),
        topicListProvider.overrideWith2((_) => _FakeTopicList(null, topics)),
        categoryMapProvider.overrideWithValue(
          AsyncData({for (final c in fixtureCategories()) c.id: c}),
        ),
        categoriesProvider.overrideWith((ref) async => fixtureCategories()),
        currentUserProvider.overrideWith(_FakeUser.new),
        messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
        topicTrackingStateProvider.overrideWith(_FakeTracking.new),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.longPress(_row(topics[0]));
    await tester.pump(const Duration(milliseconds: 500));
    // 已读话题没有这一项：条件是已登录、非置顶、unread>0 或 newPosts>0
    expect(find.text('标为已读'), findsOneWidget);
    await tester.tap(find.text('标为已读'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(service.dismissed, [
      [topics[0].id],
    ]);
    expect(service.others, isEmpty, reason: '不应再请求帖子详情或其他接口');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TopicsPage)),
    );
    final list = container.read(topicListProvider(null)).value!;
    expect(list[0].unread, 0, reason: '这一条本地标为已读');
    expect(list[0].lastReadPostNumber, 10);
    expect(list[1].unread, 3, reason: '同分类的其他话题不受影响');
    expect(list[1].lastReadPostNumber, 7);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testUi('已读话题长按菜单里没有「标为已读」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final topics = _topics();
    await pumpUi(
      tester,
      Scaffold(body: TopicsPage(onCreateTopic: () {})),
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        discourseServiceProvider.overrideWithValue(_Service()),
        topicListProvider.overrideWith2((_) => _FakeTopicList(null, topics)),
        categoryMapProvider.overrideWithValue(
          AsyncData({for (final c in fixtureCategories()) c.id: c}),
        ),
        categoriesProvider.overrideWith((ref) async => fixtureCategories()),
        currentUserProvider.overrideWith(_FakeUser.new),
        messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
        topicTrackingStateProvider.overrideWith(_FakeTracking.new),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(_row(topics[2]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('标为已读'), findsNothing);
    expect(find.text('分享'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
