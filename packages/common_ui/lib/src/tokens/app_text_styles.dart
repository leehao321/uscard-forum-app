import 'package:flutter/material.dart';

import 'appearance_tiers.dart';

/// v2 字号：只有 22 / 17 / 13 / 11 四档，字重只有 Regular 与 Semibold（w600）。
///
/// 样式不带颜色和字体：颜色取 [AppColors]，字体由 ThemeData 统一给
/// （用户选的字体 + 中文回退）。行高用比例，跟着动态字体一起缩放。
@immutable
class AppTextStyles {
  const AppTextStyles({this.bodyHeight = 1.75});

  /// 正文行高（行高档：1.5 / 1.75 / 2.0）
  final double bodyHeight;

  factory AppTextStyles.forTier(LineHeightTier tier) =>
      AppTextStyles(bodyHeight: tier.height);

  /// 22 Semibold：阅读页主题标题、64 大头像字母
  TextStyle get title => const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 26 / 22,
  );

  /// 17 Semibold：列表标题、导航栏标题
  TextStyle get headline => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 24 / 17,
  );

  /// 17 Regular 正文、引用正文（行高随行高档）
  TextStyle get body =>
      TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: bodyHeight);

  /// 17 Regular 控件：输入框、按钮、半屏选项、菜单
  TextStyle get control => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 20 / 17,
  );

  /// 13 Regular：元信息、分类条、楼层号
  TextStyle get meta => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 16 / 13,
  );

  /// 13 Semibold：作者名、「AI 总结」
  TextStyle get metaStrong => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 16 / 13,
  );

  /// 11 Regular：标签、@handle、Tab 胶囊文字
  TextStyle get caption => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 13 / 11,
  );

  // iOS 上 SF Mono 不能按名字直接取，取不到时依次回退
  static const _monoFallback = ['Menlo', 'monospace', 'Consolas', 'Courier New'];

  /// 11 等宽：诊断里的代码块（D37）
  TextStyle get mono => const TextStyle(
    fontFamily: 'SF Mono',
    fontFamilyFallback: _monoFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 16 / 11,
  );

  /// 13 等宽：请求 URL
  TextStyle get monoUrl => const TextStyle(
    fontFamily: 'SF Mono',
    fontFamilyFallback: _monoFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 16 / 13,
  );

  /// 映射到 Material TextTheme，给残留的 Material 组件兜底（计划 §3.3）。
  ///
  /// [base] 提供字体与颜色；这里只覆盖字号、字重、行高与字间距。
  TextTheme applyTo(TextTheme base) {
    TextStyle? m(TextStyle? b, TextStyle token) =>
        (b ?? const TextStyle()).merge(token).copyWith(letterSpacing: 0);
    return base.copyWith(
      displayLarge: m(base.displayLarge, title),
      displayMedium: m(base.displayMedium, title),
      displaySmall: m(base.displaySmall, title),
      headlineLarge: m(base.headlineLarge, title),
      headlineMedium: m(base.headlineMedium, title),
      headlineSmall: m(base.headlineSmall, title),
      titleLarge: m(base.titleLarge, title),
      titleMedium: m(base.titleMedium, headline),
      titleSmall: m(base.titleSmall, metaStrong),
      bodyLarge: m(base.bodyLarge, control),
      bodyMedium: m(base.bodyMedium, control),
      bodySmall: m(base.bodySmall, meta),
      labelLarge: m(base.labelLarge, control),
      labelMedium: m(base.labelMedium, meta),
      labelSmall: m(base.labelSmall, caption),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppTextStyles && other.bodyHeight == bodyHeight;

  @override
  int get hashCode => bodyHeight.hashCode;
}
