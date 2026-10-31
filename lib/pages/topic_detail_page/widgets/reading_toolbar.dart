import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/s.dart';

/// 阅读页底部工具栏（0.4.0 v2，设计说明 §2.6 / §3.2「底部工具栏」）。
///
/// - 展开：64 + 底部安全区；左边「回复」(92×48 主按钮) + bell / bookmark / share
///   各 24（热区 44），右边楼层按钮 128×48（avatar/fill，arrow-up-down 16 +
///   「n」13 +「/ N」13 meta），点开楼层跳转半屏；
/// - 收起：44 + 安全区，中间一颗 32 高楼层胶囊，整条 44 可点；
/// - 不放点赞；回复、bell、bookmark 只对已登录用户显示。
///
/// 底色铺满整宽（工具栏材质 + 顶部发丝线），控件按阅读列对齐。展开 / 收起
/// 由滚动方向驱动（[expandedListenable]），楼层号来自 [floorListenable]
/// （滚动中高频变化，只重建楼层按钮）。
class ReadingToolbar extends StatelessWidget {
  const ReadingToolbar({
    super.key,
    required this.expandedListenable,
    required this.floorListenable,
    required this.total,
    required this.isLoggedIn,
    required this.bookmarked,
    required this.notificationIcon,
    required this.onReply,
    required this.onNotification,
    required this.onBookmark,
    required this.onShare,
    required this.onOpenFloorJump,
    this.showShare = true,
  });

  /// true = 展开（64），false = 收起（44）
  final ValueListenable<bool> expandedListenable;

  /// 当前楼层（流中序号，从 1 起）
  final ValueListenable<int> floorListenable;

  /// 最高楼层
  final int total;

  final bool isLoggedIn;
  final bool bookmarked;
  final IconData notificationIcon;
  final VoidCallback onReply;
  final VoidCallback onNotification;
  final VoidCallback onBookmark;
  final VoidCallback onShare;
  final VoidCallback onOpenFloorJump;

  /// 私信不能分享链接
  final bool showShare;

