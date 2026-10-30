import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_materials.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';
import 'appearance_tiers.dart';

/// v2 设计 token 汇总（ThemeExtension）。页面只通过 `context.tokens`
/// 取值，不写裸数字（0.4.0 计划 §3）。
///
/// 浅色、深色两个 ThemeData 都要注册（ThemeData.lerp 对单边缺失的
/// extension 不插值而是瞬时并入）。同样输入解析出的实例相等，主题
/// 重建时 AnimatedTheme 不会空跑整树插值。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.accent,
    required this.tiers,
    required this.colors,
    required this.text,
    required this.radius,
    required this.materials,
  });

  factory AppTokens.resolve({
    required Brightness brightness,
    AccentPreset accent = AccentPreset.meika,
    AppearanceTiers tiers = const AppearanceTiers(),
  }) {
    final colors = AppColors.resolve(brightness, accent);
    return AppTokens(
      brightness: brightness,
      accent: accent,
      tiers: tiers,
      colors: colors,
      text: AppTextStyles.forTier(tiers.lineHeight),
      radius: AppRadius.forTier(tiers.radius),
      materials: AppMaterials.resolve(brightness, colors, tiers.translucency),
    );
  }

  final Brightness brightness;
  final AccentPreset accent;
  final AppearanceTiers tiers;
  final AppColors colors;
  final AppTextStyles text;
  final AppRadius radius;
  final AppMaterials materials;

  /// 列表行上下内边距（密度档 8 / 12 / 16）
  double get rowPadV => tiers.density.rowPadV;

  /// 主题里没注册时按当前明暗就地解析（测试或独立子树里也能用）
  static AppTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTokens>() ??
        AppTokens.resolve(brightness: theme.brightness);
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    AccentPreset? accent,
    AppearanceTiers? tiers,
    AppColors? colors,
    AppTextStyles? text,
    AppRadius? radius,
    AppMaterials? materials,
  }) => AppTokens(
    brightness: brightness ?? this.brightness,
    accent: accent ?? this.accent,
    tiers: tiers ?? this.tiers,
    colors: colors ?? this.colors,
    text: text ?? this.text,
    radius: radius ?? this.radius,
    materials: materials ?? this.materials,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    // 档位与字号是离散值，过半切换；颜色和材质平滑过渡
    final end = t < 0.5 ? this : other;
    return AppTokens(
      brightness: end.brightness,
      accent: end.accent,
      tiers: end.tiers,
      colors: AppColors.lerp(colors, other.colors, t),
      text: end.text,
      radius: end.radius,
      materials: AppMaterials.lerp(materials, other.materials, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppTokens &&
      other.brightness == brightness &&
      other.accent == accent &&
      other.tiers == tiers &&
      other.colors == colors &&
      other.text == text &&
      other.radius == radius &&
      other.materials == materials;

  @override
  int get hashCode =>
      Object.hash(brightness, accent, tiers, colors, text, radius, materials);
}

extension AppTokensContext on BuildContext {
  /// `context.tokens`：当前主题的 v2 token
  AppTokens get tokens => AppTokens.of(this);
}
