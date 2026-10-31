import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/browsing_history_page.dart';
import 'package:fluxdo/pages/notifications_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/user_content_providers.dart';
import 'package:fluxdo/utils/paged_async_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.7 / P-2：筛选没有匹配项、还有下一页时不再自动翻页（原先冷却按未筛选列表
// 长度算，永不触发，会一页接一页地翻下去）；空状态里给用户手动点的按钮。
// 数据全是假的，不请求论坛。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _PagedNotifications extends NotificationListNotifier {
  static int loadMoreCalls = 0;

  @override
  Future<List<DiscourseNotification>> build() async {
    resetPagingState();
    return completePagedRefresh(
      PagedPage(items: _repliesOnly(), hasMore: true),
    );
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
  }

  // 全是「回复」类：切到「徽章」筛选后一条都不匹配
  static List<DiscourseNotification> _repliesOnly() => [
    for (var i = 1; i <= 3; i++)
      DiscourseNotification.fromJson({
        'id': i,
        'user_id': 1,
        'notification_type': NotificationType.replied.id,
        'read': true,
        'high_priority': false,
        'created_at': fixtureTime(Duration(hours: i)),
        'post_number': 1,
        'topic_id': 1000 + i,
        'fancy_title': '话题 $i',
        'slug': 'topic-$i',
        'data': {'display_username': 'user$i'},
      }),
  ];
}

class _PagedHistory extends BrowsingHistoryNotifier {
  static int loadMoreCalls = 0;

  @override
  Future<List<Topic>> build() async {
    resetPagingState();
    return completePagedRefresh(
      PagedPage(items: fixtureTopics(), hasMore: true),
    );
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);
  setUp(() {
    _PagedNotifications.loadMoreCalls = 0;
    _PagedHistory.loadMoreCalls = 0;
  });

  testUi('通知页：筛选没有匹配项且还有下一页时不自动翻页，手动按钮才翻', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpUi(
      tester,
      const NotificationsPage(),
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWith(_FakeUser.new),
        systemUserAvatarTemplateProvider.overrideWith((ref) async => null),
        notificationListProvider.overrideWith(_PagedNotifications.new),
      ],
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('话题 1'), findsOneWidget);
    expect(_PagedNotifications.loadMoreCalls, 0);

    await tester.tap(find.text('徽章'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 筛选为空：显示空状态和手动按钮，一次都没有自动翻页
    expect(_PagedNotifications.loadMoreCalls, 0);
    expect(find.text('这一类没有通知'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-load-earlier')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notification-load-earlier')));
    await tester.pump();
    expect(_PagedNotifications.loadMoreCalls, 1);
    await _unmount(tester);
  });

  testUi('浏览历史：已加载页全被屏蔽且还有下一页时不自动翻页，手动按钮才翻', (tester) async {
    final blocked = {
      for (final t in fixtureTopics())
        if (t.posters.isNotEmpty && t.posters.first.user != null)
          t.posters.first.user!.username,
    }.toList();
    SharedPreferences.setMockInitialValues({'pref_blocked_usernames': blocked});
    final prefs = await SharedPreferences.getInstance();
    await pumpUi(
      tester,
      const BrowsingHistoryPage(),
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserProvider.overrideWith(_FakeUser.new),
        browsingHistoryProvider.overrideWith(_PagedHistory.new),
      ],
      settle: false,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(_PagedHistory.loadMoreCalls, 0);
    expect(find.text('暂无浏览历史'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-load-earlier')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-load-earlier')));
    await tester.pump();
    expect(_PagedHistory.loadMoreCalls, 1);
    await _unmount(tester);
  });
}
