import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_pressable.dart';
import 'badges.dart';

/// 头像行（通知、私信、用户结果）：pad 12 20，头像 34 + 12 + 正文列，
/// 顶对齐；标题 17 Semibold 最多两行，元信息 13 text/meta。未读点放在
/// 元信息行右端。行间分隔线左缩进 [separatorIndent]（20 + 34 + 12）。
///
/// 整行合并朗读；[readState] 放在最前面（通知行先读「未读」「已读」，
/// 设计说明 §1-7）。
class AvatarRow extends StatelessWidget {
  const AvatarRow({
    super.key,
    required this.avatar,
    required this.title,
    this.meta,
    this.trailing,
    this.unread = false,
    this.readState,
    this.onTap,
    this.onLongPress,
    this.titleMaxLines = 2,
  });

  /// 分隔线左缩进
  static const double separatorIndent =
      AppSpace.pageMargin + AppSize.avatarS + AppSpace.m;

  final Widget avatar;
  final Widget title;

  /// 元信息行（13 text/meta 的 DefaultTextStyle）
  final Widget? meta;

  /// 正文列右侧（如关注按钮）
  final Widget? trailing;

  final bool unread;

  /// 最先朗读的状态，如「未读」
  final String? readState;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final metaRow = meta == null && !unread
        ? null
        : Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: base
                      .merge(tokens.text.meta)
                      .copyWith(color: tokens.colors.textMeta),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: meta ?? const SizedBox.shrink(),
                ),
              ),
              if (unread) ...[
                const SizedBox(width: AppSpace.s),
                const UnreadDot(),
              ],
            ],
          );

    Widget row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.pageMargin,
        vertical: tokens.rowPadV,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: AppSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: base
                      .merge(tokens.text.headline)
                      .copyWith(color: tokens.colors.textPrimary),
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
                if (metaRow != null) ...[
                  const SizedBox(height: AppSpace.s),
                  metaRow,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.m),
            trailing!,
          ],
        ],
      ),
    );

    if (readState != null) {
      row = Semantics(label: readState, child: row);
    }
    return MergeSemantics(
      child: AppPressable(
        highlight: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: row,
      ),
    );
  }
}
