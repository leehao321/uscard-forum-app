import 'package:flutter/widgets.dart';

/// 系统动态字体 × 外观字号档（0.4.0 计划 §8）。
///
/// 保留系统 scaler 的非线性曲线（Android 14+），只在结果上再乘档位；
/// 最终倍数夹在 [minScale]–[maxScale] 之间。
@immutable
class TieredTextScaler extends TextScaler {
  const TieredTextScaler(this.base, this.factor);

  static const double minScale = 0.8;
  static const double maxScale = 3.2;

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => (base.scale(fontSize) * factor).clamp(
    fontSize * minScale,
    fontSize * maxScale,
  );

  @Deprecated('Use scale() instead.')
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is TieredTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);

  @override
  String toString() => 'TieredTextScaler($base × $factor)';
}

/// 把子树的 textScaler 换成「最近的 MediaQuery 的 scaler × [factor]」
class TieredTextScaling extends StatelessWidget {
  const TieredTextScaling({super.key, required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 已经套过一层时只换档位，不重复相乘
    final system = switch (media.textScaler) {
      TieredTextScaler(:final base) => base,
      final scaler => scaler,
    };
    return MediaQuery(
      data: media.copyWith(textScaler: TieredTextScaler(system, factor)),
      child: child,
    );
  }
}
