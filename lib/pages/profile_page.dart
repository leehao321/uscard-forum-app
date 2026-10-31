import 'saved_topics_page.dart';
import 'notes_page.dart';
import 'reading_stats_page.dart';
import '../constants.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../providers/discourse_providers.dart';
import '../providers/selected_topic_provider.dart';
import '../providers/shortcut_provider.dart';
import '../widgets/desktop_refresh_indicator.dart';
import '../services/discourse_cache_manager.dart';
import 'webview_page.dart';
import 'login_page.dart';
import '../widgets/layout/phone_chrome.dart';
import '../widgets/auth/qr_login_sheet.dart';
import 'browsing_history_page.dart';
import 'bookmarks_page.dart';
import 'export_history_page.dart';
import 'my_browser_page.dart';
import 'my_topics_page.dart';
import 'my_badges_page.dart';
import 'user_profile_page.dart';

import 'package:m3e_ui/m3e_ui.dart';

import '../widgets/common/loading_dialog.dart';
import '../widgets/common/flair_badge.dart';
import '../widgets/common/smart_avatar.dart';
import '../providers/app_state_refresher.dart';

import 'package:ai_model_manager/ai_model_manager.dart';

import 'topic_detail_page/topic_detail_page.dart';
import 'drafts_page.dart';
import 'pending_posts_page.dart';
import 'private_messages_page.dart';
import 'invite_links_page.dart';
import '../widgets/profile_stats_card.dart';
import '../widgets/common/spotlight_overlay.dart';
import 'profile_stats_edit_page.dart';
import '../l10n/s.dart';
import '../navigation/nav_action_bus.dart';
import '../utils/dialog_utils.dart';
import '../services/emoji_handler.dart';
import '../services/log/log_writer.dart';
import '../widgets/layout/master_detail_layout.dart';

/// 个人页面
class ProfilePage extends ConsumerStatefulWidget {
  final bool isActive;
  const ProfilePage({super.key, this.isActive = false});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late ScrollController _scrollController;
  late ScrollController _rightScrollController;
  bool _showTitle = false;
  bool _isRefreshing = false;

