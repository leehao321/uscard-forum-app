import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import 'package:common_ui/common_ui.dart';

/// username/email + password 输入表单。提交逻辑 (调 DiscourseService 登录 +
/// 处理 hcaptcha/2FA/跳转) 由父组件持有,form 本身只负责 UI 和数据校验。
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onSubmit,
    this.onForgotPassword,
    this.savedUsername,
    this.savedPassword,
  });

  /// 提交回调。父组件返 true = 成功 (form 清空 password), false = 失败 (form 保留)。
  final Future<bool> Function({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  })
  onSubmit;

  /// 忘记密码点击 (一般跳 webview)。
  final VoidCallback? onForgotPassword;

  /// 上次保存的账号 (来自 [CredentialStoreService])。
  final String? savedUsername;
  final String? savedPassword;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _remember = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.savedUsername ?? '');
    _passwordCtrl = TextEditingController(text: widget.savedPassword ?? '');
    _remember =
        (widget.savedPassword != null && widget.savedPassword!.isNotEmpty);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final identifier = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (identifier.isEmpty || password.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    try {
      final ok = await widget.onSubmit(
        identifier: identifier,
        password: password,
        rememberCredentials: _remember,
      );
      if (ok && mounted) {
        _passwordCtrl.clear();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// v2 分组输入：无边框，占位符作标签，行高 52
  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final tokens = context.tokens;
    return InputDecoration(
      hintText: hint,
      hintStyle: tokens.text.control.copyWith(color: tokens.colors.textMeta),
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.l,
        vertical: AppSpace.l,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: AppSpace.l, right: AppSpace.m),
        child: Icon(icon, size: AppSize.iconM, color: tokens.colors.textMeta),
      ),
      prefixIconConstraints: const BoxConstraints(),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final fieldStyle = theme.textTheme.bodyLarge!
        .merge(tokens.text.control)
        .copyWith(color: colors.textPrimary);

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _usernameCtrl,
                  focusNode: _usernameFocus,
                  enabled: !_submitting,
                  style: fieldStyle,
                  cursorColor: colors.brandPrimary,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _inputDecoration(
                    context,
                    hint: '用户名或邮箱',
                    icon: AppIcons.person,
                  ),
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const AppHairline(indent: AppSpace.l),
                TextField(
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  enabled: !_submitting,
                  style: fieldStyle,
                  cursorColor: colors.brandPrimary,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.go,
                  obscureText: _obscure,
                  decoration: _inputDecoration(
                    context,
                    hint: '密码',
                    icon: AppIcons.lock,
                    suffixIcon: AppIconButton(
                      icon: _obscure
                          ? AppIcons.visibility
                          : AppIcons.visibilityOff,
                      semanticLabel: _obscure ? '显示密码' : '隐藏密码',
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.s),
          Row(
            children: [
              // 圆形勾选 + 文字，整行 44 可点
              Semantics(
                checked: _remember,
                label: '记住密码',
                excludeSemantics: true,
                onTap: _submitting
                    ? null
                    : () => setState(() => _remember = !_remember),
                child: AppPressable(
                  onTap: _submitting
                      ? null
                      : () => setState(() => _remember = !_remember),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSize.hit),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _remember
                              ? AppIcons.checkCircle
                              : AppIcons.radioButtonOff,
                          size: AppSize.iconM,
                          color: _remember
                              ? colors.brandPrimary
                              : colors.textMeta,
                        ),
                        const SizedBox(width: AppSpace.s),
                        Text(
                          '记住密码',
                          style: theme.textTheme.bodyMedium!
                              .merge(tokens.text.meta)
                              .copyWith(color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onForgotPassword != null)
                TextButton(
                  onPressed: _submitting ? null : widget.onForgotPassword,
                  child: const Text('忘记密码？'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.s),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: AppButtonStyles.large.merge(
              FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, AppSize.replyButton),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }
}
