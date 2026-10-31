import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:ai_model_manager/ai_model_manager.dart'
    show
        AiAdvancedSettingsPage,
        AiChatHistoryPage,
        AiModelConfigPage,
        AiProviderEditPage,
        AiProviderListPage,
        AiProvidersPage,
        PromptPresetEditPage,
        PromptPresetsPage;
import 'package:fluxdo/models/badge.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/about_page.dart';
import 'package:fluxdo/pages/create_topic_page.dart';
import 'package:fluxdo/pages/edit_topic_page.dart';
import 'package:fluxdo/pages/image_viewer_page.dart';
import 'package:fluxdo/widgets/post/reply_sheet.dart';
import 'package:fluxdo/services/discourse_cook_service.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluxdo/pages/badge_page.dart';
import 'package:fluxdo/pages/bookmarks_page.dart';
import 'package:fluxdo/pages/category_topics_page.dart';
import 'package:fluxdo/pages/dev/ui_gallery_page.dart';
import 'package:fluxdo/pages/drafts_page.dart';
import 'package:fluxdo/pages/login_page.dart';
import 'package:fluxdo/pages/my_browser_page.dart';
import 'package:fluxdo/pages/my_topics_page.dart';
import 'package:fluxdo/pages/qr_login_scan_page.dart';
import 'package:fluxdo/pages/onboarding_page.dart';
import 'package:fluxdo/pages/pending_posts_page.dart';
import 'package:fluxdo/pages/private_messages_page.dart';
import 'package:fluxdo/pages/tag_topics_page.dart';
import 'package:fluxdo/pages/user_profile_page.dart';
import 'package:fluxdo/pages/browsing_history_page.dart';
import 'package:fluxdo/pages/follow_list_page.dart';
import 'package:fluxdo/pages/my_badges_page.dart';
import 'package:fluxdo/pages/notifications_page.dart';
import 'package:fluxdo/pages/profile_page.dart';
import 'package:fluxdo/pages/search_page.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/utils/paged_async_notifier.dart';
import 'package:fluxdo/pages/app_lock_settings_page.dart';
import 'package:fluxdo/pages/app_logs_page.dart';
import 'package:fluxdo/pages/download_list_page.dart';
import 'package:fluxdo/pages/export_history_page.dart';
import 'package:fluxdo/pages/invite_links_page.dart';
import 'package:fluxdo/pages/notes_page.dart';
import 'package:fluxdo/pages/notion_settings_page.dart';
import 'package:fluxdo/pages/perf_diagnostics_page.dart';
import 'package:fluxdo/pages/profile_stats_edit_page.dart';
import 'package:fluxdo/pages/reading_stats_page.dart';
import 'package:fluxdo/pages/saved_topics_page.dart';
import 'package:fluxdo/pages/network_settings_page/doh_detail_settings_page.dart';
import 'package:fluxdo/pages/appearance_page.dart';
import 'package:fluxdo/pages/bottom_nav_settings_page.dart';
import 'package:fluxdo/pages/data_management_page.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/font_settings_page.dart';
import 'package:fluxdo/pages/network_settings_page/network_settings_page.dart';
import 'package:fluxdo/pages/preferences_page.dart';
import 'package:fluxdo/pages/reading_settings_page.dart';
import 'package:fluxdo/pages/settings_page.dart';
import 'package:fluxdo/pages/shortcut_settings_page.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart'
    show sharedPreferencesProvider;
import 'package:fluxdo/providers/user_content_providers.dart'
    show currentUsernameProvider;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

// 0.4.0 横屏巡检：lib/pages/ 和 packages/ai_model_manager/lib/pages/ 里能用假数据打开的
// 页面，逐个放到 852×393（landscapePro）和 956×440（landscape）下渲染，每页检查
//   1. 没有 RenderFlex 溢出等渲染异常（expectNoUiException）；
//   2. 手机横屏时主体内容宽度 ≤ 640（expectReadableBody，计划 §7）。
// 打不开的页面和原因见 docs/uscard/0.4.0-plan.md §14「A：S 级与设计偏差」里的
// 「横屏巡检打不开的页面」。数据全是假的，不请求论坛；失败的页面出截图
// （SHOTS_DIR 指到 scratchpad）。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => fixtureUser();
}

class _FakeTracking extends TopicTrackingStateNotifier {
  @override
  Map<int, TrackedTopicState> build() => const {};
}

class _FakeMessageBusInit extends MessageBusInitNotifier {
  @override
  void build() {}
}

/// 1×1 透明 PNG
Uint8List _tinyPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeNotifications extends NotificationListNotifier {
  @override
  Future<List<DiscourseNotification>> build() async => fixtureNotifications();

  @override
  bool get hasMore => false;
}

