import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../models/category.dart';
import '../../models/topic.dart';
import '../common/notification_level_button.dart';

enum TopicNotificationButtonStyle { icon, chip }

class TopicNotificationButton extends StatelessWidget {
  const TopicNotificationButton({
    super.key,
    required this.level,
    this.onChanged,
    this.isLoading = false,
    this.style = TopicNotificationButtonStyle.icon,
  });

  final TopicNotificationLevel level;
  final ValueChanged<TopicNotificationLevel>? onChanged;
  final bool isLoading;
  final TopicNotificationButtonStyle style;

  static IconData getIcon(TopicNotificationLevel level) =>
      notificationLevelIcon(level.value);

  @override
  Widget build(BuildContext context) {
    if (style == TopicNotificationButtonStyle.chip) {
      return _buildChip(context);
    }
    return NotificationLevelButton(
      level: level.value,
      label: level.label,
      isLoading: isLoading,
      onPressed: onChanged == null ? null : () => _showSheet(context),
    );
  }

  /// AI 摘要卡片内的订阅入口：筛选胶囊样式，关注 / 跟踪时文字变 brand。
  Widget _buildChip(BuildContext context) {
    final isWatching =
        level == TopicNotificationLevel.watching ||
        level == TopicNotificationLevel.tracking;
    return FilterPill(
      label: level.label,
      icon: getIcon(level),
      selected: isWatching,
      onTap: onChanged != null ? () => _showSheet(context) : null,
    );
  }

  void _showSheet(BuildContext context) {
    if (onChanged == null) return;
    showNotificationLevelSheet(context, level, onChanged!);
  }
}

/// 「本帖通知」半屏：从高到低（关注 → 静音）排列，同设计稿。
void showNotificationLevelSheet(
  BuildContext context,
  TopicNotificationLevel currentLevel,
  ValueChanged<TopicNotificationLevel> onSelected,
) {
  showNotificationLevelSelectionSheet(
    context: context,
    currentLevel: currentLevel,
    options: [
      for (final level in TopicNotificationLevel.values.reversed)
        NotificationLevelOption(
          value: level,
          icon: TopicNotificationButton.getIcon(level),
          label: level.label,
          description: level.description,
        ),
    ],
    onSelected: onSelected,
  );
}

class CategoryNotificationButton extends StatelessWidget {
  const CategoryNotificationButton({
    super.key,
    required this.level,
    this.onChanged,
    this.isLoading = false,
  });

  final CategoryNotificationLevel level;
  final ValueChanged<CategoryNotificationLevel>? onChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => NotificationLevelButton(
    level: level.value,
    label: level.label,
    isLoading: isLoading,
    onPressed: onChanged == null
        ? null
        : () => showCategoryNotificationLevelSheet(context, level, onChanged!),
  );
}

IconData getCategoryNotificationIcon(CategoryNotificationLevel level) =>
    notificationLevelIcon(level.value);

/// 分类详情页与侧栏共用的订阅选择入口。
void showCategoryNotificationLevelSheet(
  BuildContext context,
  CategoryNotificationLevel currentLevel,
  ValueChanged<CategoryNotificationLevel> onSelected,
) {
  showNotificationLevelSelectionSheet(
    context: context,
    currentLevel: currentLevel,
    options: [
      for (final level in CategoryNotificationLevel.values.reversed)
        NotificationLevelOption(
          value: level,
          icon: getCategoryNotificationIcon(level),
          label: level.label,
          description: level.description,
        ),
    ],
    onSelected: onSelected,
  );
}
