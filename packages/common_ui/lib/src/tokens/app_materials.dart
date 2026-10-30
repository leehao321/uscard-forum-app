import 'package:flutter/widgets.dart';

import 'app_colors.dart';
import 'appearance_tiers.dart';

/// v2 稿内材质（设计说明 §2.2）：工具栏、浮动胶囊、遮罩、阴影。
///
/// 模糊值是设计稿的模糊半径；`ImageFilter.blur` 取 sigma = 半径 / 2
/// （[sigmaOf]）。半透明档「关」时填充不透明、不模糊；「强」时
/// 半透明的填充再降 0.1 透明度（本来就不透明的不变）。
@immutable
class AppMaterials {
  const AppMaterials({
    required this.barFill,
    required this.barBlur,
    required this.capsuleFill,
    required this.capsuleBlur,
    required this.capsuleStroke,
    required this.sheetFill,
  });

  /// 底部工具栏底
  final Color barFill;

  /// 底部工具栏模糊半径（0 = 不模糊）
  final double barBlur;

  /// 浮动胶囊底（Tab、搜索）
  final Color capsuleFill;

  /// 浮动胶囊模糊半径（0 = 不模糊）
  final double capsuleBlur;

  /// 浮动胶囊 0.5 描边色
  final Color capsuleStroke;

  /// 半屏底
  final Color sheetFill;

  /// 浮动胶囊描边宽
  static const double capsuleStrokeWidth = 0.5;

  /// 浮动胶囊阴影；菜单、Toast 也用
  static const floatingShadow = BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 4),
    blurRadius: 18,
  );

  /// 半屏遮罩
  static const scrim = Color(0x52000000);

  /// 滑块拇指阴影
  static const thumbShadow = BoxShadow(
    color: Color(0x2E000000),
    offset: Offset(0, 2),
    blurRadius: 6,
  );

  /// 表格固定列投影（0.4.0 暂时用不到，计划 P4）
  static const tableShadow = BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(4, 0),
    blurRadius: 8,
  );

  /// 设计稿模糊半径 → ImageFilter.blur 的 sigma
  static double sigmaOf(double radius) => radius / 2;

  bool get barBlurred => barBlur > 0;
  bool get capsuleBlurred => capsuleBlur > 0;

  static AppMaterials resolve(
    Brightness brightness,
    AppColors colors,
    TranslucencyTier tier,
  ) {
    final dark = brightness == Brightness.dark;
    final sheetFill = dark ? colors.surfaceGrouped : colors.surfacePage;
    // 胶囊深色本来就是不透明的 #1C1C1E（surface/grouped）
    final capsuleOpaque = dark ? colors.surfaceGrouped : colors.surfacePage;
    final capsuleStroke = dark
        ? const Color(0x24FFFFFF)
        : const Color(0xE6FFFFFF);

    if (tier == TranslucencyTier.off) {
      return AppMaterials(
        barFill: colors.surfacePage,
        barBlur: 0,
        capsuleFill: capsuleOpaque,
        capsuleBlur: 0,
        capsuleStroke: capsuleStroke,
        sheetFill: sheetFill,
      );
    }

    final reduce = tier == TranslucencyTier.strong ? 0.1 : 0.0;
    Color fade(Color c) =>
        c.a >= 1 ? c : c.withValues(alpha: (c.a - reduce).clamp(0.0, 1.0));
    final bar = dark ? const Color(0xF0000000) : const Color(0xF0F9F9F9);
    final capsule = dark ? capsuleOpaque : const Color(0x9EFFFFFF);
    return AppMaterials(
      barFill: fade(bar),
      barBlur: 10,
      capsuleFill: fade(capsule),
      capsuleBlur: 12,
      capsuleStroke: capsuleStroke,
      sheetFill: sheetFill,
    );
  }

  static AppMaterials lerp(AppMaterials a, AppMaterials b, double t) =>
      AppMaterials(
        barFill: Color.lerp(a.barFill, b.barFill, t)!,
        barBlur: a.barBlur + (b.barBlur - a.barBlur) * t,
        capsuleFill: Color.lerp(a.capsuleFill, b.capsuleFill, t)!,
        capsuleBlur: a.capsuleBlur + (b.capsuleBlur - a.capsuleBlur) * t,
        capsuleStroke: Color.lerp(a.capsuleStroke, b.capsuleStroke, t)!,
        sheetFill: Color.lerp(a.sheetFill, b.sheetFill, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AppMaterials &&
      other.barFill == barFill &&
      other.barBlur == barBlur &&
      other.capsuleFill == capsuleFill &&
      other.capsuleBlur == capsuleBlur &&
      other.capsuleStroke == capsuleStroke &&
      other.sheetFill == sheetFill;

  @override
  int get hashCode => Object.hash(
    barFill,
    barBlur,
    capsuleFill,
    capsuleBlur,
    capsuleStroke,
    sheetFill,
  );
}
