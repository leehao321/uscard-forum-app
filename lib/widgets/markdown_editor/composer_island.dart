import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import 'composer_tools_anchor.dart';

const double kComposerIslandRadius = 20;
const double kComposerIslandInset = 8;
const double kComposerIslandBottomGap = 10;

/// 编辑器底部工具岛：v2 工具栏材质（胶囊底色 + 模糊 + 0.5 描边），只负责材质与裁切；
/// 覆盖正文的布局由 ComposerEditorLayout 提供。
class ComposerIsland extends StatelessWidget {
  const ComposerIsland({
    super.key,
    required this.child,
    this.toolsAnchor,
    this.padding = const EdgeInsets.fromLTRB(
      kComposerIslandInset,
      0,
      kComposerIslandInset,
      kComposerIslandBottomGap,
    ),
    this.radius = kComposerIslandRadius,
    this.expansion = 0,
  });
  final Widget child;
  final ComposerToolsAnchor? toolsAnchor;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// 与浮岛几何共用 0–1 进度，保持展开与收起的材质连续。
  final double expansion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: KeyedSubtree(
        key: toolsAnchor?.surfaceKey,
        child: ClipRRect(
          key: const ValueKey('composer-island-surface'),
          borderRadius: BorderRadius.circular(radius),
          child: CapsuleSurface(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
    );
  }
}
