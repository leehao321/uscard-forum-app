import 'dart:async';

import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../providers/discourse_providers.dart';
import '../../../utils/font_awesome_helper.dart';
import '../../../widgets/topic/topic_summary_widget.dart';
import '../../../widgets/common/emoji_text.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/common/relative_time_text.dart';
import '../../../utils/number_utils.dart';
import '../../../widgets/topic/topic_notification_button.dart';
import '../../../widgets/layout/home_workspace_scope.dart';
import 'topic_vote_button.dart';
import '../../category_topics_page.dart';
import '../../tag_topics_page.dart';
import '../../../widgets/topic/assign_sheet.dart';

/// 话题详情页头部组件
class TopicDetailHeader extends ConsumerWidget {
  final TopicDetail detail;
  final GlobalKey? headerKey;
  final void Function(int, bool)? onVoteChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final bool showTitle;

  /// 跳转到当前话题的指定帖子
  final void Function(int postNumber)? onJumpToPost;

  const TopicDetailHeader({
    super.key,
    required this.detail,
    this.headerKey,
    this.onVoteChanged,
    this.onNotificationLevelChanged,
    this.showTitle = true,
    this.onJumpToPost,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // 获取分类信息
    final categoryMap = ref.watch(categoryMapProvider).value;
    final category = categoryMap?[detail.categoryId];

    FaIconData? faIcon;
    String? logoUrl;

    if (category != null) {
      faIcon = FontAwesomeHelper.getIcon(category.icon);
      logoUrl = category.uploadedLogo;

      if (faIcon == null &&
          (logoUrl == null || logoUrl.isEmpty) &&
          category.parentCategoryId != null) {
        final parent = categoryMap?[category.parentCategoryId];
        faIcon = FontAwesomeHelper.getIcon(parent?.icon);
        logoUrl = parent?.uploadedLogo;
      }
    }

    final tokens = context.tokens;
    final colors = tokens.colors;
    final metaStyle = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    Widget metaLink(String text, VoidCallback onTap, {bool brand = false}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            text,
            style: brand ? metaStyle.copyWith(color: colors.brandPrimary) : metaStyle,
          ),
        );

    final tags = detail.tags ?? const [];
    final showCategoryRow =
        !detail.isPrivateMessage && (category != null || tags.isNotEmpty);

    // v2 主题头（设计说明 §3.2）：pad 8 20 12，间距 8；标题 22 Semibold；
    // 元信息 13 meta：「分类 #标签」、回复数、浏览数、日期
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        showTitle ? AppSpace.s : AppSpace.xs,
        AppSpace.pageMargin,
        AppSpace.m,
      ),
      decoration: BoxDecoration(
        color: colors.surfacePage,
        border: Border(
          bottom: BorderSide(color: colors.separator, width: AppSpace.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Semantics(
              header: true,
              child: SelectableText.rich(
                TextSpan(
                  style: theme.textTheme.titleLarge
                      ?.merge(tokens.text.title)
                      .copyWith(color: colors.textPrimary),
                  children: [
                    if (detail.isPrivateMessage)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpace.s),
                          child: Icon(
                            AppIcons.mail,
                            size: AppSize.iconM,
                            color: colors.brandPrimary,
                          ),
                        ),
                      ),
                    if (detail.closed)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpace.s),
                          child: Icon(
                            AppIcons.lock,
                            size: AppSize.iconM,
                            color: colors.textMeta,
                          ),
                        ),
                      ),
                    if (detail.hasAcceptedAnswer)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpace.s),
                          child: Icon(
                            AppIcons.checkCircle,
                            size: AppSize.iconM,
                            color: colors.brandPrimary,
                          ),
                        ),
                      ),
                    ...EmojiText.buildEmojiSpans(
                      context,
                      detail.title,
                      theme.textTheme.titleLarge
                          ?.merge(tokens.text.title)
                          .copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
                key: headerKey,
              ),
            )
          else
            SizedBox(key: headerKey),

          SizedBox(height: showTitle ? AppSpace.s : AppSpace.xs),

          // 分类与标签（私信话题不显示）：纯文字一行，可点
          if (showCategoryRow) ...[
            Wrap(
              spacing: AppSpace.m,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (category != null)
                  metaLink(category.name, () {
                    final workspace = HomeWorkspaceScope.maybeOf(context);
                    if (workspace != null) {
                      workspace.onShowCategory(category);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryTopicsPage(category: category),
                      ),
                    );
                  }, brand: true),
                for (final tag in tags)
                  metaLink('#${tag.name}', () {
                    final workspace = HomeWorkspaceScope.maybeOf(context);
                    if (workspace != null) {
                      workspace.onShowTag(tag.name);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TagTopicsPage(tagName: tag.name),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: AppSpace.s),
          ],

          // 指定(discourse-assign)标识:有指定对象才显示,点开直接跳到
          // 指定弹窗——之前只在"更多"菜单的文字里标了状态,标题区域完全
          // 看不出来,指定完等于白指定。
          if (detail.isAssigned) ...[
            AppPressable(
              onTap: () => unawaited(
                showAssignSheet(context, ref, topicId: detail.id),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.m,
                  vertical: AppSpace.xs,
                ),
                decoration: ShapeDecoration(
                  color: colors.surfaceGrouped,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.assign,
                      size: AppSize.iconS,
                      color: colors.brandPrimary,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '已指定给 '
                      '${detail.assignedToUser?.displayName ?? detail.assignedToGroupName ?? ''}',
                      style: metaStyle.copyWith(color: colors.brandPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s),
          ],

          // 元信息行：回复数、浏览数、日期，右侧投票按钮
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpace.m,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildMetadataItem(
                      context,
                      AppIcons.chatBubble,
                      '${detail.postsCount - 1}',
                      label: context.l10n.topicDetail_replyLabel,
                    ),
                    _buildMetadataItem(
                      context,
                      AppIcons.visibility,
                      NumberUtils.formatCount(detail.views),
                      label: context.l10n.topicDetail_viewsLabel,
                    ),
                    Tooltip(
                      message: TimeUtils.formatTooltipTime(detail.createdAt),
                      child: RelativeTimeText(
                        dateTime: detail.createdAt,
                        style: metaStyle,
                      ),
                    ),
                  ],
                ),
              ),
              // 投票按钮
              TopicVoteButton(topic: detail, onVoteChanged: onVoteChanged),
            ],
          ),

          // AI 摘要 & 订阅按钮（卡片内容 M5 再换皮）
          const SizedBox(height: AppSpace.m),
          CollapsibleTopicSummary(
            topicId: detail.id,
            topicDetail: detail,
            onJumpToPost: onJumpToPost,
            headerExtra: TopicNotificationButton(
              level: detail.notificationLevel,
              onChanged: onNotificationLevelChanged,
              style: TopicNotificationButtonStyle.chip,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataItem(
    BuildContext context,
    IconData icon,
    String text, {
    String? label,
  }) {
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    // 图标 14 + 数字；标签只给读屏用（「12 回复」），视觉上不再显示
    return Semantics(
      label: label == null ? text : '$text $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tokens.colors.textMeta),
          const SizedBox(width: AppSpace.xs),
          Text(text, style: style),
        ],
      ),
    );
  }
}
