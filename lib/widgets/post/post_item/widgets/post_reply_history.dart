import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';

import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../utils/fluxdo_render_callbacks.dart';

/// 「回复给」内联预览（补充稿 13 / 14）
///
/// 点楼层顶部的「回复给」入口后，在楼内展开：先一行
/// 「↩ 回复给 某人 …… 收起」，下面是被回复楼层的引用块（3pt 左竖线、
/// 「作者 · #楼层」13、正文 17）。内容还没到达时（[replyHistory] 为空）
/// 引用块的位置先放加载指示，内容到达后替换。
class PostReplyHistory extends StatelessWidget {
  /// 被回复楼层；null 表示还在加载
  final List<Post>? replyHistory;

  /// 「回复给」后面的名字
  final String replyToName;

  /// 点「收起」
  final VoidCallback onCollapse;
  final void Function(int postNumber)? onJumpToPost;
  final double contentFontScale;

  const PostReplyHistory({
    super.key,
    required this.replyHistory,
    required this.replyToName,
    required this.onCollapse,
    this.onJumpToPost,
    this.contentFontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final history = replyHistory;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.hit),
            child: Row(
              children: [
                Icon(AppIcons.reply, size: AppSize.iconS, color: colors.textMeta),
                const SizedBox(width: AppSpace.s),
                Expanded(
                  child: Text(
                    '${context.l10n.post_replyTo} $replyToName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle,
                  ),
                ),
                InkWell(
                  key: const ValueKey('reply_history_collapse'),
                  onTap: onCollapse,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSize.hit,
                      minWidth: AppSize.hit,
                    ),
                    child: Center(
                      child: Text(
                        context.l10n.post_collapse,
                        style: metaStyle.copyWith(color: colors.brandPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (history == null)
            LoadingHint(
              key: const ValueKey('reply_history_loading'),
              label: context.l10n.common_loadingLabel,
              filled: true,
            )
          else
            for (final post in history) ...[
              _ReplyQuote(
                post: post,
                contentFontScale: contentFontScale,
                onTap: () => onJumpToPost?.call(post.postNumber),
              ),
              const SizedBox(height: AppSpace.s),
            ],
        ],
      ),
    );
  }
}

/// 一条被回复楼层的引用块：3pt 左竖线 + 「作者 · #楼层」+ 正文
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.post,
    required this.contentFontScale,
    required this.onTap,
  });

  final Post post;
  final double contentFontScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final name = (post.name != null && post.name!.isNotEmpty)
        ? post.name!
        : post.username;
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: colors.quoteRule),
            const SizedBox(width: AppSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$name · '),
                        TextSpan(
                          text: '#${post.postNumber}',
                          style: TextStyle(color: colors.brandPrimary),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  IgnorePointer(
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppFixedColors.black, Colors.transparent],
                          stops: [0.6, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 72),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          // 回复历史预览:改用自研 FluxdoRender 只读渲染(关闭选区)
                          child:
                              FluxdoRenderCallbacks.generic(
                                heroTagNamespace:
                                    'reply_history_${post.postNumber}',
                              ).render(
                                cookedHtml: post.cooked,
                                baseTextStyle: theme.textTheme.bodyMedium!
                                    .merge(tokens.text.body)
                                    .copyWith(
                                      fontSize:
                                          AppFontSize.body * contentFontScale,
                                      color: colors.textMeta,
                                    ),
                                compact: true,
                                selectionEnabled: false,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
