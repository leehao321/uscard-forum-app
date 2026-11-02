import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/sites/current.dart';
import 'package:fluxdo/models/profile_stats_config.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';
import 'package:fluxdo/navigation/nav_entry_registry.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/progress_gesture_action_meta.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/widgets/common/smart_avatar.dart';

void main() {
  final custom = SiteProfile(baseUrl: 'https://example.com', title: 'E');
  final preloaded = PreloadedDataService();

  tearDown(() {
    SiteContext.debugReset();
    preloaded.debugSeed();
  });

  group('功能包', () {
    test('LDC、CDK、connect 只给 linux.do', () {
      expect(SitePresets.linuxdo.hasLinuxdoServices, isTrue);
      expect(SitePresets.uscard.hasLinuxdoServices, isFalse);
      expect(custom.hasLinuxdoServices, isFalse);
    });

    test('.xz 改名上传和写死的 sitekey 只给 linux.do', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(currentSiteCustomization.mediaUploadAsXz, isTrue);
      SiteContext.activate(SitePresets.uscard);
      expect(currentSiteCustomization.mediaUploadAsXz, isFalse);
    });

    test('connect 数据源只给 linux.do，导入别的站时回到 Summary', () {
      SiteContext.activate(SitePresets.linuxdo);
      expect(availableStatsDataSources(), contains(StatsDataSource.connect));
      expect(
        ProfileStatsConfig.fromJson({'dataSource': 'connect'}).dataSource,
        StatsDataSource.connect,
      );

      SiteContext.activate(SitePresets.uscard);
      expect(availableStatsDataSources(), [StatsDataSource.summary]);
      expect(
        ProfileStatsConfig.fromJson({'dataSource': 'connect'}).dataSource,
        StatsDataSource.summary,
      );
    });

    test('方形头像规则只对 linux.do 的 neo', () {
      expect(isSquareAvatarUrl('/user_avatar/linux.do/neo/48/1.png'), isTrue);
      expect(
        isSquareAvatarUrl('/user_avatar/www.uscardforum.com/neo/48/1.png'),
        isFalse,
      );
    });
  });

  group('站点设置决定功能开关', () {
    test('设置里没有就是没装；linux.do 没加载时沿用上游行为', () {
      SiteContext.activate(custom);
      preloaded.debugSeed(siteSettings: {'title': 'x'});
      expect(preloaded.chatEnabled, isFalse);
      expect(preloaded.boostsEnabled, isFalse);
      expect(preloaded.nestedRepliesEnabled, isFalse);
      expect(preloaded.solvedEnabled, isFalse);
      expect(preloaded.topicVotingEnabled, isFalse);

      preloaded.debugSeed();
      expect(preloaded.chatEnabled, isFalse, reason: '没加载时不请求 /chat');

      SiteContext.activate(SitePresets.linuxdo);
      expect(preloaded.chatEnabled, isTrue);
      expect(preloaded.nestedRepliesEnabled, isTrue);
    });

    test('设置值优先，linux.do 上关掉也认', () {
      SiteContext.activate(SitePresets.linuxdo);
      preloaded.debugSeed(siteSettings: {'chat_enabled': false});
      expect(preloaded.chatEnabled, isFalse);

      SiteContext.activate(custom);
      preloaded.debugSeed(
        siteSettings: {
          'chat_enabled': true,
          'discourse_boosts_enabled': true,
          'nested_replies_enabled': true,
        },
      );
      expect(preloaded.chatEnabled, isTrue);
      expect(preloaded.boostsEnabled, isTrue);
      expect(preloaded.nestedRepliesEnabled, isTrue);
    });

    test('hCaptcha 只在站点确实用它时生效', () {
      preloaded.debugSeed(
        siteSettings: {'hcaptcha_site_key': '', 'discourse_captcha_enabled': false},
      );
      expect(preloaded.hcaptchaSiteKey, isNull);
      expect(preloaded.localLoginsEnabled, isTrue);

      preloaded.debugSeed(
        siteSettings: {
          'hcaptcha_site_key': 'key',
          'discourse_captcha_enabled': false,
        },
      );
      expect(preloaded.hcaptchaSiteKey, isNull, reason: '验证关着');

      preloaded.debugSeed(
        siteSettings: {
          'hcaptcha_site_key': 'key',
          'discourse_captcha_enabled': true,
          'discourse_captcha_provider': 'hcaptcha',
        },
      );
      expect(preloaded.hcaptchaSiteKey, 'key');
      expect(preloaded.localLoginsEnabled, isTrue);
    });

    test('其他人机验证跑不了内嵌登录，只留 WebView', () {
      preloaded.debugSeed(
        siteSettings: {
          'hcaptcha_site_key': 'key',
          'discourse_captcha_enabled': true,
          'discourse_captcha_provider': 'recaptcha_v2',
        },
      );
      expect(preloaded.hcaptchaSiteKey, isNull);
      expect(preloaded.localLoginsEnabled, isFalse);

      preloaded.debugSeed(siteSettings: {'enable_local_logins': false});
      expect(preloaded.localLoginsEnabled, isFalse);
    });
  });

  group('回应插件', () {
    test('三种状态', () {
      SiteContext.activate(custom);
      preloaded.debugSeed();
      expect(preloaded.reactionsPluginState, isNull);
      expect(preloaded.enabledReactionsSync, isEmpty);

      preloaded.debugSeed(siteSettings: {'title': 'x'});
      expect(preloaded.reactionsPluginState, isFalse);

      preloaded.debugSeed(
        siteSettings: {'discourse_reactions_enabled': true},
      );
      expect(preloaded.reactionsPluginState, isTrue);
      expect(preloaded.enabledReactionsSync, isNotEmpty);
    });

    test('linux.do 没加载时仍按装了处理', () {
      SiteContext.activate(SitePresets.linuxdo);
      preloaded.debugSeed();
      expect(preloaded.reactionsPluginState, isTrue);
    });

    test('没有 reactions 字段时点赞来自 actions_summary', () {
      final likes = PostReaction.likesFromActionsSummary({
        'actions_summary': [
          {'id': 2, 'count': 3, 'acted': true},
        ],
      });
      expect(likes.reactions.single.count, 3);
      expect(likes.current, isNotNull);

      final none = PostReaction.likesFromActionsSummary({});
      expect(none.reactions, isEmpty);
      expect(none.current, isNull);
    });

    test('改点赞数时保留其他表情，归零时去掉 heart', () {
      const smile = PostReaction(id: 'smile', type: 'emoji', count: 1);
      const heart = PostReaction(id: 'heart', type: 'emoji', count: 1);
      final raised = PostReaction.withHeartCount([heart, smile], 2);
      expect(raised.map((r) => r.id), ['heart', 'smile']);
      expect(raised.first.count, 2);
      expect(
        PostReaction.withHeartCount([heart, smile], 0).map((r) => r.id),
        ['smile'],
      );
    });
  });

  group('导航入口', () {
    Set<String> ids() => NavEntryRegistry.buildAll().map((e) => e.id).toSet();

    test('没开聊天的站没有聊天入口，开了才有', () {
      SiteContext.activate(custom);
      preloaded.debugSeed(siteSettings: {'title': 'x'});
      expect(ids(), isNot(contains(NavEntryIds.chat)));

      preloaded.debugSeed(siteSettings: {'chat_enabled': true});
      expect(ids(), contains(NavEntryIds.chat));
    });

    test('不允许后台访问的站没有关注入口', () {
      preloaded.debugSeed(siteSettings: {'title': 'x'});
      SiteContext.activate(SitePresets.uscard);
      expect(ids(), isNot(contains(NavEntryIds.seeking)));

      SiteContext.activate(custom);
      expect(ids(), contains(NavEntryIds.seeking));
    });
  });

  test('没开树形回复的站，手势菜单滤掉切换树形视图', () {
    SiteContext.activate(custom);
    preloaded.debugSeed(siteSettings: {'title': 'x'});
    expect(
      isProgressGestureActionAvailable(ProgressGestureAction.toggleNestedView),
      isFalse,
    );
    expect(
      availableProgressGestureActions(),
      isNot(contains(ProgressGestureAction.toggleNestedView)),
    );

    preloaded.debugSeed(siteSettings: {'nested_replies_enabled': true});
    expect(
      availableProgressGestureActions(),
      contains(ProgressGestureAction.toggleNestedView),
    );
  });
}