class _FakeSummary extends UserSummaryNotifier {
  @override
  Future<UserSummary?> build() async => UserSummary.fromJson({
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
}

class _FakeHistory extends BrowsingHistoryNotifier {
  @override
  Future<List<Topic>> build() async {
    resetPagingState();
    return completePagedRefresh(
      PagedPage(items: fixtureTopics(), hasMore: false),
    );
  }
}

/// 数据类页面用的假服务：只实现巡检里被调用的几个方法，其余返回 null
class _AuditService implements DiscourseService {
  @override
  Future<String?> getPostRaw(int postId) async => '最近重新整理了写作环境。 常用工具应该留在手边。';

  @override
  Future<List<String>> getRecentSearches() async => const ['chase 125k'];

  @override
  Future<BadgeDetailResponse> getUserBadges({required String username}) async =>
      BadgeDetailResponse.fromJson({
        'badges': [
          for (var i = 0; i < 7; i++)
            {
              'id': i + 1,
              'name': '热心人 $i',
              'description': '示例徽章',
              'badge_type_id': 1 + i % 3,
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
              'count': 1,
            },
        ],
      });

  @override
  Future<List<FollowUser>> getFollowing(String username) async => [
    for (var i = 0; i < 8; i++)
      FollowUser(
        id: i + 1,
        username: 'user_$i',
        name: i.isEven ? '用户 $i' : null,
      ),
  ];

  @override
  Future<List<FollowUser>> getFollowers(String username) =>
      getFollowing(username);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 所有页面共用的假依赖：登录用户、分类 / 标签、跟踪状态、两份偏好
Future<List<Override>> baseOverrides([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWith(_FakeUser.new),
    currentUsernameProvider.overrideWith((ref) async => 'tester'),
    categoriesProvider.overrideWith((ref) async => fixtureCategories()),
    tagsProvider.overrideWith((ref) async => const ['chase', 'csr']),
    messageBusInitProvider.overrideWith(_FakeMessageBusInit.new),
    topicTrackingStateProvider.overrideWith(_FakeTracking.new),
  ];
}

class PageCase {
  const PageCase(
    this.name,
    this.build, {
    this.extra,
    this.prefs = const {},
    this.readable = true,
    this.editor = false,
    this.editorColumn = false,
    this.navBar = true,
  });

  /// false = 全屏沉浸页（图片查看器等），只查溢出，不要求 640 限宽
  final bool readable;

  /// true = 编辑器页：先灌入站点设置和 cook 服务（和 composer_workbench_test 一样）
  final bool editor;

  /// true = 编辑器页：滚动区通栏，限宽靠两侧留白，改用 [expectEditorColumn] 量输入区
  final bool editorColumn;

  /// 检查顶部导航栏对齐 640 列（没有导航栏的页面自动跳过）
  final bool navBar;

  /// 预置的 SharedPreferences 值（例如不弹引导）
  final Map<String, Object> prefs;

  final String name;
  final Widget Function() build;

  /// 这个页面额外要的假 provider
  final List<Override> Function()? extra;
}

/// 能打开的页面（设置组页面、AI 页面等）。数据类页面在下面追加。
final List<PageCase> pageCases = [
  PageCase('设置首页', () => const SettingsPage()),
  PageCase('外观', () => const AppearancePage()),
  PageCase('字体', () => const FontSettingsPage()),
  PageCase('阅读设置', () => const ReadingSettingsPage()),
  PageCase('偏好', () => const PreferencesPage()),
  PageCase('网络', () => const NetworkSettingsPage()),
  PageCase('数据管理', () => const DataManagementPage()),
  PageCase('诊断', () => const DiagnosticsPage()),
  PageCase('快捷键', () => const ShortcutSettingsPage()),
  PageCase('底栏设置', () => const BottomNavSettingsPage()),
  PageCase('应用锁', () => const AppLockSettingsPage()),
  PageCase('DoH 详情', () => const DohDetailSettingsPage()),
  PageCase('关于', () => const AboutPage()),
  PageCase('日志', () => const AppLogsPage()),
  PageCase('Notion', () => const NotionSettingsPage()),
  PageCase('性能诊断', () => const PerfDiagnosticsPage()),
  PageCase('资料统计编辑', () => const ProfileStatsEditPage()),
  PageCase('阅读统计', () => const ReadingStatsPage()),
  PageCase('笔记', () => const NotesPage()),
  PageCase('已存帖子', () => const SavedTopicsPage()),
  PageCase('下载列表', () => const DownloadListPage()),
  PageCase('导出历史', () => const ExportHistoryPage()),
  PageCase('邀请链接', () => const InviteLinksPage()),
  // 数据类页面
  PageCase(
    '通知',
    () => const NotificationsPage(),
    extra: () => [
      systemUserAvatarTemplateProvider.overrideWith((ref) async => null),
      notificationListProvider.overrideWith(_FakeNotifications.new),
    ],
  ),
  PageCase(
    '我的',
    () => const ProfilePage(isActive: true),
    prefs: const {'profile_stats_card_guide_shown': true},
    extra: () => [userSummaryProvider.overrideWith(_FakeSummary.new)],
  ),
  PageCase(
    '我的徽章',
    () => const MyBadgesPage(),
    extra: () => [discourseServiceProvider.overrideWithValue(_AuditService())],
  ),
  PageCase(
    '关注',
    () => const FollowListPage(username: 'me', isFollowing: true),
    extra: () => [discourseServiceProvider.overrideWithValue(_AuditService())],
  ),
  PageCase(
    '搜索',
    () => const SearchPage(),
    extra: () {
      // 不让页面去请求论坛首页取站点设置
      PreloadedDataService().debugSeed(siteSettings: const {});
      return [discourseServiceProvider.overrideWithValue(_AuditService())];
    },
  ),
  PageCase(
    '浏览历史',
    () => const BrowsingHistoryPage(),
    extra: () => [browsingHistoryProvider.overrideWith(_FakeHistory.new)],
  ),
  PageCase('我的浏览器', () => const MyBrowserPage()),
  // 全屏相机取景，不要求 640 限宽
  PageCase('扫码登录', () => const QrLoginScanPage(), readable: false),
  PageCase('书签', () => const BookmarksPage()),
  PageCase('草稿', () => const DraftsPage()),
  PageCase('我的话题', () => const MyTopicsPage()),
  PageCase('私信', () => const PrivateMessagesPage()),
  PageCase('待审内容', () => const PendingPostsPage()),
  PageCase(
    '分类话题',
    () => CategoryTopicsPage(category: fixtureCategories().first),
  ),
  PageCase('标签话题', () => const TagTopicsPage(tagName: 'chase')),
  PageCase('用户主页', () => const UserProfilePage(username: 'chase_fan')),
  PageCase('徽章详情', () => const BadgePage(badgeId: 20)),
  PageCase(
    '登录',
    () => LoginPage(
      services: LoginPageServices(
        loadCredentials: () async => (username: null, password: null),
        clearCredentials: () async {},
        submit: ({
          required identifier,
          required password,
          required rememberCredentials,
        }) async => false,
      ),
    ),
  ),
  PageCase(
    '引导',
    () => OnboardingPage(onComplete: () {}, initializeDeepLink: false),
  ),
  PageCase('组件样本', () => const UiGalleryPage()),
  PageCase(
    '发新话题',
    () =>
        const CreateTopicPage(initialTitle: '分享最近的开发体验', initialContent: '正文'),
    editor: true,
    // 编辑器的滚动区通栏（底部工具条背景要铺满屏宽），正文列限宽 640 靠两侧留白
    readable: false,
    editorColumn: true,
  ),
  PageCase(
    '编辑话题',
    () {
      final detail = fixtureTopicDetail();
      return EditTopicPage(
        topicDetail: detail,
        firstPost: detail.postStream.posts.first,
        firstPostId: detail.postStream.posts.first.id,
      );
    },
    editor: true,
    readable: false,
    editorColumn: true,
    extra: () => [discourseServiceProvider.overrideWithValue(_AuditService())],
  ),
  PageCase(
    '回复半屏',
    () => ReplySheet(topicId: 1001, preloadedDraftFuture: Future.value(null)),
    editor: true,
    readable: false,
    editorColumn: true,
  ),
  PageCase(
    '图片查看器',
    () => ImageViewerPage(imageBytes: _tinyPng()),
    readable: false,
  ),
  // AI 模型服务（packages/ai_model_manager）
  PageCase('AI 服务入口', () => const AiProvidersPage()),
  PageCase('AI 服务商列表', () => const AiProviderListPage()),
  PageCase('AI 服务商编辑', () => const AiProviderEditPage()),
  PageCase('AI 模型配置', () => const AiModelConfigPage()),
  PageCase('AI 提示词', () => const PromptPresetsPage()),
  PageCase('AI 提示词编辑', () => const PromptPresetEditPage()),
  PageCase('AI 对话历史', () => const AiChatHistoryPage()),
  PageCase('AI 高级设置', () => const AiAdvancedSettingsPage()),
];

void main() {
  setUpAll(loadUiFonts);

  for (final device in [UiDevice.landscapePro, UiDevice.landscape]) {
    final variant = UiVariant(Brightness.light, 1, device);
    for (final c in pageCases) {
      testUi('${c.name}（${device.name}）', (tester) async {
        final overrides = [
          ...await baseOverrides(c.prefs),
          ...?c.extra?.call(),
        ];
        if (c.editor) {
          // 编辑器页：先灌入站点设置和 cook 服务（和 composer_workbench_test 一样）
          await tester.runAsync(() async {
            if (!PreloadedDataService().isLoaded) {
              await PreloadedDataService().hydrateFromHtml(
                '<meta id="data-discourse-setup"><script id="data-preloaded" type="application/json">${jsonEncode({
                  'currentUser': {'id': 1, 'username': 'tester'},
                  'siteSettings': {'min_post_length': 1, 'max_post_length': 10000},
                  'site': {'categories': [], 'top_tags': []},
                })}</script>',
              );
              await DiscourseCookService().ensureInitialized();
            }
          });
        }
        await pumpUi(
          tester,
          c.build(),
          variant: variant,
          overrides: overrides,
          settle: false,
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        try {
          expectNoUiException(tester);
          if (c.readable) expectReadableBody(tester, variant);
          if (c.navBar) expectNavBarAligned(tester, variant);
          if (c.editorColumn) expectEditorColumn(tester, variant);
        } catch (_) {
          await uiShot(tester, 'landscape_fail_${c.name}_${device.name}');
          rethrow;
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        }
      });
    }
  }
}
