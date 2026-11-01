import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

/// 设置里的单选对话框（补充稿 34）：标题左对齐，每行一个选项，当前项右侧
/// 打勾（brand），底部「取消」。点选项即生效并关闭。
Future<void> showSettingsChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
  required void Function(T value) onSelected,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      width: AppSize.dialogWidth,
      title: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(title, textAlign: TextAlign.start),
      ),
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

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
