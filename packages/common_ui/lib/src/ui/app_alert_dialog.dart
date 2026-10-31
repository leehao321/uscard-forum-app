import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_pressable.dart';
import 'surfaces.dart';

/// v2 对话框（设计说明 §4）：宽 320、r16、底同半屏底；正文区 pad 20 16 16、
/// 间距 4：标题 17 Semibold 居中、说明 13 meta；按钮行 44 高，顶部 0.5
/// 分隔线，按钮间 0.5 竖线；按钮文字 17 brand/primary，破坏性
/// text/destructive。
///
/// 参数和 [AlertDialog] 一样，旧调用点改个类名就能用：
/// - [actions] 里的 TextButton / FilledButton 等会被拆成「文字 + 回调」重画
///   成按钮行；按钮样式里前景或背景是红色（colorScheme.error）的当成破坏性。
///   两个以内横排，三个及以上竖排。
/// - [content] 是一段文字时按说明样式居中；是表单、列表等复杂内容时用
///   17 正文样式左对齐，宽度放到 360（带输入框的对话框左右 40）。
/// - 只为兼容保留、v2 不用的参数（elevation、shape 等）会被忽略。
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.icon,
    this.iconPadding,
    this.iconColor,
    this.title,
    this.titlePadding,
    this.titleTextStyle,
    this.content,
    this.contentPadding,
    this.contentTextStyle,
    this.actions,
    this.actionsPadding,
    this.actionsAlignment,
    this.actionsOverflowAlignment,
    this.actionsOverflowDirection,
    this.actionsOverflowButtonSpacing,
    this.buttonPadding,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.semanticLabel,
    this.insetPadding,
    this.clipBehavior,
    this.shape,
    this.alignment,
    this.scrollable = false,
    this.constraints,
    this.width,
  });

  final Widget? icon;
  final EdgeInsetsGeometry? iconPadding;
  final Color? iconColor;
  final Widget? title;
  final EdgeInsetsGeometry? titlePadding;
  final TextStyle? titleTextStyle;
  final Widget? content;

  /// 给了就照用（列表类内容常传 zero 贴边）
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? contentTextStyle;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? actionsPadding;
  final MainAxisAlignment? actionsAlignment;
  final OverflowBarAlignment? actionsOverflowAlignment;
  final VerticalDirection? actionsOverflowDirection;
  final double? actionsOverflowButtonSpacing;
  final EdgeInsetsGeometry? buttonPadding;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final String? semanticLabel;
  final EdgeInsets? insetPadding;
  final Clip? clipBehavior;
  final ShapeBorder? shape;
  final AlignmentGeometry? alignment;
  final bool scrollable;
  final BoxConstraints? constraints;

  /// 覆盖宽度；默认纯文字 320、复杂内容 360
  final double? width;

  static bool _isPlainText(Widget? w) =>
      w == null || w is Text || w is RichText || w is SelectableText;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final plain = _isPlainText(content);
    final screen = MediaQuery.sizeOf(context).width;
    final dialogWidth = math.min(
      width ??
          (plain
              ? AppSize.dialogWidth
              : AppSize.dialogWidth + 2 * (60 - AppSize.dialogInsetInput)),
      screen - 2 * AppSpace.l,
    );

    final head = <Widget>[
      if (icon != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s),
          child: IconTheme.merge(
            data: IconThemeData(
              size: AppSize.iconL,
              color: iconColor ?? colors.textMeta,
            ),
            child: icon!,
          ),
        ),
      if (title != null)
        Semantics(
          header: true,
          child: DefaultTextStyle(
            style: base
                .merge(tokens.text.headline)
                .copyWith(color: colors.textPrimary)
                .merge(titleTextStyle),
            textAlign: TextAlign.center,
            child: title!,
          ),
        ),
    ];

    Widget? body;
    if (content != null) {
      final style = plain
          ? base.merge(tokens.text.meta).copyWith(color: colors.textMeta)
          : base.merge(tokens.text.control).copyWith(color: colors.textPrimary);
      body = DefaultTextStyle(
        style: style.merge(contentTextStyle),
        textAlign: plain ? TextAlign.center : TextAlign.start,
        child: content!,
      );
    }

    // 纯文字：标题和说明在同一个可滚动区（pad 20 16 16、间距 4）；
    // 复杂内容：标题固定在上面，内容自己决定滚不滚（同 AlertDialog）
    final textArea = <Widget>[];
    if (plain || scrollable) {
      textArea.add(
        Flexible(
          child: SingleChildScrollView(
            padding:
                contentPadding ??
                const EdgeInsets.fromLTRB(
                  AppSpace.l,
                  AppSpace.xl,
                  AppSpace.l,
                  AppSpace.l,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...head,
                if (head.isNotEmpty && body != null)
                  const SizedBox(height: AppSpace.xs),
                ?body,
              ],
            ),
          ),
        ),
      );
    } else {
      if (head.isNotEmpty) {
        textArea.add(
          Padding(
            padding:
                titlePadding ??
                const EdgeInsets.fromLTRB(
                  AppSpace.l,
                  AppSpace.xl,
                  AppSpace.l,
                  AppSpace.m,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: head,
            ),
          ),
        );
      }
      textArea.add(
        Flexible(
          child: Padding(
            padding:
                contentPadding ??
                EdgeInsets.fromLTRB(
                  AppSpace.l,
                  head.isEmpty ? AppSpace.xl : 0,
                  AppSpace.l,
                  AppSpace.l,
                ),
            child: body!,
          ),
        ),
      );
    }

    final buttons = actions ?? const <Widget>[];
    final dialog = Dialog(
      backgroundColor: backgroundColor ?? tokens.materials.sheetFill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpace.l,
            vertical: AppSpace.xxl,
          ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.sheet),
      ),
      alignment: alignment,
      constraints: BoxConstraints(maxWidth: dialogWidth),
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...textArea,
            if (buttons.isNotEmpty) ...[
              const AppHairline(),
              _DialogActions(actions: buttons),
            ],
          ],
        ),
      ),
    );

    final label =
        semanticLabel ??
        (title is Text ? (title! as Text).data : null) ??
        MaterialLocalizations.of(context).alertDialogLabel;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: label,
      child: dialog,
    );
  }
}