  // 统计卡片引导
  static const String _guideKey = 'profile_stats_card_guide_shown';
  final GlobalKey _statsCardKey = GlobalKey();
  bool _guideShown = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _rightScrollController = ScrollController();
  }

  @override
  void didUpdateWidget(ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // tab 切换时 isActive 变化
    if (widget.isActive && !oldWidget.isActive) {
      if (!_guideShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryShowStatsGuide();
        });
      }
    }
  }

  /// 刷新页面数据。
  ///
  /// [showAppBarIndicator] 为 false 时不点亮 AppBar 的刷新指示:
  /// 下拉/快捷键刷新自带圆片 spinner,再亮 AppBar 就是同屏双 loading;
  /// AppBar 指示只留给无下拉指示器的静默刷新(tab 切回等)。
  Future<void> _refreshData({bool showAppBarIndicator = true}) async {
    if (!mounted) return;
    if (showAppBarIndicator) setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        ref.read(currentUserProvider.notifier).refreshSilently(force: true),
        ref.read(userSummaryProvider.notifier).refresh(),
      ]);
    } finally {
      if (mounted && showAppBarIndicator) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  void dispose() {
    SpotlightOverlay.dismiss();
    _scrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  /// 统计卡片引导：页面可见且卡片已渲染时触发（仅一次）
  Future<void> _tryShowStatsGuide() async {
    if (_guideShown) return;
    if (!widget.isActive) return;

    final renderObj =
        _statsCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObj == null || !renderObj.hasSize) return;

    _guideShown = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_guideKey) == true) return;
    await prefs.setBool(_guideKey, true);

    if (!mounted) return;
    SpotlightOverlay.show(
      context,
      targetKey: _statsCardKey,
      message: S.current.profileStats_guideMessage,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // 发布"距顶进度"给底栏图标（NavActionBus 的 progress provider）
    _publishProfileScrollProgress();

    // 双栏模式下头像始终可见，无需标题动画
    if (MasterDetailLayout.canShowBothPanesFor(context)) {
      if (_showTitle) setState(() => _showTitle = false);
      return;
    }

    // 当滚动超过一定距离（例如头像区域的高度）时显示标题
    // 头像(72) + padding(大概20)
    final show = _scrollController.offset > 80;
    if (show != _showTitle) {
      setState(() {
        _showTitle = show;
      });
    }
  }

  void _publishProfileScrollProgress() {
    final raw = _scrollController.offset;
    final progress = raw < 0 ? 0.0 : raw;
    final current = ref.read(navScrollProgressProvider(NavEntryIds.profile));
    final atZero = progress == 0 && current != 0;
    final crossed =
        (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4.0) return;
    ref.read(navScrollProgressProvider(NavEntryIds.profile).notifier).state =
        progress;
  }

  Future<void> _goToLogin() async {
    // 提前捕获 container:登录路由弹出/平行视界重挂载可能让本元素短暂
    // deactivate(此时 mounted 仍为 true),任何祖先查找(context.l10n、
    // Navigator.of、containerOf)都会抛错;曾因此把 refreshAll 整段掐死,
    // 表现为扫码登录成功后 UI 无登录态、要重启才恢复。
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (result != true) return;

    // 等一帧让路由弹出与重挂载稳定;deactivate 未复活的元素此刻已 unmount,
    // mounted 重新可信。刷新在任何分支都必须执行,不依赖本元素存活。
    await WidgetsBinding.instance.endOfFrame;
    AppStateRefresher.refreshAll(container);

    if (!mounted) return;
    final loading = LoadingDialog.show(
      context,
      message: S.current.profile_loadingData,
    );
    try {
      await Future.wait([
        container.read(currentUserProvider.future),
        container.read(userSummaryProvider.future),
      ]).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[ProfilePage] 登录后刷新失败/超时: $e');
      // 超时或错误时继续
    } finally {
      loading.hide();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.profile_confirmLogout),
        content: Text(context.l10n.profile_logoutContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_exit),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // provider 容器要在 widget 销毁前取好:resetForLogout 执行时本页可能
      // 已经不在树上,那时再 ProviderScope.containerOf(context) 会失败。
      final container = ProviderScope.containerOf(context, listen: false);

      // 用 controller 而非静态 hide(context):resetForLogout 会 invalidate
      // 整棵 provider 树,本页 widget 随之销毁,mounted 变 false —— 若用
      // `if (mounted) LoadingDialog.hide(context)`,这段会被整体跳过,弹窗
      // 永久留在根 navigator 上(现象:一直卡「正在退出…」)。
      // controller 持有 NavigatorState,不依赖本 widget 的生命周期。
      final loading = LoadingDialog.show(
        context,
        message: context.l10n.profile_loggingOut,
      );

      // 记录主动退出日志
      LogWriter.instance.write({
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'type': 'lifecycle',
        'event': 'logout_active',
        'message': '用户主动退出登录',
      });

      try {
        await ref.read(discourseServiceProvider).logout(callApi: true);
        // 这里刻意不判 mounted:provider 容器的生命周期与本 widget 无关,
        // 状态重置必须执行完(否则登出后残留上一个账号的缓存)。
        await AppStateRefresher.resetForLogout(container);
      } catch (e) {
        debugPrint('[ProfilePage] 退出登录异常: $e');
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'type': 'lifecycle',
          'event': 'logout_error',
          'message': '退出登录过程出错，本地状态已尽力清理',
          'error': e.toString(),
        });
      } finally {
        loading.hide();
      }
    }
  }

  Future<void> _openProfileEdit() async {
    final username = ref.read(currentUserProvider).value?.username;
    if (username != null && username.isNotEmpty) {
      await WebViewPage.open(
        context,
        '${AppConstants.baseUrl}/u/$username/preferences/account',
        title: context.l10n.profile_editProfile,
        injectCss: '''
          .new-user-content-wrapper {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            height: 100% !important;
            z-index: 100 !important;
            background: var(--d-content-background, var(--secondary)) !important;
            overflow-y: auto !important;
            padding: 20px !important;
            box-sizing: border-box !important;
          }
          .d-header {
            display: none !important;
          }
        ''',
      );

      // 返回后静默刷新数据
      if (mounted) {
        ref.read(currentUserProvider.notifier).refreshSilently().ignore();
        ref.read(userSummaryProvider.notifier).refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userState = ref.watch(currentUserProvider);
    final isLoggedIn = userState.value != null;
    final user = userState.value;

    final isOffline =
        userState.hasError && userState.hasValue && userState.value != null;
    final showWideLayout = MasterDetailLayout.canShowBothPanesFor(context);

    // 监听底栏派发的快捷动作（仅活跃 tab 响应）
    ref.listen(navActionBusProvider, (_, event) {
      if (event == null) return;
      if (event.targetId != NavEntryIds.profile) return;
      if (!widget.isActive) return;
      switch (event.action) {
        case NavAction.scrollToTop:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          break;
        case NavAction.refresh:
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          _refreshData();
          ref.resetNavScrollProgress(NavEntryIds.profile);
          break;
      }
    });

    final scaffold = Scaffold(
      appBar: AppNavBar(
        title: context.l10n.nav_mine,
        automaticallyImplyLeading: false,
        slotWidth: isLoggedIn ? 110 : 70,
        trailing: [
          if (isLoggedIn) ...[
            // 状态指示（固定占位，避免后方图标闪烁）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isRefreshing
                  ? const SizedBox(
                      key: ValueKey('refreshing'),
                      width: AppSize.hit,
                      height: AppSize.hit,
                      child: Center(child: LoadingSpinner(size: 18)),
                    )
                  : isOffline
                  ? SizedBox(
                      key: const ValueKey('offline'),
                      width: AppSize.hit,
                      height: AppSize.hit,
                      child: Icon(
                        AppIcons.serverOff,
                        size: AppSize.iconL,
                        color: context.tokens.colors.textMeta,
                      ),
                    )
                  : const SizedBox(key: ValueKey('idle'), width: 0),
            ),
            AppIconButton(
              icon: AppIcons.qrCode,
              semanticLabel: context.l10n.login_qrShowCode,
              onPressed: () =>
                  showQrLoginSheet(context, username: user?.username),
            ),
            AppIconButton(
              icon: AppIcons.edit,
              semanticLabel: context.l10n.profile_editProfile,
              onPressed: _openProfileEdit,
            ),
          ],
        ],
      ),
      // 「我的」页是**导航枢纽**:所有入口(话题/设置/资料…)一律开
      // 新页面,不做右栏平行视界(曾接过 panes 宿主,用户拍板退役:
      // 本页不存在"切换别的页面"的语义)。宽屏纯静态双栏(左资料卡
      // 右功能卡),窄屏单列。
      body: ReadableBody(
        child: showWideLayout
            ? MasterDetailLayout(
                // 左栏是定宽资料卡,保持固定 360:不可拖拽、不随窗口
                // 比例放宽。
                masterWidth: 360,
                resizableMaster: false,
                master: _buildLeftPanel(theme),
                emptyDetail: _buildRightPanel(theme),
              )
            : _buildMobileBody(theme),
      ),
    );
    return scaffold;
  }

  /// 手机端：保持原有单列布局
  Widget _buildMobileBody(ThemeData theme) {
    final userState = ref.watch(currentUserProvider);
    final isLoggedIn = userState.value != null;
    final user = userState.value;
    final isLoadingInitial = userState.isLoading && !userState.hasValue;
    final hasError = userState.hasError && !userState.hasValue;
    final errorMessage = userState.error?.toString() ?? '';

    return DesktopRefreshIndicator(
      refreshNotifier: masterRefreshNotifier,
      shouldRefresh: () => widget.isActive,
      onRefresh: () => _refreshData(showAppBarIndicator: false),
      child: ListView(
        controller: _scrollController,
        // 底部给 Tab 胶囊留 120（设计说明 §5.1）
        padding: EdgeInsets.only(
          top: AppSpace.s,
          bottom: kPhoneChromeHeight + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: AppSpace.m),

          if (isLoadingInitial)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(64),
                child: LoadingSpinner(),
              ),
            )
          else if (hasError)
            _buildError(theme, errorMessage)
          else if (isLoggedIn)
            _buildStatsCardWithGuide(),

          if (isLoggedIn) ...[
            _buildContentCard(theme),
            const SizedBox(height: AppSpace.l),
            _buildCommunityCard(
              theme,
              canAccessInviteLinks: (user?.trustLevel ?? 0) >= 3,
            ),
            const SizedBox(height: AppSpace.l),
          ],

          _buildSystemAndToolsCard(theme),
          const SizedBox(height: AppSpace.l),
          _buildAuthButton(theme, isLoggedIn),
          if (!isLoggedIn)
            Padding(
              padding: const EdgeInsets.all(AppSpace.pageMargin),
              child: Text(
                context.l10n.profile_browseWithoutLogin,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.merge(context.tokens.text.meta)
                    .copyWith(color: context.tokens.colors.textMeta),
              ),
            ),
        ],
      ),
    );
  }

  /// 左面板：资料卡 + 统计 + 余额卡片 + 登录/退出按钮固定底部
  Widget _buildLeftPanel(ThemeData theme) {
    final userState = ref.watch(currentUserProvider);
    final isLoggedIn = userState.value != null;
    final isLoadingInitial = userState.isLoading && !userState.hasValue;
    final hasError = userState.hasError && !userState.hasValue;
    final errorMessage = userState.error?.toString() ?? '';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                const _ProfileHeader(),
                const SizedBox(height: 24),

                if (isLoadingInitial)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(64),
                      child: LoadingSpinner(),
                    ),
                  )
                else if (hasError)
                  _buildError(theme, errorMessage)
                else if (isLoggedIn)
                  _buildStatsCardWithGuide(),

                if (isLoggedIn) ...[
                  _buildContentCard(theme),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _buildAuthButton(theme, isLoggedIn),
        ),
      ],
    );
  }

  /// 右面板：功能菜单卡片
  Widget _buildRightPanel(ThemeData theme) {
    final userState = ref.watch(currentUserProvider);
    final isLoggedIn = userState.value != null;
    final user = userState.value;

    return DesktopRefreshIndicator(
      refreshNotifier: masterRefreshNotifier,
      shouldRefresh: () => widget.isActive,
      onRefresh: () => _refreshData(showAppBarIndicator: false),
      child: ListView(
        controller: _rightScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (isLoggedIn) ...[
            _buildCommunityCard(
              theme,
              canAccessInviteLinks: (user?.trustLevel ?? 0) >= 3,
            ),
            const SizedBox(height: 20),
          ],
          _buildSystemAndToolsCard(theme),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.m),
        decoration: ShapeDecoration(
          color: colors.surfaceGrouped,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.tokens.radius.card),
          ),
        ),
        child: Row(
          children: [
            Icon(
              AppIcons.error,
              size: AppSize.iconM,
              color: colors.textDestructive,
            ),
            const SizedBox(width: AppSpace.m),
            Expanded(
              child: Text(
                '${context.l10n.common_loadFailed}: $error',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(currentUserProvider),
              child: Text(context.l10n.common_retry),
            ),
          ],
        ),
      ),
    );
  }

  /// 统计卡片 + 引导触发
  Widget _buildStatsCardWithGuide() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
          child: ProfileStatsCard(
            statsCardKey: _statsCardKey,
            onEdit: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileStatsEditPage()),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.l),
      ],
    );
  }

  void _openDrafts() {
    // 草稿页是独立的双栏页(宽屏自带"左列表右话题"),所有入口统一
    // 全屏打开,不再往「我的」页右栏塞草稿层。
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DraftsPage()),
    );
  }

  Widget _buildContentCard(ThemeData theme) {
    return _group([
      _buildOptionTile(
        icon: AppIcons.article,
        title: context.l10n.profile_myTopics,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyTopicsPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.bookmark,
        title: context.l10n.profile_myBookmarks,
        // 书签数取已加载的用户概览，不为这个数字另发请求
        detail: _bookmarkCountText(),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BookmarksPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.description,
        title: context.l10n.profile_myDrafts,
        onTap: _openDrafts,
      ),
      _buildOptionTile(
        icon: AppIcons.history,
        title: context.l10n.profile_browsingHistory,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BrowsingHistoryPage()),
        ),
      ),
    ]);
  }

  /// 分组列表：外边距 20，圆角取 radius/card；行高 48，图标 20 brand
  Widget _group(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
      child: SegmentedCardGroup(children: children),
    );
  }

  Widget _buildCommunityCard(
    ThemeData theme, {
    required bool canAccessInviteLinks,
  }) {
    return _group([
      _buildOptionTile(
        icon: AppIcons.mail,
        title: context.l10n.profile_privateMessages,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PrivateMessagesPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.inbox,
        title: context.l10n.review_myPending,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PendingPostsPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.medal,
        title: context.l10n.profile_myBadges,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyBadgesPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.note,
        title: '我的笔记',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotesPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.speed,
        title: '阅读统计',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReadingStatsPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.saveAlt,
        title: '已存帖子',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SavedTopicsPage()),
        ),
      ),
      if (canAccessInviteLinks)
        _buildOptionTile(
          icon: AppIcons.link,
          title: context.l10n.profile_inviteLinks,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InviteLinksPage()),
          ),
        ),
      _buildOptionTile(
        icon: AppIcons.download,
        title: context.l10n.exportHistory_title,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExportHistoryPage()),
        ),
      ),
    ]);
  }

  Widget _buildSystemAndToolsCard(ThemeData theme) {
    return _group([
      _buildOptionTile(
        icon: AppIcons.language,
        title: context.l10n.profile_myBrowser,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyBrowserPage()),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.autoAwesome,
        title: context.l10n.profile_aiModelService,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AiProvidersPage(
              onOpenSession: (ctx, topicId, sessionId) {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => TopicDetailPage(
                      topicId: topicId,
                      autoOpenAiChat: true,
                      initialSessionId: sessionId,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      _buildOptionTile(
        icon: AppIcons.settings,
        title: context.l10n.profile_settings,
        // 导航枢纽语义:开新页面(本页无 EmbeddedStackScope,
        // openSettings 自然走全屏 push,与其他入口一致)。
        onTap: () => EmbeddedStackScope.openSettings(context),
      ),
    ]);
  }

  /// 分组列表行：高 48，图标 20 brand/primary 线框（不再用彩色方块），
  /// 标题 17，右侧 chevron-right 16
  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? detail,
  }) {
    final tokens = context.tokens;
    return AppPressable(
      highlight: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
          child: Row(
            children: [
              Icon(
                icon,
                size: AppSize.iconM,
                color: tokens.colors.brandPrimary,
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.merge(tokens.text.control)
                      .copyWith(color: tokens.colors.textPrimary),
                ),
              ),
              if (detail != null) ...[
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.merge(tokens.text.meta)
                      .copyWith(color: tokens.colors.textMeta),
                ),
                const SizedBox(width: AppSpace.xs),
              ],
              Icon(
                AppIcons.chevronRight,
                size: AppSize.iconS,
                color: tokens.colors.textMeta,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _bookmarkCountText() {
    final count = ref.watch(userSummaryProvider).value?.bookmarkCount;
    return count == null || count <= 0 ? null : '$count';
  }

  Widget _buildAuthButton(ThemeData theme, bool isLoggedIn) {
    final tokens = context.tokens;
    if (isLoggedIn) {
      // 单独一组「退出登录」：破坏性、居中
      return _group([
        AppPressable(
          highlight: true,
          onTap: _logout,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.row48),
            child: Center(
              child: Text(
                context.l10n.profile_logoutCurrentAccount,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.merge(tokens.text.control)
                    .copyWith(color: tokens.colors.textDestructive),
              ),
            ),
          ),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
      child: FilledButton(
        onPressed: _goToLogin,
        style: AppButtonStyles.large,
        child: Text(context.l10n.profile_loginForum),
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(
      currentUserProvider.select((value) => value.value?.id),
    );
    final username = ref.watch(
      currentUserProvider.select((value) => value.value?.username),
    );
    final isLoggedIn = ref.watch(
      currentUserProvider.select((value) => value.value != null),
    );
    final canNavigate = username != null && username.isNotEmpty;

    // 头部行 pad 12 20：大头像 64 + 名字 17 Semibold + 「@handle · L2 成员」13 meta +
    // chevron-right（整行 → 自己的用户主页）
    return AppPressable(
      onTap: canNavigate
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(username: username),
                ),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.pageMargin,
          vertical: AppSpace.m,
        ),
        child: Row(
          children: [
            _ProfileAvatarSection(userId: userId, isLoggedIn: isLoggedIn),
            const SizedBox(width: AppSpace.m),
            const Expanded(child: _ProfileInfoSection()),
            if (isLoggedIn)
              Icon(
                AppIcons.chevronRight,
                size: AppSize.iconM,
                color: context.tokens.colors.textMeta,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatarSection extends ConsumerWidget {
  final int? userId;
  final bool isLoggedIn;

  const _ProfileAvatarSection({required this.userId, required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = ref.watch(
      currentUserProvider.select((value) => value.value?.getAvatarUrl() ?? ''),
    );
    final flairUrl = ref.watch(
      currentUserProvider.select((value) => value.value?.flairUrl),
    );
    final flairName = ref.watch(
      currentUserProvider.select((value) => value.value?.flairName),
    );
    final flairBgColor = ref.watch(
      currentUserProvider.select((value) => value.value?.flairBgColor),
    );
    final flairColor = ref.watch(
      currentUserProvider.select((value) => value.value?.flairColor),
    );

    return _ProfileAvatar(
      key: ValueKey('profile-avatar-$userId'),
      userId: userId,
      avatarUrl: avatarUrl,
      isLoggedIn: isLoggedIn,
      flairUrl: flairUrl,
      flairName: flairName,
      flairBgColor: flairBgColor,
      flairColor: flairColor,
    );
  }
}

class _ProfileInfoSection extends ConsumerWidget {
  const _ProfileInfoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final name = ref.watch(
      currentUserProvider.select((value) => value.value?.name),
    );
    final username = ref.watch(
      currentUserProvider.select((value) => value.value?.username),
    );
    final trustLevel = ref.watch(
      currentUserProvider.select((value) => value.value?.trustLevel),
    );
    final status = ref.watch(
      currentUserProvider.select((value) => value.value?.status),
    );
    final isLoggedIn = ref.watch(
      currentUserProvider.select((value) => value.value != null),
    );
    final meta = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name ??
              username ??
              (isLoggedIn
                  ? context.l10n.common_loading
                  : context.l10n.profile_notLoggedIn),
          style: theme.textTheme.titleMedium
              ?.merge(tokens.text.headline)
              .copyWith(color: tokens.colors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpace.xs),
        if (isLoggedIn) ...[
          Text(
            '@${username ?? ''} · ${_getTrustLevelLabel(trustLevel ?? 0)}',
            style: meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpace.xs),
            _buildStatusChip(status, theme),
          ],
        ] else
          Text(context.l10n.profile_loginForMore, style: meta),
      ],
    );
  }
}

/// 独立的头像组件，使用 AutomaticKeepAliveClientMixin 避免重建
class _ProfileAvatar extends StatefulWidget {
  final int? userId;
  final String avatarUrl;
  final bool isLoggedIn;
  final String? flairUrl;
  final String? flairName;
  final String? flairBgColor;
  final String? flairColor;

  const _ProfileAvatar({
    super.key,
    required this.userId,
    required this.avatarUrl,
    required this.isLoggedIn,
    this.flairUrl,
    this.flairName,
    this.flairBgColor,
    this.flairColor,
  });

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar>
    with AutomaticKeepAliveClientMixin {
  Widget? _cachedAvatarWithFlair;
  String _cachedSignature = '';

  @override
  bool get wantKeepAlive => true;

  String _buildCacheSignature() {
    return '${widget.avatarUrl}_${widget.flairUrl}_${widget.flairName}_${widget.flairBgColor}_${widget.flairColor}';
  }

  @override
  void didUpdateWidget(_ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSignature = _buildCacheSignature();
    if (newSignature != _cachedSignature) {
      _cachedAvatarWithFlair = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin

    final signature = _buildCacheSignature();
    if (_cachedAvatarWithFlair != null && signature == _cachedSignature) {
      return _cachedAvatarWithFlair!;
    }
    _cachedSignature = signature;

    _cachedAvatarWithFlair = AvatarWithFlair(
      key: ValueKey('profile-avatar-flair-${widget.userId}-${widget.flairUrl}'),
      flairSize: 24,
      flairRight: -2,
      flairBottom: -2,
      flairUrl: widget.flairUrl,
      flairName: widget.flairName,
      flairBgColor: widget.flairBgColor,
      flairColor: widget.flairColor,
      avatar: SmartAvatar(
        imageUrl: widget.avatarUrl.isNotEmpty ? widget.avatarUrl : null,
        radius: 32,
        fallbackText: widget.isLoggedIn ? null : '',
        backgroundColor: context.tokens.colors.avatarFill,
      ),
    );

    return _cachedAvatarWithFlair!;
  }
}

String _getTrustLevelLabel(int level) {
  switch (level) {
    case 0:
      return S.current.user_trustLevel0;
    case 1:
      return S.current.user_trustLevel1;
    case 2:
      return S.current.user_trustLevel2;
    case 3:
      return S.current.user_trustLevel3;
    case 4:
      return S.current.user_trustLevel4;
    default:
      return 'L$level';
  }
}

Widget _buildStatusEmoji(UserStatus status) {
  final emoji = status.emoji;
  if (emoji == null || emoji.isEmpty) return const SizedBox.shrink();

  final isEmojiName =
      emoji.contains(RegExp(r'[a-zA-Z0-9_]')) &&
      !emoji.contains(RegExp(r'[^\x00-\x7F]'));

  if (isEmojiName) {
    final cleanName = emoji.replaceAll(':', '');
    final emojiUrl = EmojiHandler().getEmojiUrl(cleanName);

    return Image(
      image: emojiImageProvider(emojiUrl),
      width: 14,
      height: 14,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  return Text(
    emoji,
    style: const TextStyle(fontSize: AppFontSize.meta, height: 1.2),
  );
}

Widget _buildStatusChip(UserStatus status, ThemeData theme) {
  final emoji = status.emoji;
  final description = status.description;

  if ((emoji == null || emoji.isEmpty) &&
      (description == null || description.isEmpty)) {
    return const SizedBox.shrink();
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppTokens.resolve(brightness: theme.brightness)
          .colors
          .surfaceGrouped,
      borderRadius: BorderRadius.circular(
        AppTokens.resolve(brightness: theme.brightness).radius.tag,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (emoji != null && emoji.isNotEmpty) ...[
          _buildStatusEmoji(status),
          if (description != null && description.isNotEmpty)
            const SizedBox(width: 4),
        ],
        if (description != null && description.isNotEmpty)
          Flexible(
            child: Text(
              description,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );
}
