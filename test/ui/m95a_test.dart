import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/follow_list_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 M9.5a：M6 / M7 遗留项。论坛请求一律是假数据。

class _FakeService implements DiscourseService {
  final List<String> calls = [];

  @override
  Future<List<FollowUser>> getFollowing(String username) async => [
    for (var i = 0; i < 3; i++)
      FollowUser(id: i + 1, username: 'user_$i', name: '用户 $i'),
  ];

  @override
  Future<void> unfollowUser(String username) async =>
      calls.add('unfollow:$username');

  @override
  Future<void> followUser(String username) async =>
      calls.add('follow:$username');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMe extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

void main() {
  setUpAll(loadUiFonts);

  group('关注页「已关注 / ＋关注」胶囊', () {
    for (final v in [UiVariant.lightDefault, ...UiVariant.landscape]) {
      testUi('自己的关注列表：点胶囊取消关注并可再关注（${v.label}）', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = _FakeService();
        await pumpUi(
          tester,
          FollowListPage(username: fixtureUser().username, isFollowing: true),
          variant: v,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            discourseServiceProvider.overrideWithValue(service),
            currentUserProvider.overrideWith(_FakeMe.new),
          ],
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expectNoUiException(tester);
        expect(find.text('已关注'), findsNWidgets(3));

        await tester.tap(find.text('已关注').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(service.calls, ['unfollow:user_0']);
        expect(find.text('已关注'), findsNWidgets(2));
        expect(find.text('＋关注'), findsOneWidget);

        await tester.tap(find.text('＋关注'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(service.calls, ['unfollow:user_0', 'follow:user_0']);
        expect(find.text('已关注'), findsNWidgets(3));
        await expectUiAccessibility(tester, textContrast: false);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testUi('看别人的关注列表时没有胶囊', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpUi(
        tester,
        const FollowListPage(username: 'someone_else', isFollowing: true),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          discourseServiceProvider.overrideWithValue(_FakeService()),
          currentUserProvider.overrideWith(_FakeMe.new),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已关注'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