  static const double expandedHeight = 64;
  static const double collapsedHeight = AppSize.toolbarCollapsed;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: expandedListenable,
      builder: (context, expanded, _) {
        final body = AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
          child: expanded
              ? _Expanded(
                  key: const ValueKey('reading-toolbar-expanded'),
                  floorListenable: floorListenable,
                  total: total,
                  isLoggedIn: isLoggedIn,
                  bookmarked: bookmarked,
                  notificationIcon: notificationIcon,
                  onReply: onReply,
                  onNotification: onNotification,
                  onBookmark: onBookmark,
                  onShare: onShare,
                  onOpenFloorJump: onOpenFloorJump,
                  showShare: showShare,
                )
              : _Collapsed(
                  key: const ValueKey('reading-toolbar-collapsed'),
                  floorListenable: floorListenable,
                  total: total,
                  onOpenFloorJump: onOpenFloorJump,
                ),
        );
        return AnimatedSize(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: BarSurface(
            edge: BarEdge.top,
            child: Padding(
              padding: EdgeInsets.only(bottom: safeBottom),
              child: SizedBox(
                height: expanded ? expandedHeight : collapsedHeight,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: kChromeMaxTextScale,
                  child: body,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Expanded extends StatelessWidget {
  const _Expanded({
    super.key,
    required this.floorListenable,
    required this.total,
    required this.isLoggedIn,
    required this.bookmarked,
    required this.notificationIcon,
    required this.onReply,
    required this.onNotification,
    required this.onBookmark,
    required this.onShare,
    required this.onOpenFloorJump,
    required this.showShare,
  });

  final ValueListenable<int> floorListenable;
  final int total;
  final bool isLoggedIn;
  final bool bookmarked;
  final IconData notificationIcon;
  final VoidCallback onReply;
  final VoidCallback onNotification;
  final VoidCallback onBookmark;
  final VoidCallback onShare;
  final VoidCallback onOpenFloorJump;
  final bool showShare;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final insets = readableInsets(context, gutter: 0);
    // 视觉边在页边距 20，44 热区向外多出 10
    const overhang = (AppSize.hit - AppSize.iconL) / 2;

    return Padding(
      padding: EdgeInsets.only(
        left: insets.left + AppSpace.pageMargin,
        right: insets.right + AppSpace.pageMargin,
      ),
      child: Row(
        children: [
          if (isLoggedIn) ...[
            FilledButton.icon(
              style: AppButtonStyles.large.merge(
                FilledButton.styleFrom(
                  minimumSize: const Size(92, AppSize.replyButton),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.l),
                ),
              ),
              onPressed: onReply,
              icon: const Icon(AppIcons.reply, size: 18),
              label: Text(l10n.common_reply),
            ),
            const SizedBox(width: AppSpace.xxl - 2 * overhang),
            AppIconButton(
              icon: notificationIcon,
              semanticLabel: l10n.topic_notificationSettings,
              onPressed: onNotification,
            ),
            const SizedBox(width: AppSpace.xxl - 2 * overhang),
            AppIconButton(
              icon: AppIcons.bookmark,
              semanticLabel: bookmarked
                  ? l10n.topicDetail_editBookmark
                  : l10n.common_addBookmark,
              selected: bookmarked,
              color: bookmarked ? colors.brandPrimary : null,
              onPressed: onBookmark,
            ),
            if (showShare) const SizedBox(width: AppSpace.xxl - 2 * overhang),
          ],
          if (showShare)
            AppIconButton(
              icon: AppIcons.share,
              semanticLabel: l10n.topicDetail_shareLink,
              onPressed: onShare,
            ),
          const Spacer(),
          // 窄屏（393）左侧四个控件占满后，楼层按钮可以收窄，不能溢出
          Flexible(
            child: ValueListenableBuilder<int>(
              valueListenable: floorListenable,
              builder: (context, floor, _) => Semantics(
                button: true,
                label: l10n.topic_floorButton(floor, total),
                excludeSemantics: true,
                onTap: onOpenFloorJump,
                child: AppPressable(
                  onTap: onOpenFloorJump,
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: AppSize.floorButtonWidth,
                    ),
                    width: AppSize.floorButtonWidth,
                    height: AppSize.floorButtonHeight,
                    decoration: ShapeDecoration(
                      color: colors.avatarFill,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          AppIcons.floor,
                          size: AppSize.iconS,
                          color: colors.textPrimary,
                        ),
                        const SizedBox(width: AppSpace.s),
                        Text(
                          '$floor',
                          style: base
                              .merge(tokens.text.meta)
                              .copyWith(color: colors.textPrimary),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Flexible(
                          child: Text(
                            '/ $total',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: base
                                .merge(tokens.text.meta)
                                .copyWith(color: colors.textMeta),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  const _Collapsed({
    super.key,
    required this.floorListenable,
    required this.total,
    required this.onOpenFloorJump,
  });

  final ValueListenable<int> floorListenable;
  final int total;
  final VoidCallback onOpenFloorJump;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return ValueListenableBuilder<int>(
      valueListenable: floorListenable,
      builder: (context, floor, _) => Semantics(
        button: true,
        label: context.l10n.topic_floorButton(floor, total),
        excludeSemantics: true,
        onTap: onOpenFloorJump,
        child: AppPressable(
          onTap: onOpenFloorJump,
          // 整条 44 都可点
          child: SizedBox(
            height: collapsedHeightOf,
            child: Center(
              child: Container(
                height: AppSize.floorPill,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                decoration: ShapeDecoration(
                  color: colors.surfaceGrouped,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.floor,
                      size: AppSize.iconS,
                      color: colors.textPrimary,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '$floor / $total',
                      style: base
                          .merge(tokens.text.meta)
                          .copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get collapsedHeightOf => ReadingToolbar.collapsedHeight;
}
