import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';

import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../utils/fluxdo_render_callbacks.dart';
import '../../../../utils/time_utils.dart';
import '../../../common/smart_avatar.dart';

/// 回复列表组件（补充稿 12）
///
/// 点楼层的回复入口后在楼下展开：surface/grouped 圆角卡片，每条回复
/// 「头像 34 + 名字 13 Semibold / @handle · 时间 11 meta」加 17 正文，
/// 条间 0.5 发丝线；卡片下方左侧「收起回复」，有更多时右侧「加载更多」。
class PostRepliesList extends StatelessWidget {
  final List<Post> replies;
  final int replyCount;
  final bool canLoadMore;
  final ValueNotifier<bool> isLoadingRepliesNotifier;
  final ValueNotifier<bool> showRepliesNotifier;
  final VoidCallback onLoadMore;
  final void Function(int postNumber)? onJumpToPost;
  final double contentFontScale;

  const PostRepliesList({
    super.key,
    required this.replies,
    required this.replyCount,
    required this.canLoadMore,
    required this.isLoadingRepliesNotifier,
    required this.showRepliesNotifier,
    required this.onLoadMore,
    this.onJumpToPost,
    this.contentFontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final actionStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.brandPrimary);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 已加载的回复列表：一张分组卡片，条间发丝线
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < replies.length; i++) ...[
                  if (i > 0)
                    const AppHairline(indent: AppSpace.m, endIndent: AppSpace.m),
                  _ReplyRow(
                    reply: replies[i],
                    contentFontScale: contentFontScale,
                    onTap: () => onJumpToPost?.call(replies[i].postNumber),
                  ),
                ],
              ],
            ),
          ),

          // 底部操作栏：左「收起回复」，右「加载更多」
          ValueListenableBuilder<bool>(
            valueListenable: isLoadingRepliesNotifier,
            builder: (context, isLoadingReplies, _) {
              return Row(
                children: [
                  InkWell(
                    key: const ValueKey('replies_collapse'),
                    onTap: () => showRepliesNotifier.value = false,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppSize.hit),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.expandLess,
                            size: AppSize.iconS,
                            color: colors.brandPrimary,
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Text(
                            context.l10n.post_collapseReplies,
                            style: actionStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (canLoadMore)
                    InkWell(
                      key: const ValueKey('replies_load_more'),
                      onTap: isLoadingReplies ? null : onLoadMore,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSize.hit,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLoadingReplies) ...[
                              const CupertinoActivityIndicator(
                                radius: AppSize.iconS / 2,
                              ),
                              const SizedBox(width: AppSpace.xs),
                            ],
                            Text(
                              context.l10n.post_loadMoreReplies,
                              style: actionStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 回复列表里的一行：头像 + 名字 / @handle · 时间 + 正文
class _ReplyRow extends StatelessWidget {
  const _ReplyRow({
    required this.reply,
    required this.contentFontScale,
    required this.onTap,
  });

  final Post reply;
  final double contentFontScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final avatarUrl = reply.getAvatarUrl(size: 60);
    final displayName = (reply.name != null && reply.name!.isNotEmpty)
        ? reply.name!
        : reply.username;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SmartAvatar(
                  imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                  radius: AppSize.avatarS / 2,
                  backgroundColor: colors.avatarFill,
                  fallbackText: reply.username,
                ),
                const SizedBox(width: AppSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!
                            .merge(tokens.text.metaStrong)
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpace.xxs),
                      Text(
                        '@${reply.username} · '
                        '${TimeUtils.formatRelativeTime(reply.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall!
                            .merge(tokens.text.caption)
                            .copyWith(color: colors.textMeta),
                      ),
                    ],
                  ),
                ),
                Text(
                  '#${reply.postNumber}',
                  style: theme.textTheme.bodySmall!
                      .merge(tokens.text.meta)
                      .copyWith(color: colors.textMeta),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s),
            IgnorePointer(
              // 回复预览:改用自研 FluxdoRender 只读渲染(关闭选区)
              child:
                  FluxdoRenderCallbacks.generic(
                    heroTagNamespace: 'reply_preview_${reply.postNumber}',
                  ).render(
                    cookedHtml: reply.cooked,
                    baseTextStyle: theme.textTheme.bodyMedium!
                        .merge(tokens.text.body)
                        .copyWith(
                          fontSize: AppFontSize.body * contentFontScale,
                          color: colors.textPrimary,
                        ),
                    compact: true,
                    selectionEnabled: false,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
