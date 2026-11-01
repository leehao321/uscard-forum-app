import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// 补充稿的填充输入框：标签（13 meta）在框上方，框 r10 无描边、单行最小 44 高，
/// 文字 17，占位 17 meta；聚焦时 1.5pt 品牌色描边、标签变品牌色。
///
/// 用在表单页、对话框和步骤卡片里：
/// - 页面上的框底是 `surface/grouped`（默认）；
/// - 对话框里是 `surface/elevated`，分组卡片里是 `surface/page`，用 [fillColor] 换；
/// - [suffix] 放框内右侧的 20 图标按钮（显示 / 隐藏、粘贴）。
///
/// 校验：[validator] 在外层 [Form] 校验时调用，错误文字显示在框下方（13 破坏性色）。
class AppFilledField extends StatefulWidget {
  const AppFilledField({
    super.key,
    this.label,
    this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled = true,
    this.minLines,
    this.maxLines = 1,
    this.suffix,
    this.fillColor,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textStyle,
  });

  final String? label;
  final TextEditingController? controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool obscureText;
  final bool enabled;
  final int? minLines;
  final int? maxLines;

  /// 框内右侧控件（一般是 [AppIconButton]）
  final Widget? suffix;

  /// 框底色，默认 `surface/grouped`
  final Color? fillColor;
  final String? Function(String value)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autocorrect;
  final bool enableSuggestions;

  /// 覆盖文字样式（如等宽）；默认 17 text/primary
  final TextStyle? textStyle;

  @override
  State<AppFilledField> createState() => _AppFilledFieldState();
}

class _AppFilledFieldState extends State<AppFilledField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focusNode => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
    _focused = _focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(AppFilledField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final control = base
        .merge(tokens.text.control)
        .copyWith(color: colors.textPrimary)
        .merge(widget.textStyle);
    final meta = base
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final multiline = (widget.maxLines ?? 2) != 1;

    return FormField<String>(
      initialValue: _controller.text,
      // 值以控制器为准（程序改文字时 FormField 自己的值会过期）
      validator: (_) => widget.validator?.call(_controller.text),
      builder: (state) {
        final error = state.errorText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s),
                child: Text(
                  widget.label!,
                  style: meta.copyWith(
                    color: _focused ? colors.brandPrimary : colors.textMeta,
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: widget.fillColor ?? colors.surfaceGrouped,
                borderRadius: BorderRadius.circular(tokens.radius.field),
                border: _focused
                    ? Border.all(color: colors.brandPrimary, width: 1.5)
                    : null,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.hit),
                child: Row(
                  crossAxisAlignment: multiline
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        autofocus: widget.autofocus,
                        obscureText: widget.obscureText,
                        autocorrect: widget.autocorrect,
                        enableSuggestions: widget.enableSuggestions,
                        keyboardType: widget.keyboardType,
                        textInputAction: widget.textInputAction,
                        minLines: widget.minLines,
                        maxLines: widget.obscureText ? 1 : widget.maxLines,
                        style: control,
                        cursorColor: colors.brandPrimary,
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: control.copyWith(color: colors.textMeta),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          // 单行：上下 12 + 行高 20 = 44；聚焦描边在框外沿，不占内边距
                          contentPadding: EdgeInsets.fromLTRB(
                            AppSpace.m,
                            AppSpace.m,
                            widget.suffix == null ? AppSpace.m : 0,
                            AppSpace.m,
                          ),
                        ),
                        onChanged: (v) {
                          state.didChange(v);
                          widget.onChanged?.call(v);
                        },
                        onSubmitted: widget.onSubmitted,
                      ),
                    ),
                    if (widget.suffix != null) widget.suffix!,
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  error,
                  style: meta.copyWith(color: colors.textDestructive),
                ),
              ),
          ],
        );
      },
    );
  }
}
