import 'dart:io';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/utils/dialog_utils.dart';

import 'support/ui_harness.dart';

// Gemini 审阅核实 B · M-12：`AppAlertDialog._isPlainText` 对外包 `ConstrainedBox` /
// `SingleChildScrollView` 的纯文字不穿透。三处受影响的弹窗（内容结构和现场代码
// 一致）在改动前后各出一组浅 / 深截图，对照设计说明 §4「对话框」：
// 标题 17 Semibold 居中、说明 13 meta、左右外边距 60（宽 320）。
//
// 用法：M12_PHASE=before|after SHOTS_DIR=... flutter test 这个文件

final _phase = Platform.environment['M12_PHASE'] ?? 'run';

Widget _host(
  Widget Function(BuildContext) dialogBuilder,
) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => showAppDialog<void>(
        context: context,
        builder: (ctx) => dialogBuilder(ctx),
      ),
      child: const Text('open'),
    ),
  ),
);

/// 三处弹窗：和现场代码相同的内容包装
final _dialogs = <String, Widget Function(BuildContext)>{
  // lib/widgets/auth/qr_login_sheet.dart `_confirmAndGenerate`：ConstrainedBox 包 Text
  'qr_confirm': (ctx) => AppAlertDialog(
    title: Text(ctx.l10n.login_qrConfirmTitle),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Text(ctx.l10n.login_qrConfirmMessage),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(ctx.l10n.common_cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(ctx.l10n.login_qrConfirmAction),
      ),
    ],
  ),
  // lib/widgets/post/post_item/widgets/post_device_source.dart：SingleChildScrollView 包 SelectableText
  'device_source': (ctx) => AppAlertDialog(
    title: Text(ctx.l10n.post_deviceSourceTitle),
    content: SingleChildScrollView(
      child: SelectableText(ctx.l10n.post_deviceSource('iPhone 16 Pro')),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(ctx.l10n.common_close),
      ),
    ],
  ),
  // lib/pages/network_settings_page/widgets/engine_card.dart `_showFailureReasonDialog`：
  // SingleChildScrollView 包等宽的 SelectableText（技术原因）
  'engine_reason': (ctx) => AppAlertDialog(
    title: Text(ctx.l10n.networkAdapter_degradeReason),
    content: SingleChildScrollView(
      child: SelectableText(
        'CronetException: ERR_CONNECTION_RESET (-101)\n'
        '  at org.chromium.net.impl.CronetUrlRequest.onFailed\n'
        '  open https://example.invalid/latest.json',
        // 现场代码 M-12 之后加了 textAlign: start（技术原因要左对齐）
        textAlign: _phase == 'before' ? null : TextAlign.start,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text(ctx.l10n.common_close),
      ),
      FilledButton(onPressed: () {}, child: Text(ctx.l10n.common_copy)),
    ],
  ),
};

void main() {
  setUpAll(loadUiFonts);

  for (final entry in _dialogs.entries) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testUi('M-12 ${entry.key}（${brightness.name}）', (tester) async {
        await pumpUi(
          tester,
          _host(entry.value),
          variant: UiVariant(brightness, 1, UiDevice.pro),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        await uiShot(tester, 'm12_${_phase}_${entry.key}_${brightness.name}');
        // 对话框宽度：设计说明 §4 纯文字确认 320
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
