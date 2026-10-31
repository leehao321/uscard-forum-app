import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification.dart';
import '../providers/discourse_providers.dart';
import '../providers/preferences_provider.dart';
import '../utils/load_more_coordinator.dart';
import '../widgets/desktop_refresh_indicator.dart';
import '../providers/selected_topic_provider.dart';
import '../utils/notification_navigation.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/layout/master_detail_pane_host.dart';
import '../widgets/notification/notification_item.dart';
import '../widgets/notification/notification_list_skeleton.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/paged_list_footer.dart';
import '../l10n/s.dart';
import '../utils/blocked_user_filter.dart';
import 'login_page.dart';

/// 页内筛选（设计说明 §5.1）：只筛已加载的列表，不改请求
enum NotificationFilter {
  all,
  unread,
  replies,
  mentions,
  likes,
  messages,
  badges,
  other;

  static const _replyTypes = {
    NotificationType.replied,
    NotificationType.posted,
    NotificationType.quoted,
    NotificationType.followingReplied,
  };
  static const _mentionTypes = {
    NotificationType.mentioned,
    NotificationType.groupMentioned,
    NotificationType.chatMention,
    NotificationType.chatGroupMention,
  };
  static const _likeTypes = {
    NotificationType.liked,
    NotificationType.likedConsolidated,
    NotificationType.reaction,
  };
  static const _messageTypes = {
    NotificationType.privateMessage,
    NotificationType.invitedToPrivateMessage,
  };

  bool matches(DiscourseNotification n) {
    final t = n.notificationType;
    switch (this) {
      case all:
        return true;
      case unread:
        return !n.read;
      case replies:
        return _replyTypes.contains(t);
      case mentions:
        return _mentionTypes.contains(t);
      case likes:
        return _likeTypes.contains(t);
      case messages:
        return _messageTypes.contains(t);
      case badges:
        return t == NotificationType.grantedBadge;
      case other:
        // 编辑、移动、群组、Boost、系统类等都收进「其他」
        return !_replyTypes.contains(t) &&
            !_mentionTypes.contains(t) &&
            !_likeTypes.contains(t) &&
            !_messageTypes.contains(t) &&
            t != NotificationType.grantedBadge;
    }
  }
}

