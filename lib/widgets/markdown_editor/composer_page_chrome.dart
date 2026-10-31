import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 文档操作的统一图标规格。
class ComposerActionButton extends StatelessWidget {
  const ComposerActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.color,
  });
  final Object icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? color;

  static ButtonStyle get buttonStyle => IconButton.styleFrom(
    minimumSize: const Size(44, 44),
    maximumSize: const Size(44, 44),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    color: color,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    padding: const EdgeInsets.all(10),
    style: buttonStyle,
    icon: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : AppIcon(icon, size: 21),
  );
}

/// 可切换的创建页标题，继承 AppBar 的标题样式。
class ComposerTopicKindPicker extends StatelessWidget {
  const ComposerTopicKindPicker({
    super.key,
    required this.question,
    required this.onChanged,
    this.enabled = true,
    this.locked = false,
  });
  final bool question;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final label = question
        ? S.current.composer_kindQuestion
        : S.current.composer_kindTopic;
    return AppMenuAnchor<bool>(
      enabled: enabled && !locked,
      semanticLabel: label,
      onSelected: (value) {
        if (value != question) onChanged(value);
      },
      sectionsBuilder: (_) => [
        [
          for (final value in [false, true])
            AppMenuItem<bool>(
              rowKey: ValueKey('composer-kind-option-$value'),
              label: value
                  ? S.current.composer_kindQuestion
                  : S.current.composer_kindTopic,
              value: value,
              checked: value == question,
            ),
        ],
      ],
      child: SizedBox(
        key: const ValueKey('composer-kind-trigger'),
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          // 箭头参与标题的自然省略，窄屏优先保留标题文字。
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      locked ? AppIcons.lock : AppIcons.expandMore,
                      size: 16,
                      color: context.tokens.colors.textMeta,
                    ),
                  ),
                ),
              ],
            ),
            key: const ValueKey('composer-title-label'),
            semanticsLabel: label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
