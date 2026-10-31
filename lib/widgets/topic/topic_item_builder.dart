import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../models/topic.dart';

import '../../utils/responsive.dart';
import 'preview_action.dart';
import 'topic_row.dart';

/// 话题卡排版宽:与 [buildTopicItem] 的壳层约束同源(移动 = 视口宽
/// - 页边距 24;桌面 = 同口径再封顶 [Breakpoints.maxContentWidth])。
/// 预热层([TopicCardPrewarmer])必须用同一口径取宽,否则挂载帧
/// ensureWidth 纠偏重排,预热白做。
double topicCardWidthFor(BuildContext context) {
  final viewportWidth = MediaQuery.sizeOf(context).width - 24;
  if (Responsive.isMobile(context)) return viewportWidth;
  return viewportWidth > Breakpoints.maxContentWidth
      ? Breakpoints.maxContentWidth
      : viewportWidth;
}

/// 话题卡片渲染公共函数
///
/// 处理 pinned/normal 卡片选择、自绘/widget 路由、长按预览、响应式
/// 宽度包装。普通/私信话题卡默认走自绘(单渲染对象,挂载帧纯绘制,
/// 见 [TopicCardLayout]);带自定义 topWidget/middleWidget 的调用方
/// (书签有专用自绘接线)与置顶卡走 widget 版。
Widget buildTopicItem({
  required BuildContext context,
  required Topic topic,
  required bool isSelected,
  required VoidCallback onTap,
  VoidCallback? onMiddleClick,
  required bool enableLongPress,
  Color? highlightColor,
  Widget? topWidget,
  Widget? middleWidget,
  bool showUnreadDot = false,
  bool messageStyle = false,
  Map<int, Category>? categoryMap,
  double? statsAvailableWidth,
  List<PreviewAction>? previewActions,
  WidgetBuilder? previewCustomActionPanelBuilder,
}) {
  // 0.4.0 v2：所有话题列表统一画 [TopicRow]（置顶折成单行），长按浮起上下文
  // 菜单取代旧的预览弹窗；书签等带附加内容的调用方通过 topWidget / middleWidget
  // 把内容放进行里。
  return _buildV2Row(
    context: context,
    topic: topic,
    isSelected: isSelected,
    onTap: onTap,
    onMiddleClick: onMiddleClick,
    enableLongPress: enableLongPress,
    highlightColor: highlightColor,
    messageStyle: messageStyle,
    categoryMap: categoryMap,
    previewActions: previewActions,
    topWidget: topWidget,
    middleWidget: middleWidget,
    showUnreadDot: showUnreadDot,
  );
}

/// v2 列表行 + 发丝线；长按浮起「打开 + 调用方给的操作」菜单
Widget _buildV2Row({
  required BuildContext context,
  required Topic topic,
  required bool isSelected,
  required VoidCallback onTap,
  VoidCallback? onMiddleClick,
  required bool enableLongPress,
  required bool messageStyle,
  Color? highlightColor,
  Map<int, Category>? categoryMap,
  List<PreviewAction>? previewActions,
  Widget? topWidget,
  Widget? middleWidget,
  bool showUnreadDot = false,
}) {
  final category = categoryMap?[int.tryParse(topic.categoryId)];
  Widget row = topic.pinned && topWidget == null && middleWidget == null
      ? PinnedTopicRow(
          topic: topic,
          onTap: onTap,
          onMiddleClick: onMiddleClick,
          isSelected: isSelected,
        )
      : TopicRow(
          topic: topic,
          category: category,
          isSelected: isSelected,
          highlightColor: highlightColor,
          showCounts: !messageStyle,
          onTap: onTap,
          onMiddleClick: onMiddleClick,
          topSlot: topWidget,
          middleSlot: middleWidget,
          showUnreadDot: showUnreadDot,
        );

  if (enableLongPress) {
    final actions = previewActions ?? const <PreviewAction>[];
    row = LiftedContextMenu<int>(
      sectionsBuilder: (_) => [
        [
          AppMenuItem(
            label: S.current.topic_rowOpen,
            icon: AppIcons.article,
            value: -1,
          ),
          for (var i = 0; i < actions.length; i++)
            AppMenuItem(
              label: actions[i].label,
              icon: actions[i].icon,
              value: i,
              destructive:
                  actions[i].color == Theme.of(context).colorScheme.error,
            ),
        ],
      ],
      liftedBuilder: (_) =>
          topic.pinned && topWidget == null && middleWidget == null
          ? PinnedTopicRow(topic: topic, onTap: () {})
          : TopicRow(
              topic: topic,
              category: category,
              showCounts: !messageStyle,
              onTap: () {},
              topSlot: topWidget,
              middleSlot: middleWidget,
              showUnreadDot: showUnreadDot,
            ),
      onSelected: (v) {
        if (v == -1) {
          onTap();
        } else {
          actions[v].onTap();
        }
      },
      child: row,
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      row,
      const AppHairline(indent: AppSpace.pageMargin),
    ],
  );
}
