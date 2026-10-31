import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../utils/dialog_utils.dart';

/// 日期范围半屏（设计说明 §5.1「搜索 · 高级筛选」）：开始 / 结束两个
/// Cupertino 日期滚轮，取代系统的日历范围选择器。选完点「确定」返回。
Future<DateTimeRange?> showDateRangeSheet(
  BuildContext context, {
  required DateTime first,
  required DateTime last,
  required DateTimeRange initial,
}) {
  return showAppBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DateRangeSheet(first: first, last: last, initial: initial),
  );
}

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({
    required this.first,
    required this.last,
    required this.initial,
  });

  final DateTime first;
  final DateTime last;
  final DateTimeRange initial;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  late DateTime _start = widget.initial.start;
  late DateTime _end = widget.initial.end;

  /// 当前在调哪一端：0 开始、1 结束
  int _editing = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;

    Widget tab(int index, String label, DateTime value) {
      final selected = _editing == index;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: '$label ${_format(value)}',
          excludeSemantics: true,
          child: AppPressable(
            onTap: () => setState(() => _editing = index),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSize.hit),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
              alignment: Alignment.centerLeft,
              decoration: ShapeDecoration(
                color: colors.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radius.field),
                  side: BorderSide(
                    color: selected ? colors.brandPrimary : Colors.transparent,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: base
                        .merge(tokens.text.caption)
                        .copyWith(color: colors.textMeta),
                  ),
                  Text(
                    _format(value),
                    style: base
                        .merge(tokens.text.control)
                        .copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final current = _editing == 0 ? _start : _end;
    final minimum = _editing == 0 ? widget.first : _start;
    final maximum = _editing == 0 ? _end : widget.last;

    return AppSheetScaffold(
      title: l10n.search_selectDateRange,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pageMargin,
          AppSpace.s,
          AppSpace.pageMargin,
          0,
        ),
        child: FilledButton(
          style: AppButtonStyles.large,
          onPressed: () =>
              Navigator.pop(context, DateTimeRange(start: _start, end: _end)),
          child: Text(l10n.common_confirm),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tab(0, l10n.search_dateStart, _start),
              const SizedBox(width: AppSpace.s),
              tab(1, l10n.search_dateEnd, _end),
            ],
          ),
          SizedBox(
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
                key: ValueKey(_editing),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: current,
                minimumDate: minimum,
                maximumDate: maximum,
                onDateTimeChanged: (value) => setState(() {
                  if (_editing == 0) {
                    _start = value;
                  } else {
                    _end = value;
                  }
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
