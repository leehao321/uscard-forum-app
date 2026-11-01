import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

/// 设置里的单选对话框：标题左对齐，每行一个选项，当前项右侧打勾（brand），
/// 底部「取消」。点选项即生效并关闭（补充稿 34 / 35 的单选对话框）。
///
/// 选项可带前导图标（[iconOf]，20 meta），不带就只有文字。
Future<void> showSettingsChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
  required void Function(T value) onSelected,
  String? subtitle,
  IconData? Function(T value)? iconOf,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      width: AppSize.dialogWidth,
      title: _ChoiceTitle(title: title, subtitle: subtitle),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpace.l,
        AppSpace.l,
        AppSpace.l,
        AppSpace.s,
      ),
      contentPadding: EdgeInsets.zero,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const AppHairline(indent: AppSpace.m),
            _ChoiceRow(
              label: options[i].$2,
              icon: iconOf?.call(options[i].$1),
              selected: options[i].$1 == current,
              onTap: () {
                Navigator.pop(dialogContext);
                onSelected(options[i].$1);
              },
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction.text(
          onPressed: () => Navigator.pop(dialogContext),
          label: dialogContext.l10n.common_cancel,
        ),
      ],
    ),
  );
}

class _ChoiceTitle extends StatelessWidget {
  const _ChoiceTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(title, textAlign: TextAlign.start),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(
            subtitle!,
            textAlign: TextAlign.start,
            style: Theme.of(context).textTheme.bodySmall!
                .merge(tokens.text.meta)
                .copyWith(color: tokens.colors.textMeta),
          ),
        ],
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppPressable(
      highlight: true,
      onTap: onTap,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSize.iconM, color: tokens.colors.textMeta),
                const SizedBox(width: AppSpace.m),
              ],
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium!
                      .merge(tokens.text.control)
                      .copyWith(color: tokens.colors.textPrimary),
                ),
              ),
              if (selected)
                Icon(
                  AppIcons.check,
                  size: AppSize.iconM,
                  color: tokens.colors.brandPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
