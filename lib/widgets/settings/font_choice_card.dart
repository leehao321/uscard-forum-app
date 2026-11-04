import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 字体卡片里的一个选项。
@immutable
class FontChoice<T> {
  const FontChoice({required this.value, required this.label, this.fontFamily});

  final T value;
  final String label;

  /// 用这个字体显示选项名，让用户看到字体的样子；null 用当前字体
  final String? fontFamily;
}

/// 外观设置里的字体卡片：选项和「导入字体」在同一张圆角卡片里。
///
/// 按 iOS 设置的规范：选中的选项右侧打勾，没有单选按钮；各行标题从同一个位置开始，
/// 「导入字体」上方一条淡淡的分割线。
class FontChoiceCard<T> extends StatelessWidget {
  const FontChoiceCard({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    required this.importTitle,
    required this.importSubtitle,
    required this.onImport,
  });

  static const radius = 16.0;
  static const rowHorizontalPadding = 16.0;

  final List<FontChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;
  final String importTitle;
  final String importSubtitle;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color ?? scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            _FontChoiceRow(
              label: choice.label,
              fontFamily: choice.fontFamily,
              selected: choice.value == selected,
              onTap: () {
                if (choice.value == selected) return;
                HapticFeedback.selectionClick();
                onSelected(choice.value);
              },
            ),
          Divider(
            height: 1,
            indent: rowHorizontalPadding,
            endIndent: rowHorizontalPadding,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _FontImportRow(
            title: importTitle,
            subtitle: importSubtitle,
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}

class _FontChoiceRow extends StatelessWidget {
  const _FontChoiceRow({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FontChoiceCard.rowHorizontalPadding,
              vertical: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFamily: fontFamily,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: 22, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FontImportRow extends StatelessWidget {
  const _FontImportRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FontChoiceCard.rowHorizontalPadding,
              vertical: 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Symbols.upload_file_rounded, size: 22, color: muted),
                const SizedBox(width: 4),
                Icon(Symbols.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
