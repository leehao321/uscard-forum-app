import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// v2 的按压反馈：没有水波纹。图标、文字按钮按下变淡；列表行、菜单项
/// 按下铺一层浅灰（设计说明 §1 的「系统控件」观感）。
///
/// 只负责手势、反馈和语义；尺寸、热区由调用方的子组件决定。
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.highlight = false,
    this.pressedOpacity = 0.4,
    this.borderRadius,
    this.semanticLabel,
    this.selected,
    this.button = true,
    this.excludeChildSemantics = false,
    this.semanticHint,
    this.inMutuallyExclusiveGroup,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// true：按下时铺一层浅灰底（行、菜单项）；false：按下时整体变淡
  final bool highlight;

  /// [highlight] 为 false 时按下的不透明度
  final double pressedOpacity;

  /// 高亮底的圆角
  final BorderRadius? borderRadius;

  final String? semanticLabel;
  final bool? selected;
  final bool button;

  /// true 时只读 [semanticLabel]，不再合并子组件里的文字
  final bool excludeChildSemantics;

  final String? semanticHint;

  /// Tab、分段选择这类「一组里只选一个」的项
  final bool? inMutuallyExclusiveGroup;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (widget.highlight) {
      final tokens = context.tokens;
      child = DecoratedBox(
        decoration: BoxDecoration(
          // 浅色叠 avatar/fill、深色叠 elevated：和系统列表按下的灰度接近
          color: _pressed
              ? (tokens.brightness == Brightness.dark
                    ? tokens.colors.surfaceElevated
                    : tokens.colors.avatarFill)
              : Colors.transparent,
          borderRadius: widget.borderRadius,
        ),
        child: child,
      );
    } else {
      child = AnimatedOpacity(
        opacity: _pressed ? widget.pressedOpacity : 1,
        // 按下立即变淡，松手淡回（同 CupertinoButton）
        duration: _pressed ? Duration.zero : const Duration(milliseconds: 150),
        child: child,
      );
    }

    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _setPressed(false);
              widget.onLongPress!();
            },
      excludeFromSemantics: true,
      child: child,
    );
    if (_enabled) {
      child = MouseRegion(cursor: SystemMouseCursors.click, child: child);
    }

    return Semantics(
      container: true,
      button: widget.button,
      enabled: widget.button ? _enabled : null,
      selected: widget.selected,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: child,
    );
  }
}
