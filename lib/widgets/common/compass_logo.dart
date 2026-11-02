import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

/// 罗盘 logo:气泡 + 圆环为底,中间指针可绕中心转动。
///
/// 底图 `assets/logo_base.svg`(viewBox 187 192 880 880),指针
/// `assets/logo_needle.svg`(以指针中心为中心的 500x500 视窗)。
/// 两者坐标均由 `tool/gen_logo_assets.py` 生成,常量需与脚本输出保持一致。
class CompassLogo extends StatefulWidget {
  const CompassLogo({
    super.key,
    this.size = 120,
    this.spinning = true,
    this.period = const Duration(milliseconds: 2400),
  });

  final double size;

  /// 指针是否持续转动(用作加载动画);false 时指针静止在原始角度
  final bool spinning;

  /// 转一圈的时间
  final Duration period;

  // 底图 viewBox 边长,以及指针中心、指针视窗边长在底图坐标系中的位置
  static const double _viewSide = 880;
  static const double _needleSide = 500;
  static const double _needleLeft = 188.96;
  static const double _needleTop = 168.49;

  @override
  State<CompassLogo> createState() => _CompassLogoState();
}

class _CompassLogoState extends State<CompassLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: widget.period,
    vsync: this,
  );

  // 只建一次:CurvedAnimation 会给 controller 挂状态监听,每次 build 新建会越挂越多
  // easeInOut 让指针像在"找方向":加速、减速、再转
  late final CurvedAnimation _turns = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant CompassLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _svg(BuildContext context, String asset) => ScalableImageWidget.fromSISource(
    si: ScalableImageSource.fromSvg(
      DefaultAssetBundle.of(context),
      asset,
      warnF: (_) {},
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final k = s / CompassLogo._viewSide;
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          children: [
            Positioned.fill(child: _svg(context, 'assets/logo_base.svg')),
            Positioned(
              left: CompassLogo._needleLeft * k,
              top: CompassLogo._needleTop * k,
              width: CompassLogo._needleSide * k,
              height: CompassLogo._needleSide * k,
              child: RotationTransition(
                turns: _turns,
                child: _svg(context, 'assets/logo_needle.svg'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
