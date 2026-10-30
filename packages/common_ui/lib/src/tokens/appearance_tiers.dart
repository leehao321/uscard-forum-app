import 'package:flutter/foundation.dart';

/// 字号档：与系统动态字体相乘，不替换（0.4.0 计划 §8）
enum FontTier {
  small(0.88),
  standard(1.0),
  large(1.12),
  extraLarge(1.24);

  const FontTier(this.factor);

  final double factor;

  /// 旧偏好 `contentFontScale` 折算到最近的档位（计划 §3.6）
  static FontTier fromLegacyScale(double scale) {
    if (scale <= 0.94) return FontTier.small;
    if (scale <= 1.06) return FontTier.standard;
    if (scale <= 1.18) return FontTier.large;
    return FontTier.extraLarge;
  }
}

/// 行高档：只作用于正文 `body`
enum LineHeightTier {
  compact(1.5),
  standard(1.75),
  relaxed(2.0);

  const LineHeightTier(this.height);

  final double height;
}

/// 信息密度档：列表行上下内边距
enum DensityTier {
  compact(8),
  standard(12),
  comfortable(16);

  const DensityTier(this.rowPadV);

  final double rowPadV;
}

/// 圆角档：胶囊与 App 图标不受影响
enum RadiusTier {
  small(0.75),
  standard(1.0),
  large(1.25);

  const RadiusTier(this.factor);

  final double factor;
}

/// 半透明档：关 = 不透明 surface 且不模糊；强 = 透明度再降 0.1
enum TranslucencyTier { off, standard, strong }

/// 外观预设（设计说明 §6）：组合五个档位
enum AppearancePreset {
  standard,
  compact,
  comfortable,
  largeText;

  AppearanceTiers get tiers => switch (this) {
    AppearancePreset.standard => const AppearanceTiers(),
    AppearancePreset.compact => const AppearanceTiers(
      font: FontTier.small,
      lineHeight: LineHeightTier.compact,
      density: DensityTier.compact,
    ),
    AppearancePreset.comfortable => const AppearanceTiers(
      lineHeight: LineHeightTier.relaxed,
      density: DensityTier.comfortable,
    ),
    AppearancePreset.largeText => const AppearanceTiers(
      font: FontTier.extraLarge,
      lineHeight: LineHeightTier.relaxed,
    ),
  };

  /// 当前档位组合正好等于某个预设时返回它，否则是「自定义」(null)。
  /// 半透明档不属于预设，比较时不看它。
  static AppearancePreset? match(AppearanceTiers tiers) {
    final normalized = tiers.copyWith(translucency: TranslucencyTier.standard);
    for (final p in values) {
      if (p.tiers == normalized) return p;
    }
    return null;
  }
}

/// 外观 › 微调里的五个档位
@immutable
class AppearanceTiers {
  const AppearanceTiers({
    this.font = FontTier.standard,
    this.lineHeight = LineHeightTier.standard,
    this.density = DensityTier.standard,
    this.radius = RadiusTier.standard,
    this.translucency = TranslucencyTier.standard,
  });

  final FontTier font;
  final LineHeightTier lineHeight;
  final DensityTier density;
  final RadiusTier radius;
  final TranslucencyTier translucency;

  AppearanceTiers copyWith({
    FontTier? font,
    LineHeightTier? lineHeight,
    DensityTier? density,
    RadiusTier? radius,
    TranslucencyTier? translucency,
  }) => AppearanceTiers(
    font: font ?? this.font,
    lineHeight: lineHeight ?? this.lineHeight,
    density: density ?? this.density,
    radius: radius ?? this.radius,
    translucency: translucency ?? this.translucency,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceTiers &&
      other.font == font &&
      other.lineHeight == lineHeight &&
      other.density == density &&
      other.radius == radius &&
      other.translucency == translucency;

  @override
  int get hashCode =>
      Object.hash(font, lineHeight, density, radius, translucency);
}
