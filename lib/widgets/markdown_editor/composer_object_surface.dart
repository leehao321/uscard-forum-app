import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 所有对象工具条与菜单共享的 v2 浮层材质：surface/elevated 不透明底 + 浮层阴影。
class ComposerObjectSurface extends StatelessWidget {
  const ComposerObjectSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.compact = false,
  });
  final Widget child;
  final double radius;
  final bool compact;
  @override
  Widget build(BuildContext context) => CapsuleSurface(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    fill: context.tokens.colors.surfaceElevated,
    child: Material(color: Colors.transparent, child: child),
  );
}
