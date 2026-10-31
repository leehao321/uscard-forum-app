import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// 0.5 发丝线（separator）。横线默认铺满，[indent] 是左缩进。
class AppHairline extends StatelessWidget {
  const AppHairline({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  }) : vertical = false,
       height = null;

  /// 竖线：按钮行之间、分类条里「全部 · 精彩 · 难绷」后面那根
  const AppHairline.vertical({super.key, this.height, this.color})
    : vertical = true,
      indent = 0,
      endIndent = 0;

  final double indent;
  final double endIndent;
  final Color? color;
  final bool vertical;

  /// 竖线高度；null 时撑满父级
  final double? height;

  @override
  Widget build(BuildContext context) {
    final line = ColoredBox(color: color ?? context.tokens.colors.separator);
    if (vertical) {
      return ExcludeSemantics(
        child: SizedBox(width: AppSpace.hairline, height: height, child: line),
      );
    }
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: SizedBox(
          height: AppSpace.hairline,
          width: double.infinity,
          child: line,
        ),
      ),
    );
  }
}

/// 工具栏底边或顶边的发丝线位置
enum BarEdge { none, top, bottom }

/// 工具栏材质（导航栏、底部工具栏）：bar 底色 + 背景模糊 10。
/// 半透明档为「关」时不透明、不模糊（[AppMaterials.resolve]）。
class BarSurface extends StatelessWidget {
  const BarSurface({super.key, required this.child, this.edge = BarEdge.none});

  final Widget child;
  final BarEdge edge;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final m = tokens.materials;
    final side = BorderSide(
      color: tokens.colors.separator,
      width: AppSpace.hairline,
    );
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: m.barFill,
        border: switch (edge) {
          BarEdge.none => null,
          BarEdge.top => Border(top: side),
          BarEdge.bottom => Border(bottom: side),
        },
      ),
      child: child,
    );
    if (!m.barBlurred) return box;
    final sigma = AppMaterials.sigmaOf(m.barBlur);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: box,
      ),
    );
  }
}

/// 浮动胶囊材质（Tab 胶囊、搜索胶囊、Toast）：capsule 底色 + 模糊 12 +
/// 0.5 描边 + 浮动阴影。
///
/// 阴影只画在形状外面（Figma 默认「不在透明区域后显示阴影」），否则
/// 半透明底会被自己的阴影染灰。
class CapsuleSurface extends StatelessWidget {
  const CapsuleSurface({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
    this.shadow = true,
    this.fill,
  });

  final Widget child;
  final OutlinedBorder shape;
  final bool shadow;

  /// 覆盖底色（菜单等不透明浮层用）；null 时取胶囊材质
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final m = context.tokens.materials;
    final color = fill ?? m.capsuleFill;
    final blurred = fill == null && m.capsuleBlurred;
    Widget body = ColoredBox(color: color, child: child);
    if (blurred) {
      final sigma = AppMaterials.sigmaOf(m.capsuleBlur);
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: body,
      );
    }
    body = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: body,
    );
    body = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: shape.copyWith(
          side: BorderSide(
            color: m.capsuleStroke,
            width: AppMaterials.capsuleStrokeWidth,
          ),
        ),
      ),
      child: body,
    );
    if (!shadow) return body;
    return CustomPaint(
      painter: _OuterShadowPainter(shape, AppMaterials.floatingShadow),
      child: body,
    );
  }
}

/// 只在形状外面画阴影
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.shape, this.shadow);

  final ShapeBorder shape;
  final BoxShadow shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(shadow.blurRadius * 2 + shadow.offset.distance))
      ..addPath(path, Offset.zero);
    canvas
      ..save()
      ..clipPath(outside)
      ..drawPath(
        shape.getOuterPath(
          rect.shift(shadow.offset).inflate(shadow.spreadRadius),
        ),
        shadow.toPaint(),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.shadow != shadow;
}
