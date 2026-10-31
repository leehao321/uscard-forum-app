import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/topic.dart';
import '../../utils/time_utils.dart';

/// 列表行（0.4.0 v2，设计说明 §3.1「列表行」）：
///
/// pad 12 20，标题 17 Semibold / 24 最多 2 行；元信息行 13 meta 两端对齐：
/// 左「分类 · 作者 · 时间 [· N 条新回复]」，右 heart 14 + 赞数、
/// message-circle 14 + 回复数。行间 0.5 发丝线由列表画（缩进 20）。
///
/// 整行合并朗读，顺序：标题、分类、作者、时间、N 条新回复、N 赞、N 回复。
class TopicRow extends StatelessWidget {
  const TopicRow({
    super.key,
    required this.topic,
    required this.onTap,
    this.category,
    this.onLongPress,
    this.onMiddleClick,
    this.isSelected = false,
    this.highlightColor,
    this.showCounts = true,
  });

  final Topic topic;
  final Category? category;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 鼠标中键点击（桌面「后台开标签」）
  final VoidCallback? onMiddleClick;

  /// 桌面双栏里当前打开的话题
  final bool isSelected;

  /// 刚插入的新话题短暂高亮
  final Color? highlightColor;

  /// 私信等不显示赞 / 回复计数的列表传 false
  final bool showCounts;

  /// 「N 条新回复」：已读过的话题里还没读的帖子数
  static int newRepliesOf(Topic topic) {
    if (topic.unseen) return 0;
    final n = topic.unread + topic.newPosts;
    return n > 0 ? n : 0;
  }

  /// 作者 = 发起人（posters 里描述含 Original Poster 的那位，没有就取第一位）
  static String? authorOf(Topic topic) {
    if (topic.posters.isEmpty) return null;
    final op = topic.posters.firstWhere(
      (p) =>
          p.description.contains('Original Poster') ||
          p.description.contains('原始发帖'),
      orElse: () => topic.posters.first,
    );
    return op.user?.name?.trim().isNotEmpty == true
        ? op.user!.name
        : op.user?.username;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final metaStyle = base
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final newReplies = newRepliesOf(topic);
    final author = authorOf(topic);
    final time = TimeUtils.formatRelativeTime(
      topic.lastPostedAt ?? topic.createdAt,
    );
    final likes = topic.likeCount;
    final replies = topic.replyCount;

    final metaParts = <String>[
      if (category != null) category!.name,
      ?author,
      if (time.isNotEmpty) time,
    ];
    final newText = newReplies > 0
        ? context.l10n.topic_newRepliesCount(newReplies)
        : null;

    final semanticLabel = [
      topic.title,
      ...metaParts,
      ?newText,
      if (showCounts) ...[context.l10n.topic_likeCount('$likes'), '$replies'],
    ].join('，');

    Widget countItem(IconData icon, int n) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textMeta),
        const SizedBox(width: AppSpace.xs),
        Text('$n', style: metaStyle),
      ],
    );

    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.pageMargin,
        vertical: tokens.rowPadV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            topic.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: base
                .merge(tokens.text.headline)
                .copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpace.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: metaParts.join(' · ')),
                      if (newText != null)
                        TextSpan(
                          text: ' · $newText',
                          style: TextStyle(color: colors.brandPrimary),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
              if (showCounts) ...[
                const SizedBox(width: AppSpace.s),
                countItem(AppIcons.heart, likes),
                const SizedBox(width: AppSpace.s),
                countItem(AppIcons.chatBubble, replies),
              ],
            ],
          ),
        ],
      ),
    );

    Widget child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.topicRow),
      child: row,
    );
    if (highlightColor != null) {
      child = ColoredBox(color: highlightColor!, child: child);
    } else if (isSelected) {
      child = ColoredBox(color: colors.surfaceGrouped, child: child);
    }

    return MergeSemantics(
      child: Listener(
        onPointerDown: onMiddleClick == null
            ? null
            : (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons == kMiddleMouseButton) {
                  onMiddleClick!();
                }
              },
        child: Semantics(
          label: semanticLabel,
          button: true,
          selected: isSelected ? true : null,
          child: ExcludeSemantics(
            child: AppPressable(
              highlight: true,
              onTap: onTap,
              onLongPress: onLongPress,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 置顶折叠行（设计说明 §3.1）：视觉 36 + 上下各 4 透明热区；
/// pin 13 +「置顶 · 标题」13 meta，单行省略。
class PinnedTopicRow extends StatelessWidget {
  const PinnedTopicRow({
    super.key,
    required this.topic,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  final Topic topic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final style = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final label = '${context.l10n.topic_pinnedLabel} · ${topic.title}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppPressable(
        highlight: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.hit),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.pageMargin,
            ),
            child: Row(
              children: [
                Icon(AppIcons.pushPin, size: 13, color: colors.textMeta),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
