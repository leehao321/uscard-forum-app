import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../utils/dialog_utils.dart';

/// 分类、标签和话题共用的顶部订阅入口（44 热区的图标按钮）。
class NotificationLevelButton extends StatelessWidget {
  const NotificationLevelButton({
    super.key,
    required this.level,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.errorTooltip,
  });

  final int? level;
  final String? label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? errorTooltip;

  @override
  Widget build(BuildContext context) {
    final title = context.l10n.topic_notificationSettings;
    final semanticLabel =
        errorTooltip ?? (label == null ? title : '$title: $label');
    if (isLoading) {
      return Semantics(
        label: semanticLabel,
        child: const SizedBox.square(
          dimension: AppSize.hit,
          child: Center(
            child: CupertinoActivityIndicator(radius: AppSize.iconS / 2),
          ),
        ),
      );
    }
    return AppIconButton(
      icon: errorTooltip == null
          ? notificationLevelIcon(level)
          : AppIcons.warning,
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      color: errorTooltip == null && (level ?? 1) >= 2
          ? context.tokens.colors.brandPrimary
          : null,
    );
  }
}

/// Discourse 通知级别 → 图标：静音 bell-off、常规 / 跟踪 bell、关注
/// bell-ring、关注首帖 bell-plus（选中与否用颜色区分）
IconData notificationLevelIcon(int? level) => switch (level) {
  0 => AppIcons.notificationOff,
  3 => AppIcons.notificationActive,
  4 => AppIcons.notificationAdd,
  _ => AppIcons.notification,
};

class NotificationLevelOption<T> {
  const NotificationLevelOption({
    required this.value,
    required this.icon,
    required this.label,
    required this.description,
  });

  final T value;
  final IconData icon;
  final String label;
  final String description;
}

/// 页面、侧栏和快捷手势共用的订阅选择半屏（「本帖通知」画板）：每行
/// 图标 20 + 标题 17 / 说明 13 meta，当前级别右侧 check 20 brand；行间
/// 分隔线缩进到文字起点。
void showNotificationLevelSelectionSheet<T>({
  required BuildContext context,
  required T currentLevel,
  required List<NotificationLevelOption<T>> options,
  required ValueChanged<T> onSelected,
}) {
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return AppSheetScaffold(
        title: sheetContext.l10n.topic_notificationSettings,
        contentPadding: EdgeInsets.zero,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0)
                  const AppHairline(
                    indent: AppSpace.pageMargin + AppSize.iconM + AppSpace.m,
                    endIndent: AppSpace.pageMargin,
                  ),
                _NotificationLevelRow(
                  option: options[i],
                  selected: options[i].value == currentLevel,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (options[i].value != currentLevel) {
                      onSelected(options[i].value);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _NotificationLevelRow<T> extends StatelessWidget {
  const _NotificationLevelRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final NotificationLevelOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return AppPressable(
      highlight: true,
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.pageMargin,
          vertical: AppSpace.m,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                option.icon,
                size: AppSize.iconM,
                color: selected ? colors.brandPrimary : colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: base
                        .merge(tokens.text.control)
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    option.description,
                    style: base
                        .merge(tokens.text.meta)
                        .copyWith(color: colors.textMeta),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpace.m),
              Icon(
                AppIcons.check,
                size: AppSize.iconM,
                color: colors.brandPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
