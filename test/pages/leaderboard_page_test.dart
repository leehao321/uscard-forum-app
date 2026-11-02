import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/site_customization.dart';
import 'package:fluxdo/config/sites/current.dart';
import 'package:fluxdo/models/badge.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/leaderboard_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/leaderboard_provider.dart';
import 'package:fluxdo/services/site_context.dart';

import '../support/app_harness.dart';

BadgeTopicEntry _entry(int id) => BadgeTopicEntry(
  topicId: id,
  title: '话题 $id',
  grantedAt: DateTime.utc(2026, 10, 1),
  author: '作者$id',
  postsCount: 8,
);

void main() {
  tearDown(SiteContext.debugReset);

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

  group('按站显示', () {
    test('没配徽章的榜单不出现', () {
      expect(leaderboardsFor(const SiteCustomization()), isEmpty);
      expect(leaderboardsFor(const SiteCustomization(greatTopicBadgeId: 20)), [
        LeaderboardKind.great,
      ]);
    });

    test('只有美卡有榜单，徽章 id 进站点配置', () {
      SiteContext.activate(SitePresets.uscard);
      expect(availableLeaderboards(), [
        LeaderboardKind.great,
        LeaderboardKind.funny,
      ]);
      expect(currentSiteCustomization.greatTopicBadgeId, 20);
      expect(currentSiteCustomization.funnyTopicBadgeId, 115);

      SiteContext.activate(SitePresets.linuxdo);
      expect(availableLeaderboards(), isEmpty);

      SiteContext.activate(
        SiteProfile(baseUrl: 'https://example.com', title: 'E'),
      );
      expect(availableLeaderboards(), isEmpty);
    });

    test('按 topic_id 去重，保留先出现的', () {
      final merged = LeaderboardNotifier.mergeUnique(
        [_entry(1), _entry(2)],
        [_entry(2), _entry(3)],
      );
      expect(merged.map((e) => e.topicId), [1, 2, 3]);
    });
  });

  group('页面', () {
    Future<void> pump(WidgetTester tester, LeaderboardState state) async {
      await pumpApp(
        tester,
        const LeaderboardPage(kind: LeaderboardKind.great),
        overrides: [
          leaderboardProvider(
            LeaderboardKind.great,
          ).overrideWith(() => _FixedNotifier(state)),
          currentUserProvider.overrideWith(() => _NoUser()),
        ],
      );
    }

    testWidgets('列出话题和元信息', (tester) async {
      await pump(
        tester,
        LeaderboardState(entries: [_entry(1)], hasMore: false),
      );
      expect(find.text('精彩'), findsOneWidget);
      expect(find.text('话题 1'), findsOneWidget);
      expect(find.textContaining('作者1 · 获得于'), findsOneWidget);
      expect(find.textContaining('7 回复'), findsOneWidget);
    });

    testWidgets('没有数据时给空状态', (tester) async {
      await pump(tester, const LeaderboardState(hasMore: false));
      expect(find.text('榜上还没有帖子'), findsOneWidget);
    });
  });
}

class _FixedNotifier extends LeaderboardNotifier {
  _FixedNotifier(this.fixed) : super(LeaderboardKind.great);

  final LeaderboardState fixed;

  @override
  Future<LeaderboardState> build() async => fixed;
}

class _NoUser extends CurrentUserNotifier {
  @override
  Future<User?> build() async => null;
}
