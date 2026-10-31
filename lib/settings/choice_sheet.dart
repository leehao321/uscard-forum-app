import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../utils/dialog_utils.dart';

/// 设置里的单选半屏（0.4.0 v2）：每行一个选项，选中打勾（brand）
///
/// 取代旧的 SimpleDialog 单选。
Future<void> showSettingsChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
  required void Function(T value) onSelected,
}) {
  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppSheetScaffold(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: value == current,
              child: ListTile(
                title: Text(label),
                trailing: value == current
                    ? Icon(
                        AppIcons.check,
                        size: AppSize.iconM,
                        color: sheetContext.tokens.colors.brandPrimary,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSelected(value);
                },
              ),
            ),
        ],
      ),
    ),
  );
}
