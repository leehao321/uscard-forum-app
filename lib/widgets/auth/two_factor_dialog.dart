import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/services.dart';

/// 二步验证 (TOTP) 输入对话框。返回用户输入的 6 位 code,取消返 null。
///
/// 用法:
/// ```dart
/// final code = await showTwoFactorDialog(context);
/// if (code != null) {
///   // 用 code 重 POST /session.json
/// }
/// ```
Future<String?> showTwoFactorDialog(
  BuildContext context, {
  String? hint,
  VoidCallback? onUseBackupCode,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _TwoFactorDialog(hint: hint, onUseBackupCode: onUseBackupCode),
  );
}

class _TwoFactorDialog extends StatefulWidget {
  const _TwoFactorDialog({this.hint, this.onUseBackupCode});

  final String? hint;
  final VoidCallback? onUseBackupCode;

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.length != 6) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    return AppAlertDialog(
      title: const Text('二步验证'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.hint ?? '请输入身份验证器 App 显示的 6 位验证码',
            style: theme.textTheme.bodySmall
                ?.merge(tokens.text.meta)
                .copyWith(color: colors.textMeta),
          ),
          const SizedBox(height: AppSpace.l),
          // 6 格：格子只负责显示，真正的输入框叠在上面（透明），
          // 这样自动填充、粘贴和读屏都走同一个输入框
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) {
              final text = value.text;
              return Stack(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpace.s),
                        Expanded(
                          child: _Cell(
                            char: i < text.length ? text[i] : '',
                            active: i == text.length.clamp(0, 5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Positioned.fill(
                    child: Semantics(
                      label: '验证码，6 位数字',
                      textField: true,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        enableInteractiveSelection: false,
                        showCursor: false,
                        style: const TextStyle(color: Colors.transparent),
                        cursorColor: Colors.transparent,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          counterText: '',
                        ),
                        onChanged: (v) {
                          if (v.length == 6) _submit();
                        },
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (widget.onUseBackupCode != null) ...[
            const SizedBox(height: AppSpace.s),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onUseBackupCode!();
                },
                child: const Text('改用备用码或安全密钥'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, _) {
            final enabled = value.text.trim().length == 6;
            return AppDialogAction(
              onPressed: enabled ? _submit : null,
              child: const Text('验证'),
            );
          },
        ),
      ],
    );
  }
}

/// 一格：48 高，r10，surface/elevated；当前格 1.5pt brand 内描边
class _Cell extends StatelessWidget {
  const _Cell({required this.char, required this.active});

  final String char;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radius.field),
        border: active
            ? Border.all(color: colors.brandPrimary, width: 1.5)
            : Border.all(color: colors.separator, width: AppSpace.hairline),
      ),
      child: Text(
        char,
        style: Theme.of(context).textTheme.titleLarge
            ?.merge(tokens.text.control)
            .copyWith(
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}
