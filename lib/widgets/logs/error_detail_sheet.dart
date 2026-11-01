import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/s.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';

/// 「复制」复制出去的文字：错误类型一行 + 完整堆栈（原样，不截断）。
///
/// 没有错误类型时退回 [fallbackTitle]（一般是错误文字或日志消息）；
/// 没有堆栈就只复制那一行。
String buildErrorCopyText({
  String? errorType,
  String? stackTrace,
  String? fallbackTitle,
}) {
  final head = (errorType != null && errorType.trim().isNotEmpty)
      ? errorType
      : (fallbackTitle ?? '');
  final stack = stackTrace?.trimRight() ?? '';
  if (stack.isEmpty) return head;
  if (head.isEmpty) return stack;
  return '$head\n$stack';
}

/// 日志里一条错误的详情半屏（补充稿 37，沿用请求详情半屏模板）：
/// 标题「错误详情」+ 右上复制 + 关闭；类型 / 级别 / 时间 / 版本分组行；
/// 一句错误说明；堆栈代码块（等宽）；底部「复制错误类型和完整堆栈」。
/// 右上和底部两个「复制」复制的是同一份文字（[buildErrorCopyText]）。
Future<void> showErrorDetailSheet(
  BuildContext context, {
  required String level,
  required String timestamp,
  String? tag,
  String? errorType,
  String? appVersion,
  String? message,
  Map<String, String> extras = const {},
  String? stackTrace,
}) {
  final copyText = buildErrorCopyText(
    errorType: errorType,
    stackTrace: stackTrace,
    fallbackTitle: message,
  );
  void copy() {
    Clipboard.setData(ClipboardData(text: copyText));
    ToastService.showSuccess(S.current.common_copiedToClipboard);
  }

  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final tokens = sheetContext.tokens;
      final base = Theme.of(sheetContext).textTheme.bodyMedium!;
      final meta = base
          .merge(tokens.text.meta)
          .copyWith(color: tokens.colors.textMeta);
      final rows = <(String, String)>[
        (l10n.appLogs_type, errorType ?? '-'),
        (l10n.appLogs_level, level.toUpperCase()),
        if (tag != null) (l10n.appLogs_tag, tag),
        (l10n.appLogs_time, timestamp),
        if (appVersion != null) (l10n.appLogs_version, appVersion),
      ];
      final hasStack = stackTrace != null && stackTrace.trim().isNotEmpty;
      Widget codeBlock(String label, String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
            child: Text(label, style: meta),
          ),
          const SizedBox(height: AppSpace.s),
          Container(
            padding: const EdgeInsets.all(AppSpace.m),
            decoration: BoxDecoration(
              color: tokens.colors.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            child: SelectableText(
              text,
              style: base
                  .merge(tokens.text.monoUrl)
                  .copyWith(color: tokens.colors.textPrimary),
            ),
          ),
        ],
      );
      return AppSheetScaffold(
        title: l10n.appLogs_errorDetail,
        maxHeightFactor: 0.85,
        actions: [
          AppIconButton(
            icon: AppIcons.copy,
            semanticLabel: l10n.appLogs_copyErrorAndStack,
            onPressed: copy,
          ),
        ],
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.l,
            AppSpace.pageMargin,
            0,
          ),
          child: _CopyButton(
            label: l10n.appLogs_copyErrorAndStack,
            onTap: copy,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radius.card),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const AppHairline(indent: AppSpace.m),
                      _DetailRow(label: rows[i].$1, value: rows[i].$2),
                    ],
                  ],
                ),
              ),
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: AppSpace.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                  child: SelectableText(message, style: meta),
                ),
              ],
              if (extras.isNotEmpty)
                codeBlock(
                  l10n.appLogs_otherFields,
                  [for (final e in extras.entries) '${e.key}: ${e.value}']
                      .join('\n'),
                ),
              if (hasStack) codeBlock(l10n.appLogs_stack, stackTrace),
            ],
          ),
        ),
      );
    },
  );
}

/// 分组里的一行：左 17 text/primary、右 17 meta（右对齐，长了换行），最小高 48
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = Theme.of(context).textTheme.bodyMedium!
        .merge(tokens.text.control);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.row48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.m,
          vertical: AppSpace.s,
        ),
        child: Row(
          children: [
            Text(label, style: base.copyWith(color: tokens.colors.textPrimary)),
            const SizedBox(width: AppSpace.l),
            Expanded(
              child: SelectableText(
                value,
                textAlign: TextAlign.end,
                style: base.copyWith(color: tokens.colors.textMeta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部整宽「复制」按钮：44 高 r10、底 surface/elevated、brand 文字 + 复制图标 16
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSize.hit),
        decoration: BoxDecoration(
          color: tokens.colors.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radius.field),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.copy,
              size: AppSize.iconS,
              color: tokens.colors.brandPrimary,
            ),
            const SizedBox(width: AppSpace.s),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium!
                    .merge(tokens.text.headline)
                    .copyWith(color: tokens.colors.brandPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
