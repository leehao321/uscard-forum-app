import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 骨架屏容器
///
/// v2（设计说明 §4「骨架」）：按真实行的几何画灰条，avatar/fill、r4，
/// **没有闪光动画**。什么时候出骨架由页面决定（请求超过 200ms 才出，
/// 见 [DelayedLoading]）。骨架本身不朗读。
///
/// 使用方式：
/// ```dart
/// Skeleton(
///   child: Column(
///     children: [
///       SkeletonBox(width: 100, height: 20),
///       SkeletonBox(width: 200, height: 16),
///     ],
///   ),
/// )
/// ```
class Skeleton extends StatelessWidget {
  final Widget child;

  const Skeleton({required this.child, super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: child);
}

/// 骨架屏占位条：avatar/fill、r4
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.colors.avatarFill,
        borderRadius: BorderRadius.circular(
          borderRadius * tokens.radius.factor,
        ),
      ),
    );
  }
}

/// 圆形骨架屏占位（头像）
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.tokens.colors.avatarFill,
        shape: BoxShape.circle,
      ),
    );
  }
}
