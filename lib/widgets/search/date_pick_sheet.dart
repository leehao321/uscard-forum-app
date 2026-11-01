import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../utils/dialog_utils.dart';

/// 选一个日期的半屏（设计说明 §5.1「搜索 · 高级筛选」自定义时间的开始 / 结束日期）：
/// 一个 Cupertino 日期滚轮（iOS 系统日期选择器），选完点「确定」返回当天 0 点。
/// 点关闭 / 下滑返回 null。
Future<DateTime?> showDatePickSheet(
  BuildContext context, {
  required String title,
  required DateTime first,
  required DateTime last,
  required DateTime initial,
}) {
  return showAppBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DatePickSheet(
      title: title,
      first: first,
      last: last,
      initial: initial,
    ),
  );
}

class _DatePickSheet extends StatefulWidget {
  const _DatePickSheet({
    required this.title,
    required this.first,
    required this.last,
    required this.initial,
  });

  final String title;
  final DateTime first;
  final DateTime last;
  final DateTime initial;

  @override
  State<_DatePickSheet> createState() => _DatePickSheetState();
}

class _DatePickSheetState extends State<_DatePickSheet> {
  late DateTime _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;

    return AppSheetScaffold(
      title: widget.title,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pageMargin,
          AppSpace.s,
          AppSpace.pageMargin,
          0,
        ),
        child: FilledButton(
          style: AppButtonStyles.large,
          onPressed: () => Navigator.pop(context, DateUtils.dateOnly(_value)),
          child: Text(context.l10n.common_confirm),
        ),
      ),
      child: SizedBox(
        height: 180,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: base
                  .merge(tokens.text.control)
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.date,
            initialDateTime: widget.initial,
            minimumDate: widget.first,
            maximumDate: widget.last,
            onDateTimeChanged: (value) => _value = value,
          ),
        ),
      ),
    );
  }
}
