import 'dart:async';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/badge.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/follow_list_page.dart';
import 'package:fluxdo/pages/my_badges_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M7：话题相关与个人列表。不请求论坛：服务一律用假数据。

class _FakeService implements DiscourseService {
  _FakeService({this.badges, this.follows});

  final Future<BadgeDetailResponse> Function()? badges;
  final Future<List<FollowUser>> Function()? follows;

  @override
  Future<BadgeDetailResponse> getUserBadges({required String username}) =>
      badges!();

  @override
  Future<List<FollowUser>> getFollowing(String username) => follows!();

  @override
  Future<List<FollowUser>> getFollowers(String username) => follows!();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

BadgeDetailResponse _badgeResponse() => BadgeDetailResponse.fromJson({
  'badges': [
    for (final (i, type) in [1, 2, 3, 3, 2, 1, 3].indexed)
      {
        'id': i + 1,
        'name': i.isEven ? '热心人' : '好奇宝宝 $i',
        'description': '示例徽章',
        'badge_type_id': type,
        'grant_count': 120 + i,
        'slug': 'badge-$i',
      },
  ],
  'users': const [],
  'user_badges': [
    for (var i = 0; i < 7; i++)
      {
        'id': 100 + i,
        'badge_id': i + 1,
        'user_id': 1,
        'granted_at': '2026-10-20T08:00:00.000Z',
        'count': i == 1 ? 3 : 1,
      },
  ],
});

List<FollowUser> _follows() => [
  for (var i = 0; i < 8; i++)
    FollowUser(id: i + 1, username: 'user_$i', name: i.isEven ? '用户 $i' : null),
];

List<Override> _overrides(SharedPreferences prefs, _FakeService service) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  discourseServiceProvider.overrideWithValue(service),
  currentUserProvider.overrideWith(_FakeUser.new),
];

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadUiFonts);

  final variants = [...UiVariant.portrait, ...UiVariant.landscape];

  group('我的徽章', () {
    for (final v in variants) {
      testUi('三列卡片、金银铜只写字（${v.label}）', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await pumpUi(
          tester,
          const MyBadgesPage(),
          variant: v,
          overrides: _overrides(
            prefs,
            _FakeService(badges: () async => _badgeResponse()),
          ),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expectNoUiException(tester);
        expect(find.textContaining('热心人'), findsWidgets);
        // 卡片：金银铜只用文字，名称下一行是「类型 · ×次数」
        expect(find.textContaining('×3'), findsOneWidget);
        await uiShot(tester, 'm7_my_badges_${v.label}');
        await _unmount(tester);
      });
    }

    testUi('卡片热区可点、可朗读', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const MyBadgesPage(),
        overrides: _overrides(
          prefs,
          _FakeService(badges: () async => _badgeResponse()),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      final card = find.ancestor(
        of: find.text('热心人').first,
        matching: find.byType(AppPressable),
      );
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, greaterThanOrEqualTo(44));
      await expectUiAccessibility(tester, textContrast: false);
      await _unmount(tester);
    });
  });

  group('关注与粉丝', () {
    for (final v in variants) {
      testUi('行 = 34 头像 + 名字 + @handle（${v.label}）', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await pumpUi(
          tester,
          const FollowListPage(username: 'me', isFollowing: true),
          variant: v,
          overrides: _overrides(
            prefs,
            _FakeService(follows: () async => _follows()),
          ),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expectNoUiException(tester);
        expect(find.text('@user_0'), findsOneWidget);
        await uiShot(tester, 'm7_follow_${v.label}');
        await _unmount(tester);
      });
    }

    testUi('无障碍与行高', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const FollowListPage(username: 'me', isFollowing: false),
        overrides: _overrides(
          prefs,
          _FakeService(follows: () async => _follows()),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      final row = find.ancestor(
        of: find.text('@user_0'),
        matching: find.byType(AppPressable),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(AppSize.row48));
      await expectUiAccessibility(tester, textContrast: false);
      await _unmount(tester);
    });

    testUi('空列表显示状态页', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const FollowListPage(username: 'me', isFollowing: true),
        overrides: _overrides(
          prefs,
          _FakeService(follows: () async => const []),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expectNoUiException(tester);
      expect(find.byType(AppStateView), findsOneWidget);
      await _unmount(tester);
    });
  });
}
