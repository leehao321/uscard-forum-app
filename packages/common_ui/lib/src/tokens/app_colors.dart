import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 强调色预设（设计说明 §6、D31）：只替换 brand/primary 与 brand/button 一对
enum AccentPreset {
  /// 美卡绿（默认，11 色原值）
  meika,
  navy,
  graphite,
  wisteria;

  static AccentPreset fromName(String? name) => AccentPreset.values.firstWhere(
    (p) => p.name == name,
    orElse: () => AccentPreset.meika,
  );
}

/// v2 的 11 个颜色 token（设计说明 §2.1），浅 / 深各一套。
///
/// 页面取色只用这里的字段；ColorScheme 由它生成，只给残留的 Material
/// 组件兜底（对照见 0.4.0 计划 §3.1）。
@immutable
class AppColors {
  const AppColors({
    required this.brandPrimary,
    required this.brandButton,
    required this.onBrandButton,
    required this.textPrimary,
    required this.textMeta,
    required this.textDestructive,
    required this.surfacePage,
    required this.surfaceGrouped,
    required this.surfaceElevated,
    required this.separator,
    required this.quoteRule,
    required this.avatarFill,
  });

  /// 选中态、链接、新回复
  final Color brandPrimary;

  /// 主按钮填充
  final Color brandButton;

  /// 主按钮上的文字与图标
  final Color onBrandButton;

  /// 标题、正文
  final Color textPrimary;

  /// 元信息、次要文字
  final Color textMeta;

  /// 破坏性操作
  final Color textDestructive;

  /// 页面、列表、阅读页背景
  final Color surfacePage;

  /// 分组面板、代码块、表头、AI 卡片、深色半屏
  final Color surfaceGrouped;

  /// 半屏内输入框、悬浮控件
  final Color surfaceElevated;

  /// 0.5 发丝分隔线
  final Color separator;

  /// 引用左侧竖线
  final Color quoteRule;

  /// 字母头像底色、次按钮底、开关关闭态
  final Color avatarFill;

  static const light = AppColors(
    brandPrimary: Color(0xFF173E31),
    brandButton: Color(0xFF2E6F55),
    onBrandButton: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1C1C1E),
    textMeta: Color(0xFF636366),
    textDestructive: Color(0xFFD70015),
    surfacePage: Color(0xFFFFFFFF),
    surfaceGrouped: Color(0xFFF2F2F7),
    surfaceElevated: Color(0xFFF2F2F7),
    separator: Color(0xFFC6C6C8),
    quoteRule: Color(0xFFC7C7CC),
    avatarFill: Color(0xFFE5E5EA),
  );

  static const dark = AppColors(
    brandPrimary: Color(0xFF86C5A4),
    brandButton: Color(0xFF2E6F55),
    onBrandButton: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textMeta: Color(0xFF98989F),
    textDestructive: Color(0xFFFF453A),
    surfacePage: Color(0xFF000000),
    surfaceGrouped: Color(0xFF1C1C1E),
    surfaceElevated: Color(0xFF2C2C2E),
    separator: Color(0xFF38383A),
    quoteRule: Color(0xFF48484A),
    avatarFill: Color(0xFF3A3A3C),
  );

  /// 强调色预设的 (浅 primary, 深 primary, button)
  static const _accents = <AccentPreset, (Color, Color, Color)>{
    AccentPreset.navy: (Color(0xFF1F3A5F), Color(0xFF8FB3E0), Color(0xFF2F5A8A)),
    AccentPreset.graphite: (
      Color(0xFF3A3A3C),
      Color(0xFFC7C7CC),
      Color(0xFF48484A),
    ),
    AccentPreset.wisteria: (
      Color(0xFF4B3B6B),
      Color(0xFFB9A6E0),
      Color(0xFF5E4B8A),
    ),
  };

  /// 按明暗与强调色取一套颜色
  static AppColors resolve(Brightness brightness, AccentPreset accent) {
    final base = brightness == Brightness.dark ? dark : light;
    final pair = _accents[accent];
    if (pair == null) return base;
    final (lightPrimary, darkPrimary, button) = pair;
    return base.copyWith(
      brandPrimary: brightness == Brightness.dark ? darkPrimary : lightPrimary,
      brandButton: button,
    );
  }

  AppColors copyWith({
    Color? brandPrimary,
    Color? brandButton,
    Color? onBrandButton,
    Color? textPrimary,
    Color? textMeta,
    Color? textDestructive,
    Color? surfacePage,
    Color? surfaceGrouped,
    Color? surfaceElevated,
    Color? separator,
    Color? quoteRule,
    Color? avatarFill,
  }) => AppColors(
    brandPrimary: brandPrimary ?? this.brandPrimary,
    brandButton: brandButton ?? this.brandButton,
    onBrandButton: onBrandButton ?? this.onBrandButton,
    textPrimary: textPrimary ?? this.textPrimary,
    textMeta: textMeta ?? this.textMeta,
    textDestructive: textDestructive ?? this.textDestructive,
    surfacePage: surfacePage ?? this.surfacePage,
    surfaceGrouped: surfaceGrouped ?? this.surfaceGrouped,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    separator: separator ?? this.separator,
    quoteRule: quoteRule ?? this.quoteRule,
    avatarFill: avatarFill ?? this.avatarFill,
  );

  static AppColors lerp(AppColors a, AppColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return AppColors(
      brandPrimary: l(a.brandPrimary, b.brandPrimary),
      brandButton: l(a.brandButton, b.brandButton),
      onBrandButton: l(a.onBrandButton, b.onBrandButton),
      textPrimary: l(a.textPrimary, b.textPrimary),
      textMeta: l(a.textMeta, b.textMeta),
      textDestructive: l(a.textDestructive, b.textDestructive),
      surfacePage: l(a.surfacePage, b.surfacePage),
      surfaceGrouped: l(a.surfaceGrouped, b.surfaceGrouped),
      surfaceElevated: l(a.surfaceElevated, b.surfaceElevated),
      separator: l(a.separator, b.separator),
      quoteRule: l(a.quoteRule, b.quoteRule),
      avatarFill: l(a.avatarFill, b.avatarFill),
    );
  }

  List<Color> get _all => [
    brandPrimary,
    brandButton,
    onBrandButton,
    textPrimary,
    textMeta,
    textDestructive,
    surfacePage,
    surfaceGrouped,
    surfaceElevated,
    separator,
    quoteRule,
    avatarFill,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppColors) return false;
    final a = _all;
    final b = other._all;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_all);

  /// WCAG 2.x 对比度（1–21），测试里验证文字可读性用
  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static double _relativeLuminance(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }
}
