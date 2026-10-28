import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../../config/sites/uscard.dart';
import '../../../l10n/s.dart';
import '../../../providers/preferences_provider.dart';

/// 当前站点能用的手势动作。美卡没有树形回复插件，不提供「切换树形视图」。
/// 设置里的选择列表和长按菜单都从这里取，已保存的旧配置也会被滤掉。
bool isProgressGestureActionAvailable(ProgressGestureAction action) =>
    action != ProgressGestureAction.toggleNestedView ||
    uscardCustomization.supportsNestedView;

List<ProgressGestureAction> availableProgressGestureActions() => [
  for (final a in ProgressGestureAction.values)
    if (isProgressGestureActionAvailable(a)) a,
];

/// 进度悬浮条手势动作的元数据（图标 + 本地化标签）
/// 半圆菜单、设置 picker、subtitle 等多处共用
({IconData icon, String label}) progressGestureActionMeta(
  BuildContext context,
  ProgressGestureAction action,
) {
  final l = context.l10n;
  switch (action) {
    case ProgressGestureAction.none:
      return (
        icon: Symbols.do_not_disturb_on_rounded,
        label: l.progressGesture_action_none,
      );
    case ProgressGestureAction.openTimeline:
      return (
        icon: Symbols.unfold_more_rounded,
        label: l.progressGesture_action_openTimeline,
      );
    case ProgressGestureAction.scrollToTop:
      return (
        icon: Symbols.vertical_align_top_rounded,
        label: l.progressGesture_action_scrollToTop,
      );
    case ProgressGestureAction.jumpToUnread:
      return (
        icon: Symbols.mark_chat_unread_rounded,
        label: l.progressGesture_action_jumpToUnread,
      );
    case ProgressGestureAction.nextPost:
      return (
        icon: Symbols.south_rounded,
        label: l.progressGesture_action_nextPost,
      );
    case ProgressGestureAction.previousPost:
      return (
        icon: Symbols.north_rounded,
        label: l.progressGesture_action_previousPost,
      );
    case ProgressGestureAction.reply:
      return (
        icon: Symbols.reply_rounded,
        label: l.progressGesture_action_reply,
      );
    case ProgressGestureAction.share:
      return (
        icon: Symbols.link_rounded,
        label: l.progressGesture_action_share,
      );
    case ProgressGestureAction.shareImage:
      return (
        icon: Symbols.image_rounded,
        label: l.progressGesture_action_shareImage,
      );
    case ProgressGestureAction.exportArticle:
      return (
        icon: Symbols.download_rounded,
        label: l.progressGesture_action_exportArticle,
      );
    case ProgressGestureAction.openInBrowser:
      return (
        icon: Symbols.language_rounded,
        label: l.progressGesture_action_openInBrowser,
      );
    case ProgressGestureAction.bookmark:
      return (
        icon: Symbols.bookmark_border_rounded,
        label: l.progressGesture_action_bookmark,
      );
    case ProgressGestureAction.readLater:
      return (
        icon: Symbols.layers_rounded,
        label: l.progressGesture_action_readLater,
      );
    case ProgressGestureAction.notification:
      return (
        icon: Symbols.notifications_none_rounded,
        label: l.progressGesture_action_notification,
      );
    case ProgressGestureAction.filter:
      return (
        icon: Symbols.filter_list_rounded,
        label: l.progressGesture_action_filter,
      );
    case ProgressGestureAction.toggleNestedView:
      return (
        icon: Symbols.account_tree_rounded,
        label: l.progressGesture_action_toggleNestedView,
      );
    case ProgressGestureAction.aiAssistant:
      return (
        icon: Symbols.auto_awesome_rounded,
        label: l.progressGesture_action_aiAssistant,
      );
    case ProgressGestureAction.readingSettings:
      return (
        icon: Symbols.auto_stories_rounded,
        label: l.progressGesture_action_readingSettings,
      );
    case ProgressGestureAction.search:
      return (
        icon: Symbols.search_rounded,
        label: l.progressGesture_action_search,
      );
    case ProgressGestureAction.refresh:
      return (
        icon: Symbols.refresh_rounded,
        label: l.progressGesture_action_refresh,
      );
    case ProgressGestureAction.goBack:
      return (
        icon: Symbols.arrow_back_rounded,
        label: l.progressGesture_action_goBack,
      );
  }
}
