import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 全息渐变动画文字（模拟 CSS holographic 效果）
class HolographicText extends StatefulWidget {
  final String text;
  final double fontSize;

  const HolographicText({
    super.key,
    required this.text,
    required this.fontSize,
  });

  @override
  State<HolographicText> createState() => _HolographicTextState();
}

class _HolographicTextState extends State<HolographicText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 深色背景：高饱和亮色；浅色背景：降低明度，保证可读性
  static const _darkColors = AppFixedColors.holographicDark;
  static const _lightColors = AppFixedColors.holographicLight;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? _darkColors : _lightColors;

    // RepaintBoundary 隔离 60fps 的 ShaderMask 重建,
    // 避免持续连累整个 post header / list item 重绘。
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final offset = _controller.value;
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: colors,
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                begin: Alignment(-1.0 + offset * 4, -1.0 + offset * 4),
                end: Alignment(1.0 + offset * 4, 1.0 + offset * 4),
                tileMode: TileMode.mirror,
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcIn,
            child: child!,
          );
        },
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
