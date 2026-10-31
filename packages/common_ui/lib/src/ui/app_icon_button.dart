import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_pressable.dart';
import 'badges.dart';

/// v2 图标按钮：44×44 热区，图标默认 24 text/primary，按下变淡。
///
/// [semanticLabel] 必填（计划 §9）：VoiceOver 读它，桌面端悬停也显示它。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.size = AppSize.iconL,
    this.color,
    this.selected,
    this.showDot = false,
    this.onLongPress,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final double size;

  /// 默认 text/primary；不可点时 text/meta
  final Color? color;

  /// 两态按钮（书签、关注）的选中状态，只影响朗读
  final bool? selected;

  /// 图标右上角的未读点
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null || onLongPress != null;
    Widget glyph = Icon(
      icon,
      size: size,
      color: enabled ? (color ?? colors.textPrimary) : colors.textMeta,
    );
    if (showDot) {
      glyph = Stack(
        clipBehavior: Clip.none,
        children: [
          glyph,
          const Positioned(top: -1, right: -3, child: UnreadDot()),
        ],
      );
    }
    Widget button = AppPressable(
      onTap: onPressed,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      selected: selected,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: AppSize.hit,
        child: Center(child: glyph),
      ),
    );
    if (_isDesktop(Theme.of(context).platform)) {
      button = Tooltip(
        message: semanticLabel,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return button;
  }

  static bool _isDesktop(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
}
