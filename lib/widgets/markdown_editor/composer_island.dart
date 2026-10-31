import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../utils/platform_utils.dart';
import 'composer_tools_anchor.dart';

const double kComposerIslandRadius = 20;
const double kComposerIslandInset = 8;
const double kComposerIslandBottomGap = 10;

/// 编辑器底部工具岛：v2 工具栏材质（胶囊底色 + 模糊 + 0.5 描边），只负责材质与裁切；
/// 覆盖正文的布局由 ComposerEditorLayout 提供。
///
/// 横屏手机（短边 < 600）改成通栏：底色横跨整个屏宽（顶部 0.5 分隔线，没有圆角和
/// 左右留白），按钮按阅读列（[readableInsets]，设计说明 §5.6）左右对齐，和阅读页
/// 横屏底部工具栏同一做法；竖屏和宽屏（平板、桌面）保持浮岛。
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

  /// 横屏手机：通栏工具条
  static bool isLandscapePhone(BuildContext context) {
    // 桌面窗口再矮也不是手机横屏
    if (!PlatformUtils.isMobile) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.shortestSide < 600;
  }

  @override
  Widget build(BuildContext context) {
    if (isLandscapePhone(context)) {
      // 底部留白仍然算在条里（高度计算不变），内容按阅读列对齐
      final insets = readableInsets(context, gutter: 0);
      return KeyedSubtree(
        key: toolsAnchor?.surfaceKey,
        child: BarSurface(
          key: const ValueKey('composer-island-surface'),
          edge: BarEdge.top,
          child: Padding(
            padding: EdgeInsets.only(
              left: insets.left,
              right: insets.right,
              bottom: kComposerIslandBottomGap,
            ),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      );
    }
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
