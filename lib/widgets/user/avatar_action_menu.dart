import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/services.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/selected_topic_provider.dart';
import '../../services/toast_service.dart';
import '../../utils/share_utils.dart';
import '../post/reply_sheet.dart';

/// 复制用户名到剪贴板并 toast + 轻触觉（长按菜单/用户卡片/用户主页共用）
void copyUsernameToClipboard(String username) {
  Clipboard.setData(ClipboardData(text: username));
  HapticFeedback.selectionClick();
  ToastService.showSuccess(S.current.common_copiedToClipboard);
}

/// 打开「给指定用户发私信」编辑器。
///
/// 带话题上下文（[topicId]/[postNumber]）时正文预填帖子链接、
/// 标题预填「回复:话题标题」（[topicTitle] 为空时回退话题会话状态）。
void composeMessageToUser({
  required BuildContext context,
  required String username,
  int? topicId,
  int? postNumber,
  String? topicTitle,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = container.read(preferencesProvider);
  final currentUsername = container.read(currentUserProvider).value?.username;

  String? body;
  if (topicId != null && postNumber != null) {
    body = ShareUtils.buildShareUrl(
      path: '/t/$topicId/$postNumber',
      username: currentUsername,
      anonymousShare: prefs.anonymousShare,
    );
  }
  // 标题优先用传入的 topicTitle，否则从话题会话状态读取（基于话题的私信预填「回复:标题」）
  final resolvedTitle =
      topicTitle ??
      (topicId != null
          ? container.read(topicSessionProvider(topicId)).topicTitle
          : null);
  final title = (resolvedTitle != null && resolvedTitle.isNotEmpty)
      ? S.current.userCard_referenceTopicTitle(resolvedTitle)
      : null;

  showReplySheet(
    context: context,
    targetUsername: username,
    initialContent: body,
    initialTitle: title,
  );
}

/// 头像长按：浮起头像 + v2 菜单（点按仍是原来的 [onTap]，通常打开用户卡片）。
class AvatarLongPressMenu extends StatelessWidget {
  const AvatarLongPressMenu({
    super.key,
    required this.onTap,
    required this.itemsBuilder,
    required this.child,
    this.liftedChild,
  });

  final VoidCallback onTap;
  final List<AppMenuItem<VoidCallback>> Function() itemsBuilder;
  final Widget child;

  /// 浮起时显示的头像；默认就是 [child]
  final Widget? liftedChild;

  @override
  Widget build(BuildContext context) {
    return LiftedContextMenu<VoidCallback>(
      sectionsBuilder: (_) => [itemsBuilder()],
      liftedBuilder: (_) => liftedChild ?? child,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// 构建头像长按菜单项（长按触发瞬间调用）。
///
/// - 进入主页 / 复制用户名：总是显示
/// - 私信：已登录且当前用户可发私信且非自己（目标用户级能力此时未知，
///   对方关闭私信时由发送阶段服务端报错 + ErrorInterceptor 兜底）
/// - @用户：[onMentionUser] 非 null（链路可回复）且非自己
/// - 只看此人：有话题上下文时显示(发帖数此时未知,不设官方 ≥2 帖门
///   槛;已在过滤该用户时变「取消只看」)
List<AppMenuItem<VoidCallback>> buildAvatarMenuItems(
  BuildContext context, {
  required String username,
  int? topicId,
  int? postNumber,
  String? topicTitle,
  void Function(String username)? onMentionUser,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final currentUser = container.read(currentUserProvider).value;
  final isSelf = currentUser != null && currentUser.username == username;
  final canMessage =
      currentUser != null &&
      currentUser.canSendPrivateMessages != false &&
      !isSelf;

  // 话题内过滤状态:决定「只看此人/取消只看」形态
  bool isFilteringThisUser = false;
  bool canFilter = false;
  if (topicId != null) {
    final params = TopicDetailNotifier.activeParamsFor(topicId);
    if (params != null && container.exists(topicDetailProvider(params))) {
      canFilter = true;
      isFilteringThisUser =
          container.read(topicDetailProvider(params).notifier).usernameFilter ==
          username;
    }
  }

  return [
    AppMenuItem(
      icon: AppIcons.person,
      label: S.current.avatarMenu_viewProfile,
      onTap: () => EmbeddedStackScope.openProfile(context, username),
    ),
    if (canMessage)
      AppMenuItem(
        icon: AppIcons.mail,
        label: S.current.userProfile_message,
        onTap: () => composeMessageToUser(
          context: context,
          username: username,
          topicId: topicId,
          postNumber: postNumber,
          topicTitle: topicTitle,
        ),
      ),
    if (onMentionUser != null && !isSelf)
      AppMenuItem(
        icon: AppIcons.mention,
        label: S.current.avatarMenu_mention,
        onTap: () => onMentionUser(username),
      ),
    if (canFilter)
      AppMenuItem(
        icon: isFilteringThisUser ? AppIcons.filterOff : AppIcons.filter,
        label: isFilteringThisUser
            ? S.current.avatarMenu_cancelFilterPosts
            : S.current.avatarMenu_filterPosts,
        onTap: () => container
            .read(topicUserFilterRequestProvider.notifier)
            .request(
              topicId: topicId!,
              username: isFilteringThisUser ? null : username,
            ),
      ),
    AppMenuItem(
      icon: AppIcons.copy,
      label: S.current.avatarMenu_copyUsername,
      onTap: () => copyUsernameToClipboard(username),
    ),
  ];
}
