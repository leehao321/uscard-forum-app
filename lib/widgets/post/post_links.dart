import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../providers/selected_topic_provider.dart';
import '../../utils/discourse_url_parser.dart';

/// 帖子相关链接组件
///
/// 显示其他帖子引用当前帖子的入站链接（reflection links）。
/// 默认折叠成一行（补充稿 09），点击展开成列表（补充稿 10），
/// 列表下方的「收起」收回。
class PostLinks extends StatefulWidget {
  final List<LinkCount>? linkCounts;
  final bool defaultExpanded;

  /// 最大折叠显示数量
  static const int maxCollapsedLinks = 5;

  const PostLinks({super.key, this.linkCounts, this.defaultExpanded = false});

  /// 链接的站点名：取 host，去掉前导 www.
  static String hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  State<PostLinks> createState() => _PostLinksState();
}

class _PostLinksState extends State<PostLinks> {
  late bool _expanded = widget.defaultExpanded;
  bool _showAll = false; // 链接列表内部的"查看更多"

  /// 获取内部入站链接（reflection links）
  List<LinkCount> get _internalLinks {
    if (widget.linkCounts == null) return [];

    // 过滤：内部链接 + reflection + 有标题
    final filtered = widget.linkCounts!
        .where(
          (l) =>
              l.internal &&
              l.reflection &&
              l.title != null &&
              l.title!.isNotEmpty,
        )
        .toList();

    // 按标题去重
    final seen = <String>{};
    final unique = <LinkCount>[];
    for (final link in filtered) {
      if (!seen.contains(link.title)) {
        seen.add(link.title!);
        unique.add(link);
      }
    }

    return unique;
  }

  List<LinkCount> get _displayedLinks {
    final links = _internalLinks;
    if (_showAll || links.length <= PostLinks.maxCollapsedLinks) {
      return links;
    }
    return links.take(PostLinks.maxCollapsedLinks).toList();
  }

  bool get _canShowMore {
    return _internalLinks.length > PostLinks.maxCollapsedLinks && !_showAll;
  }

  int get _remainingCount {
    return _internalLinks.length - PostLinks.maxCollapsedLinks;
  }

  /// 处理链接点击:平行视界面板内压当前栈(与正文内链同语义),
  /// 全屏页照旧 push。
  void _onLinkTap(LinkCount link) {
    final topicInfo = DiscourseUrlParser.parseTopic(link.url);
    if (topicInfo != null) {
      if (EmbeddedStackScope.maybePushTopic(
        context,
        topicId: topicInfo.topicId,
        initialTitle: link.title,
      )) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TopicDetailPage(
            topicId: topicInfo.topicId,
            initialTitle: link.title,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_internalLinks.isEmpty) return const SizedBox.shrink();
    return _expanded ? _buildExpanded(context) : _buildCollapsed(context);
  }

  /// 折叠态：一整行（48 高、r12、surface/grouped），整行可点
  Widget _buildCollapsed(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s),
      child: Semantics(
        button: true,
        expanded: false,
        label: context.l10n.post_relatedLinks,
        child: ExcludeSemantics(
          child: Material(
            color: colors.surfaceGrouped,
            borderRadius: BorderRadius.circular(tokens.radius.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('related_links_toggle'),
              onTap: () => setState(() => _expanded = true),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.row48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.link,
                        size: AppSize.iconM,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: AppSpace.m),
                      Expanded(
                        child: Text(
                          context.l10n.post_relatedLinks,
                          style: theme.textTheme.bodyMedium!
                              .merge(tokens.text.control)
                              .copyWith(color: colors.textPrimary),
                        ),
                      ),
                      Icon(
                        AppIcons.chevronRight,
                        size: AppSize.iconS,
                        color: colors.textMeta,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 展开态：小标题 + 分组卡片（每行 标题 + 站点 + 外跳箭头）+ 右下「收起」
  Widget _buildExpanded(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final brandMeta = metaStyle.copyWith(color: colors.brandPrimary);
    final links = _displayedLinks;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s),
            child: Text(context.l10n.post_relatedLinks, style: metaStyle),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < links.length; i++) ...[
                  if (i > 0)
                    const AppHairline(
                      indent: AppSpace.m + AppSize.iconM + AppSpace.m,
                    ),
                  _buildLinkItem(links[i], context),
                ],
                if (_canShowMore) ...[
                  const AppHairline(),
                  InkWell(
                    onTap: () => setState(() => _showAll = true),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppSize.hit),
                      child: Center(
                        child: Text(
                          context.l10n.post_moreLinks(_remainingCount),
                          style: brandMeta,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              key: const ValueKey('related_links_collapse'),
              onTap: () => setState(() => _expanded = false),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.hit),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.l10n.post_collapse, style: brandMeta),
                    const SizedBox(width: AppSpace.xs),
                    Icon(
                      AppIcons.chevronUp,
                      size: AppSize.iconS,
                      color: colors.brandPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkItem(LinkCount link, BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final host = PostLinks.hostOf(link.url);
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    return InkWell(
      onTap: () => _onLinkTap(link),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m,
            vertical: AppSpace.s,
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.link,
                size: AppSize.iconM,
                color: colors.textPrimary,
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title ?? link.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium!
                          .merge(tokens.text.control)
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (host.isNotEmpty)
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                  ],
                ),
              ),
              if (link.clicks > 0) ...[
                const SizedBox(width: AppSpace.s),
                Text(_formatClicks(link.clicks), style: metaStyle),
              ],
              const SizedBox(width: AppSpace.s),
              Icon(
                AppIcons.arrowUpRight,
                size: AppSize.iconM,
                color: colors.textMeta,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化点击数
  String _formatClicks(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }
}
