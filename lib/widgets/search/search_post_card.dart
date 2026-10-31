import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/search_result.dart';
import '../../providers/category_provider.dart';
import '../../utils/number_utils.dart';
import '../../utils/responsive.dart';
import '../common/relative_time_text.dart';

/// 搜索卡排版宽：页边 20×2，桌面同口径再封顶 maxContentWidth。
double searchCardWidthFor(BuildContext context) {
  final viewportWidth = MediaQuery.sizeOf(context).width - 2 * AppSpace.pageMargin;
  if (Responsive.isMobile(context)) return viewportWidth;
  return viewportWidth > Breakpoints.maxContentWidth
      ? Breakpoints.maxContentWidth
      : viewportWidth;
}

/// 搜索结果列表的外层（v2 起结果行不再走自绘排版缓存，不需要预热，
/// 保留这个壳是为了调用方不变）。
class SearchPostPrewarmScope extends StatelessWidget {
  const SearchPostPrewarmScope({
    super.key,
    required this.posts,
    required this.child,
  });

  final List<SearchPost> posts;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 搜索结果行（设计说明 §5.1「搜索 · 结果与筛选」）：
/// 列表行 + 摘要。标题 17 Semibold 最多 2 行；元信息 13 meta（作者 · 分类 · 时间 ·
/// 回复 · 点赞）；摘要 13 meta 最多 2 行，楼层 > 1 时前缀「#12」；命中词用
/// brand/primary，不加底色。行间分隔线左缩进 20。
class SearchPostCard extends StatelessWidget {
  const SearchPostCard({
    super.key,
    required this.post,
    this.onTap,
    this.enableLongPress = false,
  });

  final SearchPost post;
  final VoidCallback? onTap;

  /// 长按浮起整行并弹出「打开」菜单（v2 取代旧的预览弹窗）
  final bool enableLongPress;

  @override
  Widget build(BuildContext context) {
    Widget card = _SearchPostRow(post: post, onTap: onTap);
    if (enableLongPress && onTap != null) {
      card = LiftedContextMenu<int>(
        sectionsBuilder: (_) => [
          [
            AppMenuItem(
              label: context.l10n.topic_rowOpen,
              icon: AppIcons.article,
              value: 0,
            ),
          ],
        ],
        liftedBuilder: (_) => _SearchPostRow(post: post),
        onSelected: (_) => onTap!(),
        child: card,
      );
    }
    if (!Responsive.isMobile(context)) {
      card = Center(
        child: SizedBox(width: searchCardWidthFor(context) + 2 * AppSpace.pageMargin, child: card),
      );
    }
    return card;
  }
}

final RegExp _highlightPattern = RegExp(r'<span class="search-highlight">(.*?)</span>');
final RegExp _tagPattern = RegExp(r'<[^>]*>');

/// 把带 `<span class="search-highlight">` 的片段拆成 TextSpan：命中词只变色
List<InlineSpan> _highlightSpans(String html, Color highlight) {
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in _highlightPattern.allMatches(html)) {
    if (match.start > lastEnd) {
      spans.add(
        TextSpan(
          text: html.substring(lastEnd, match.start).replaceAll(_tagPattern, ''),
        ),
      );
    }
    spans.add(
      TextSpan(
        text: match.group(1) ?? '',
        style: TextStyle(color: highlight),
      ),
    );
    lastEnd = match.end;
  }
  if (lastEnd < html.length) {
    spans.add(
      TextSpan(text: html.substring(lastEnd).replaceAll(_tagPattern, '')),
    );
  }
  return spans;
}

class _SearchPostRow extends ConsumerWidget {
  final SearchPost post;
  final VoidCallback? onTap;

  const _SearchPostRow({required this.post, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final topic = post.topic;
    final base = theme.textTheme.bodyMedium!;

    final categoryMap = ref.watch(categoryMapProvider).value;
    final categoryId = topic?.categoryId;
    Category? category;
    if (categoryId != null && categoryMap != null) {
      category = categoryMap[categoryId];
    }

    final titleStyle = base
        .merge(tokens.text.headline)
        .copyWith(color: colors.textPrimary);
    final metaStyle = base
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    final titleSpans = <InlineSpan>[
      if (topic != null && topic.closed)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs),
            child: Icon(AppIcons.lock, size: AppSize.iconS, color: colors.textMeta),
          ),
        ),
      if (topic != null && topic.archived)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs),
            child: Icon(AppIcons.archive, size: AppSize.iconS, color: colors.textMeta),
          ),
        ),
      if (post.topicTitleHeadline != null &&
          post.topicTitleHeadline!.isNotEmpty)
        ..._highlightSpans(post.topicTitleHeadline!, colors.brandPrimary)
      else if (topic != null)
        TextSpan(text: topic.title),
    ];

    final replies = topic != null ? (topic.postsCount - 1).clamp(0, 999999) : 0;
    final metaItems = <String>[
      post.username,
      if (category != null) category.name,
    ];

    final blurbSpans = post.blurb.isEmpty
        ? const <InlineSpan>[]
        : _highlightSpans(post.blurb, colors.brandPrimary);

    return AppPressable(
      highlight: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.pageMargin,
              vertical: tokens.rowPadV,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(style: titleStyle, children: titleSpans),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (post.isAiGenerated) ...[
                      const SizedBox(width: AppSpace.s),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xs),
                        child: Icon(
                          AppIcons.autoAwesome,
                          size: AppSize.iconS,
                          color: colors.brandPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpace.s),
                DefaultTextStyle(
                  style: metaStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Row(
                    children: [
                      Flexible(child: Text(metaItems.join(' · '))),
                      const Text(' · '),
                      RelativeTimeText(dateTime: post.createdAt, style: metaStyle),
                      if (replies > 0) ...[
                        const SizedBox(width: AppSpace.m),
                        Icon(AppIcons.chatBubble, size: 14, color: colors.textMeta),
                        const SizedBox(width: AppSpace.xs),
                        Text(NumberUtils.formatCount(replies)),
                      ],
                      if (post.likeCount > 0) ...[
                        const SizedBox(width: AppSpace.m),
                        Icon(AppIcons.heart, size: 14, color: colors.textMeta),
                        const SizedBox(width: AppSpace.xs),
                        Text(NumberUtils.formatCount(post.likeCount)),
                      ],
                    ],
                  ),
                ),
                if (blurbSpans.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s),
                  Text.rich(
                    TextSpan(
                      style: metaStyle,
                      children: [
                        if (post.postNumber > 1)
                          TextSpan(text: '#${post.postNumber} '),
                        ...blurbSpans,
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const AppHairline(indent: AppSpace.pageMargin),
        ],
      ),
    );
  }
}
