import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/user.dart';
import '../pages/bookmarks_page.dart';
import '../pages/browsing_history_page.dart';
import '../pages/drafts_page.dart';
import '../pages/notifications_page.dart';
import '../pages/private_messages_page.dart';
import '../pages/profile_page.dart';
import '../pages/topics_screen.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/smart_avatar.dart';
import 'nav_action_bus.dart';
import 'nav_entry.dart';

/// 注册所有可选底栏入口
///
/// 用户在底栏布局编辑器里从这些里挑选显示哪些、顺序如何。
/// 增加新入口时在 [buildAll] 里追加一条即可。
class NavEntryRegistry {
  NavEntryRegistry._();

  /// 构建完整候选列表
  static List<NavEntry> buildAll() {
    final entries = [
      NavEntry(
        id: NavEntryIds.home,
        kind: NavEntryKind.page,
        iconData: AppIcons.home,
        selectedIconData: AppIcons.home,
        label: (ctx) => ctx.l10n.nav_home,
        pageBuilder: (ctx, isActive) => TopicsScreen(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
      ),
      NavEntry(
        id: NavEntryIds.profile,
        kind: NavEntryKind.page,
        iconData: AppIcons.person,
        selectedIconData: AppIcons.person,
        label: (ctx) => ctx.l10n.nav_mine,
        pageBuilder: (ctx, isActive) => ProfilePage(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
        // 已登录时用用户头像替代默认图标
        customIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: false),
        customSelectedIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: true),
      ),
      NavEntry(
        id: NavEntryIds.bookmarks,
        kind: NavEntryKind.page,
        iconData: AppIcons.bookmark,
        selectedIconData: AppIcons.bookmark,
        label: (ctx) => ctx.l10n.nav_bookmarks,
        pageBuilder: (ctx, isActive) => BookmarksPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.history,
        kind: NavEntryKind.page,
        iconData: AppIcons.history,
        selectedIconData: AppIcons.history,
        label: (ctx) => ctx.l10n.nav_history,
        pageBuilder: (ctx, isActive) =>
            BrowsingHistoryPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.drafts,
        kind: NavEntryKind.page,
        iconData: AppIcons.article,
        selectedIconData: AppIcons.article,
        label: (ctx) => ctx.l10n.nav_drafts,
        pageBuilder: (ctx, isActive) => DraftsPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.messages,
        kind: NavEntryKind.page,
        iconData: AppIcons.mail,
        selectedIconData: AppIcons.mail,
        label: (ctx) => ctx.l10n.nav_messages,
        pageBuilder: (ctx, isActive) =>
            PrivateMessagesPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        // 0.4.0：通知是一个 Tab 页（原来是快捷面板）
        id: NavEntryIds.notifications,
        kind: NavEntryKind.page,
        iconData: AppIcons.notification,
        selectedIconData: AppIcons.notification,
        label: (ctx) => ctx.l10n.nav_notifications,
        pageBuilder: (ctx, isActive) => const NotificationsPage(),
        requiresLogin: true,
        defaultInBottomNav: true,
      ),
    ];
    return entries;
  }

  /// 按 id 查找 entry
  static NavEntry? byId(String id) {
    for (final e in buildAll()) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 根据用户登录状态过滤可用 entry
  static bool isAvailable(NavEntry entry, User? user) {
    if (!entry.requiresLogin) return true;
    return user != null;
  }

  /// 默认底栏 id 列表：首页、通知、我的
  static List<String> defaultBottomNavIds() => const [
    NavEntryIds.home,
    NavEntryIds.notifications,
    NavEntryIds.profile,
  ];

  /// 必须包含的 locked id 列表
  static List<String> lockedIds() {
    return buildAll().where((e) => e.locked).map((e) => e.id).toList();
  }
}

Widget _profileIcon(
  BuildContext context,
  WidgetRef ref, {
  required bool selected,
}) {
  final user = ref.watch(currentUserProvider).value;
  final avatarUrl = user?.getAvatarUrl();
  final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
  if (hasAvatar) {
    return SmartAvatar(
      imageUrl: avatarUrl,
      radius: 12,
      fallbackText: user?.username,
    );
  }
  return Icon(AppIcons.person, fill: selected ? 1 : 0);
}
