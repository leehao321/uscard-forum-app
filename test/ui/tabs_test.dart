import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/notifications_page.dart';
import 'package:fluxdo/pages/profile_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/widgets/profile_stats_card.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/widgets/notification/notification_item.dart';
import 'package:fluxdo/widgets/notification/notification_list_skeleton.dart';
import 'package:fluxdo/widgets/topic/topic_list_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M6：通知 Tab 页（设计说明 §5.1「通知」）。不请求论坛：列表、用户都用夹具。

class _FakeUser extends CurrentUserNotifier {
  _FakeUser(this.user);

  final User? user;

  @override
  FutureOr<User?> build() => user;
}

class _FakeNotifications extends NotificationListNotifier {
  _FakeNotifications(this.script);

  final Future<List<DiscourseNotification>> Function() script;

  @override
  Future<List<DiscourseNotification>> build() => script();

  @override
  bool get hasMore => false;

  @override
  Future<void> markAllAsRead() async {
    marked = true;
  }

  static bool marked = false;
}

List<Override> _overrides(
  SharedPreferences prefs,
  Future<List<DiscourseNotification>> Function() script, {
  bool loggedIn = true,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  currentUserProvider.overrideWith(
    () => _FakeUser(loggedIn ? fixtureUser() : null),
  ),
  systemUserAvatarTemplateProvider.overrideWith((ref) async => null),
  notificationListProvider.overrideWith(() => _FakeNotifications(script)),
];

Future<void> _pump(
  WidgetTester tester,
  Future<List<DiscourseNotification>> Function() script, {
  UiVariant variant = UiVariant.lightDefault,
  bool loggedIn = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpUi(
    tester,
    const NotificationsPage(),
    variant: variant,
    overrides: _overrides(prefs, script, loggedIn: loggedIn),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  group('通知页', () {
    testUi('导航「通知」+ check-check，头像行 + 筛选', (tester) async {
      await _pump(tester, () async => fixtureNotifications());
      expectNoUiException(tester);
      expect(find.text('通知'), findsOneWidget);
      expect(find.byIcon(AppIcons.checkAll), findsOneWidget);
      expect(find.byType(NotificationItem), findsNWidgets(5));
      // 筛选：全部 · 未读 · 回复 · 提及 · 点赞 · 私信 · 徽章 · 其他
      for (final label in ['全部', '未读', '回复', '提及']) {
        expect(find.text(label), findsOneWidget);
      }
      // 3 条未读 → 3 个未读点
      expect(find.byType(UnreadDot), findsNWidgets(3));
      await uiShot(tester, 'm6_notifications_light');
      await _unmount(tester);
    });

    // 每次只点一个筛选：FilterTabs 选中后会把选中项滚到中间，连点要等动画
    for (final c in [
      ('未读', 3),
      ('提及', 1),
      ('点赞', 1),
      ('私信', 1),
      ('徽章', 1),
    ]) {
      testUi('筛选「${c.$1}」只显示对应类型', (tester) async {
        await _pump(tester, () async => fixtureNotifications());
        await tester.ensureVisible(find.text(c.$1));
        await tester.tap(find.text(c.$1));
        await tester.pump(const Duration(milliseconds: 900));
        expect(find.byType(NotificationItem), findsNWidgets(c.$2));
        await _unmount(tester);
      });
    }

    testUi('筛选「其他」没有对应通知：空状态', (tester) async {
      await _pump(tester, () async => fixtureNotifications());
      await tester.ensureVisible(find.text('其他'));
      await tester.tap(find.text('其他'));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(NotificationItem), findsNothing);
      expect(find.text('这一类没有通知'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('未登录：登录引导，没有 check-check', (tester) async {
      await _pump(tester, () async => const [], loggedIn: false);
      expect(find.text('登录后查看通知'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.byIcon(AppIcons.checkAll), findsNothing);
      await _unmount(tester);
    });

    testUi('空列表：空状态', (tester) async {
      await _pump(tester, () async => const []);
      expect(find.text('暂无通知'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('加载中：骨架 10 行', (tester) async {
      final never = Completer<List<DiscourseNotification>>();
      await _pump(tester, () => never.future);
      expect(find.byType(NotificationListSkeleton), findsOneWidget);
      expect(find.byType(AvatarRowSkeleton), findsNWidgets(10));
      await _unmount(tester);
    });

    testUi('错误：原地错误 + 重试', (tester) async {
      await _pump(tester, () async => throw Exception('boom'));
      expect(find.text('重试'), findsOneWidget);
      await _unmount(tester);
    });

    testUi('点 check-check 全部标为已读（无确认）', (tester) async {
      _FakeNotifications.marked = false;
      await _pump(tester, () async => fixtureNotifications());
      await tester.tap(find.byIcon(AppIcons.checkAll));
      await tester.pump();
      expect(_FakeNotifications.marked, isTrue);
      await _unmount(tester);
    });

    test('类型到筛选的归类', () {
      final all = fixtureNotifications();
      List<int> ids(NotificationFilter f) =>
          all.where(f.matches).map((n) => n.id).toList();
      expect(ids(NotificationFilter.replies), [1]);
      expect(ids(NotificationFilter.mentions), [2]);
      expect(ids(NotificationFilter.likes), [3]);
      expect(ids(NotificationFilter.messages), [4]);
      expect(ids(NotificationFilter.badges), [5]);
      expect(ids(NotificationFilter.unread), [1, 2, 4]);
      expect(ids(NotificationFilter.other), isEmpty);
    });

    for (final variant in [
      ...UiVariant.portrait,
      ...UiVariant.landscape,
    ]) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await _pump(tester, () async => fixtureNotifications(), variant: variant);
        expectNoUiException(tester);
        await _unmount(tester);
      });
    }
  });

  group('我的', () {
    UserSummary summary() => UserSummary.fromJson({
      'user_summary': {
        'days_visited': 120,
        'posts_read_count': 8421,
        'likes_received': 356,
        'likes_given': 210,
        'topic_count': 12,
        'post_count': 340,
        'time_read': 360000,
        'bookmark_count': 24,
        'topics_entered': 900,
      },
    });

    Future<void> pumpProfile(
      WidgetTester tester, {
      bool loggedIn = true,
      UiVariant variant = UiVariant.lightDefault,
    }) async {
      SharedPreferences.setMockInitialValues({
        // 不弹统计卡引导
        'profile_stats_card_guide_shown': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const ProfilePage(isActive: true),
        variant: variant,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWith(
            () => _FakeUser(loggedIn ? fixtureUser() : null),
          ),
          userSummaryProvider.overrideWith(() => _FakeSummary(summary())),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testUi('已登录：导航「我的」+ qr-code，头部行、统计卡四列、三组、退出登录', (tester) async {
      await pumpProfile(tester);
      expectNoUiException(tester);
      expect(find.text('我的'), findsOneWidget);
      expect(find.byIcon(AppIcons.qrCode), findsOneWidget);
      expect(find.text('测试用户'), findsOneWidget);
      expect(find.textContaining('@hao'), findsOneWidget);
      expect(find.byType(ProfileStatsCard), findsOneWidget);
      for (final t in ['我的话题', '我的书签', '私信', '网页浏览', '应用设置']) {
        expect(find.text(t), findsOneWidget);
      }
      // 头部大头像 64
      expect(
        tester.allRenderObjects.whereType<RenderBox>().any(
          (b) => b.hasSize && b.size == const Size(64, 64),
        ),
        isTrue,
      );
      // Figma 55:2712 / 55:2730：统计卡高 65（pad 12 + 数字 24 + 间距 4 + 标签 13 + pad 12）；
      // 分组行 48、图标 20
      final card = tester.getSize(find.byType(ProfileStatsCard)).height;
      expect(card, anyOf(closeTo(65, 1), closeTo(69, 1)));
      // 相邻两行文字基线距离 = 行高 48 + 发丝线 0.5
      final step =
          tester.getTopLeft(find.text('我的书签')).dy -
          tester.getTopLeft(find.text('我的话题')).dy;
      expect(step, closeTo(48.5, 0.6));
      await uiShot(tester, 'm6_profile_in_light');
      await _unmount(tester);
    });

    testUi('未登录：登录按钮、只保留工具组、页脚说明', (tester) async {
      await pumpProfile(tester, loggedIn: false);
      expectNoUiException(tester);
      expect(find.text('未登录'), findsOneWidget);
      expect(find.byIcon(AppIcons.qrCode), findsNothing);
      expect(find.byType(ProfileStatsCard), findsNothing);
      expect(find.text('我的话题'), findsNothing);
      expect(find.text('网页浏览'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, '登录 美卡论坛');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, 48);
      await uiShot(tester, 'm6_profile_out_light');
      await _unmount(tester);
    });

    for (final variant in [
      ...UiVariant.portrait,
      ...UiVariant.landscape,
    ]) {
      testUi('不溢出（${variant.label}）', (tester) async {
        await pumpProfile(tester, variant: variant);
        expectNoUiException(tester);
        await _unmount(tester);
      });
    }
  });
}

class _FakeSummary extends UserSummaryNotifier {
  _FakeSummary(this.summary);

  final UserSummary summary;

  @override
  Future<UserSummary?> build() async => summary;
}
