import 'package:flutter/material.dart';

import '../providers/app_icon_provider.dart';
import 'common/compass_logo.dart';

/// 启动页 logo:罗盘指针持续转动,同时作为加载动画。
///
/// 底层圆形光晕随指针节奏缓慢呼吸。[style] 仅为兼容旧调用保留,
/// 现在所有图标样式使用同一个 logo。
class PreheatLogo extends StatefulWidget {
  final AppIconStyle style;
  final double size;

  const PreheatLogo({super.key, required this.style, this.size = 128});

  @override
  State<PreheatLogo> createState() => _PreheatLogoState();
}

class _PreheatLogoState extends State<PreheatLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    duration: const Duration(milliseconds: 2400),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final breathe = Curves.easeInOutSine.transform(_glow.value);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(
                  alpha: 0.12 + 0.10 * breathe,
                ),
                blurRadius: 36.0 + 16.0 * breathe,
              ),
            ],
          ),
          child: child,
        );
      },
      child: CompassLogo(size: widget.size),
    );
  }
}
