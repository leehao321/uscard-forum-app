import 'package:flutter/painting.dart';

/// 与明暗主题无关的固定色：叠在图片、视频、遮罩上的黑白，以及不属于 11 色
/// 体系的诊断信号色。页面代码不要直接写 `Colors.*` / `Color(0x…)`，从这里取。
///
/// 值与 Material 的同名常量逐位相同，替换是等价的。
abstract final class AppFixedColors {
  static const white = Color(0xFFFFFFFF);
  static const white70 = Color(0xB3FFFFFF);
  static const white54 = Color(0x8AFFFFFF);
  static const white38 = Color(0x62FFFFFF);
  static const white24 = Color(0x3DFFFFFF);
  static const white12 = Color(0x1FFFFFFF);
  static const black = Color(0xFF000000);
  static const black87 = Color(0xDD000000);
  static const black54 = Color(0x8A000000);
  static const black45 = Color(0x73000000);
  static const black38 = Color(0x61000000);
  static const black26 = Color(0x42000000);
  static const black12 = Color(0x1F000000);

  /// 模糊遮罩的两档黑色（深色 28%，浅色 15%）
  static const scrimDark = Color(0x47000000);
  static const scrimLight = Color(0x26000000);

  /// 代码块的固定底色（Dracula / GitHub Light）
  static const codeBackgroundDark = Color(0xFF282A36);
  static const codeBackgroundLight = Color(0xFFF6F8FA);

  /// 快捷键键帽文字固定色
  static const keycapTextDark = Color(0xFFF5F5F5);
  static const keycapTextLight = Color(0xFF1F2328);

  /// 头像光晕默认金色
  static const glowGold = Color(0xFFF5BF03);

  /// 全息文字的两组渐变（深色底高饱和，浅色底降明度）
  static const holographicDark = [
    Color(0xFFFF00FF),
    Color(0xFF00FFFF),
    Color(0xFFFFFF00),
    Color(0xFFFF00FF),
    Color(0xFF00FFFF),
  ];
  static const holographicLight = [
    Color(0xFFCC00CC),
    Color(0xFF0099AA),
    Color(0xFFCC8800),
    Color(0xFFCC00CC),
    Color(0xFF0099AA),
  ];

  /// 取不到分类 / 标签颜色时的中性灰
  static const neutralGrey = Color(0xFF9E9E9E);

  /// 性能诊断悬浮层的三档信号色（好 / 注意 / 差）
  static const signalGood = Color(0xFF689F38);
  static const signalWarn = Color(0xFFFF9800);
  static const signalBad = Color(0xFFFF5252);
}

/// 四档字号（设计说明 §2.3）。没有 BuildContext 的地方、`const TextStyle`
/// 里用；有 context 时优先用 `context.tokens.text.*`。
abstract final class AppFontSize {
  static const double title = 22;
  static const double body = 17;
  static const double meta = 13;
  static const double caption = 11;
}