/// 通知历史列表页面（独立分页，不受 messageBus 干扰）
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  NotificationFilter _filter = NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final notifier = ref.read(notificationListProvider.notifier);
    await _loadMoreCoordinator.loadMore(
      loadMore: notifier.loadMore,
      hasMore: () => notifier.hasMore,
      isActive: () => mounted,
      progressCount: () =>
          ref.read(notificationListProvider).value?.length ?? 0,
    );
  }

  Future<void> _onRefresh() async {
    _loadMoreCoordinator.resetCooldown();
    await ref.read(notificationListProvider.notifier).refresh();
  }

  String _filterLabel(NotificationFilter f) {
    final l10n = context.l10n;
    return switch (f) {
      NotificationFilter.all => l10n.notification_filterAll,
      NotificationFilter.unread => l10n.notification_filterUnread,
      NotificationFilter.replies => l10n.notification_filterReplies,
      NotificationFilter.mentions => l10n.notification_filterMentions,
      NotificationFilter.likes => l10n.notification_filterLikes,
      NotificationFilter.messages => l10n.notification_filterMessages,
      NotificationFilter.badges => l10n.notification_filterBadges,
      NotificationFilter.other => l10n.notification_filterOther,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(currentUserProvider).value != null;
    final notificationsAsync = ref.watch(notificationListProvider);
    final systemAvatarTemplate = ref
        .watch(systemUserAvatarTemplateProvider)
        .value;

    // 导航单行：中间「通知」，右侧 check-check（全部标为已读，无确认）
    final navBar = AppNavBar(
      title: context.l10n.common_notification,
      automaticallyImplyLeading: false,
      trailing: [
        if (isLoggedIn)
          AppIconButton(
            icon: AppIcons.checkAll,
            semanticLabel: context.l10n.notification_markAllRead,
            onPressed: () =>
                ref.read(notificationListProvider.notifier).markAllAsRead(),
          ),
      ],
    );

    if (!isLoggedIn) {
      return Scaffold(
        appBar: ReadableAppBar(child: navBar),
        body: ReadableBody(
          child: AppStateView(
            icon: AppIcons.notificationOff,
            title: context.l10n.notification_loginRequired,
            action: FilledButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LoginPage())),
              child: Text(context.l10n.common_login),
            ),
          ),
        ),
      );
    }

    final list = Scaffold(
      appBar: ReadableAppBar(child: navBar),
      body: ReadableBody(
        child: Column(
          children: [
            FilterTabs(
              labels: [
                for (final f in NotificationFilter.values) _filterLabel(f),
              ],
              selectedIndex: _filter.index,
              onSelected: (i) =>
                  setState(() => _filter = NotificationFilter.values[i]),
            ),
            Expanded(
              child: DesktopRefreshIndicator(
                onRefresh: _onRefresh,
                child: notificationsAsync.when(
                  data: (notifications) =>
                      _buildList(context, notifications, systemAvatarTemplate),
                  loading: () => const NotificationListSkeleton(),
                  error: (error, stack) => ErrorView(
                    error: error,
                    stackTrace: stack,
                    onRetry: _onRefresh,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // 宽屏：左列通知、右栏话题（平行视界），窄屏仍是单列
    return MasterDetailPaneHost(
      stackProvider: selectedNotificationsPaneProvider,
      isActive: true,
      // 左栏按自己的宽度量阅读列和安全区：双栏时全屏宽度的阅读列边距会把
      // 窄栏里的导航栏挤到溢出
      master: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          if (constraints.maxWidth >= media.size.width - 1) return list;
          return MediaQuery(
            data: media.copyWith(
              size: Size(constraints.maxWidth, media.size.height),
              padding: media.padding.copyWith(left: 0, right: 0),
              viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
            ),
            child: list,
          );
        },
      ),
    );
  }

  /// 点通知：宽屏且有话题落点时进右栏，其余走原来的跳转 / 弹窗
  void _onTap(
    DiscourseNotification notification,
    List<DiscourseNotification> siblings,
  ) {
    final topicId = notification.topicId;
    if (topicId != null && MasterDetailLayout.canShowBothPanesFor(context)) {
      if (!notification.read) {
        markNotificationReadOnTap(context, notification);
        ref.read(notificationListProvider.notifier).markAsRead(notification.id);
      }
      ref
          .read(selectedNotificationsPaneProvider.notifier)
          .select(
            topicId: topicId,
            initialTitle: notification.fancyTitle,
            scrollToPostNumber: notification.postNumber,
          );
      return;
    }
    handleNotificationTap(context, ref, notification, siblings: siblings);
  }

  Widget _buildList(
    BuildContext context,
    List<DiscourseNotification> notifications,
    String? systemAvatarTemplate,
  ) {
    final blockedUsernames = ref.watch(
      preferencesProvider.select((p) => p.normalizedBlockedUsernames),
    );
    final visibleNotifications = notifications
        .where(
          (notification) =>
              !BlockedUserFilter.isBlockedNotification(
                notification,
                blockedUsernames,
              ) &&
              _filter.matches(notification),
        )
        .toList(growable: false);
    final notifier = ref.read(notificationListProvider.notifier);
    // 已加载页全部被本地屏蔽 / 筛掉时列表不可滚，滚动触发的翻页发生不了。
    // 不自动补载（冷却按未筛选列表算，筛选没有匹配时会一页接一页地翻下去），
    // 改成空状态里给一个用户手动点的「加载更早的通知」。
    if (visibleNotifications.isEmpty) {
      return AppStateView(
        icon: AppIcons.notification,
        title: _filter == NotificationFilter.all
            ? context.l10n.notification_empty
            : context.l10n.notification_emptyFiltered,
        action: notifier.hasMore && notifications.isNotEmpty
            ? OutlinedButton(
                key: const ValueKey('notification-load-earlier'),
                onPressed: notifier.isLoadingMore ? null : _loadMore,
                child: Text(context.l10n.notification_loadEarlier),
              )
            : null,
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visibleNotifications.length + 1,
      separatorBuilder: (_, i) => i == visibleNotifications.length - 1
          ? const SizedBox.shrink()
          : const AppHairline(indent: AvatarRow.separatorIndent),
      itemBuilder: (context, index) {
        if (index == visibleNotifications.length) {
          final footer = PagedListFooter(
            hasMore: notifier.hasMore,
            isLoadingMore: notifier.isLoadingMore,
            isLoadMoreFailed: notifier.isLoadMoreFailed,
            onRetry: notifier.retryLoadMore,
          );
          // 筛选后只剩一两条时列表不满一屏，滚动触发的翻页发生不了：
          // 有筛掉的内容且还有下一页时，给用户手动点的「加载更早的通知」
          final filteredOut =
              visibleNotifications.length < notifications.length;
          if (filteredOut &&
              notifier.hasMore &&
              !notifier.isLoadingMore &&
              !notifier.isLoadMoreFailed) {
            return Column(
              children: [
                TextButton(
                  key: const ValueKey('notification-load-earlier-footer'),
                  onPressed: _loadMore,
                  child: Text(context.l10n.notification_loadEarlier),
                ),
                footer,
              ],
            );
          }
          return footer;
        }
        final notification = visibleNotifications[index];
        return NotificationItem(
          notification: notification,
          systemAvatarTemplate: systemAvatarTemplate,
          // siblings = 当前已加载列表,大屏弹窗内可上一条/下一条
          onTap: () => _onTap(notification, visibleNotifications),
        );
      },
    );
  }
}