/// 对话框按钮（新代码直接用；旧的 TextButton 也会被转换成它）
class AppDialogAction extends StatelessWidget {
  const AppDialogAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.destructive = false,
  });

  /// 文字版快捷写法
  AppDialogAction.text({
    super.key,
    required this.onPressed,
    required String label,
    this.destructive = false,
  }) : child = Text(label);

  final VoidCallback? onPressed;
  final Widget child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final color = onPressed == null
        ? colors.textMeta
        : destructive
        ? colors.textDestructive
        : colors.brandPrimary;
    return AppPressable(
      highlight: true,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s,
            vertical: AppSpace.s,
          ),
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(size: AppSize.iconM, color: color),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!
                    .merge(tokens.text.control)
                    .copyWith(color: color),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.actions});

  final List<Widget> actions;

  /// 旧按钮转成 [AppDialogAction]：只取文字（child）和回调，丢掉原样式
  static Widget _adapt(BuildContext context, Widget action) {
    if (action is AppDialogAction) return action;
    if (action is ButtonStyleButton) {
      return AppDialogAction(
        onPressed: action.onPressed,
        destructive: _isDestructive(context, action.style),
        child: action.child ?? const SizedBox.shrink(),
      );
    }
    // 其它自定义组件（比如 builder 里返回 AppDialogAction）：给满格宽度、
    // 至少 44 高，原样显示
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.hit),
      child: action,
    );
  }

  static bool _isDestructive(BuildContext context, ButtonStyle? style) {
    if (style == null) return false;
    final error = Theme.of(context).colorScheme.error;
    final destructive = context.tokens.colors.textDestructive;
    bool reddish(Color? c) {
      if (c == null || c.a == 0) return false;
      if (c == error || c == destructive) return true;
      return c.r > 0.7 && c.g < 0.4 && c.b < 0.4;
    }

    const states = <WidgetState>{};
    return reddish(style.foregroundColor?.resolve(states)) ||
        reddish(style.backgroundColor?.resolve(states));
  }

  @override
  Widget build(BuildContext context) {
    final adapted = [for (final a in actions) _adapt(context, a)];
    if (adapted.length <= 2) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < adapted.length; i++) ...[
              if (i > 0) const AppHairline.vertical(),
              Expanded(child: adapted[i]),
            ],
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < adapted.length; i++) ...[
          if (i > 0) const AppHairline(),
          adapted[i],
        ],
      ],
    );
  }
}
