import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 密度档位(第二阶段接设置;第一阶段只用 [standard])。
enum AppDensity { compact, standard, comfortable }

/// 圆角档位(第二阶段接设置;第一阶段只用 [medium])。
enum AppRadiusTier { small, medium, large }

/// 字阶:对应 iOS HIG 的 Dynamic Type 十级。
///
/// 只含字号/字重/行高,**不含颜色与 fontFamily**:用户选的字体与中文
/// fallback 由主题装配层按 textTheme 补上,这里保持纯排版意图。
@immutable
class AppTypeScale {
  final TextStyle largeTitle;
  final TextStyle title1;
  final TextStyle title2;
  final TextStyle title3;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle callout;
  final TextStyle subheadline;
  final TextStyle footnote;
  final TextStyle caption;

  const AppTypeScale({
    required this.largeTitle,
    required this.title1,
    required this.title2,
    required this.title3,
    required this.headline,
    required this.body,
    required this.callout,
    required this.subheadline,
    required this.footnote,
    required this.caption,
  });

  /// iOS HIG 字阶:34/28/22/20/17/17/16/15/13/12。
  static const AppTypeScale ios = AppTypeScale(
    largeTitle: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.2),
    title1: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
    title2: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
    title3: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
    headline: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
    body: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.35),
    callout: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.3),
    subheadline: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.3),
    footnote: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3),
    caption: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.3),
  );

  /// 非 iOS:取 Material textTheme 里最接近的档位(M3 默认字号:
  /// headlineLarge 32 / headlineMedium 28 / headlineSmall 24 / titleLarge 22 /
  /// titleMedium 16 / bodyLarge 16 / bodyMedium 14 / bodySmall 12 /
  /// labelSmall 11)。M3 档位比 iOS 稀疏,callout 与 subheadline 取同一档。
  static const AppTypeScale material = AppTypeScale(
    largeTitle: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, height: 1.25),
    title1: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, height: 1.29),
    title2: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.33),
    title3: TextStyle(fontSize: 22, fontWeight: FontWeight.w400, height: 1.27),
    headline: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.5),
    body: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
    callout: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.43),
    subheadline: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.43),
    footnote: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.33),
    caption: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.45),
  );

  AppTypeScale copyWith({
    TextStyle? largeTitle,
    TextStyle? title1,
    TextStyle? title2,
    TextStyle? title3,
    TextStyle? headline,
    TextStyle? body,
    TextStyle? callout,
    TextStyle? subheadline,
    TextStyle? footnote,
    TextStyle? caption,
  }) => AppTypeScale(
    largeTitle: largeTitle ?? this.largeTitle,
    title1: title1 ?? this.title1,
    title2: title2 ?? this.title2,
    title3: title3 ?? this.title3,
    headline: headline ?? this.headline,
    body: body ?? this.body,
    callout: callout ?? this.callout,
    subheadline: subheadline ?? this.subheadline,
    footnote: footnote ?? this.footnote,
    caption: caption ?? this.caption,
  );

  static AppTypeScale lerp(AppTypeScale a, AppTypeScale b, double t) {
    TextStyle l(TextStyle x, TextStyle y) => TextStyle.lerp(x, y, t) ?? y;
    return AppTypeScale(
      largeTitle: l(a.largeTitle, b.largeTitle),
      title1: l(a.title1, b.title1),
      title2: l(a.title2, b.title2),
      title3: l(a.title3, b.title3),
      headline: l(a.headline, b.headline),
      body: l(a.body, b.body),
      callout: l(a.callout, b.callout),
      subheadline: l(a.subheadline, b.subheadline),
      footnote: l(a.footnote, b.footnote),
      caption: l(a.caption, b.caption),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppTypeScale &&
      other.largeTitle == largeTitle &&
      other.title1 == title1 &&
      other.title2 == title2 &&
      other.title3 == title3 &&
      other.headline == headline &&
      other.body == body &&
      other.callout == callout &&
      other.subheadline == subheadline &&
      other.footnote == footnote &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(largeTitle, title1, title2, title3, headline, body, callout, subheadline, footnote, caption);
}

/// 动效曲线集合。
@immutable
class AppMotionCurves {
  final Curve standard;
  final Curve enter;
  final Curve exit;
  final Curve emphasized;

  const AppMotionCurves({
    this.standard = Curves.easeInOutCubic,
    this.enter = Curves.easeOutCubic,
    this.exit = Curves.easeInCubic,
    this.emphasized = Curves.fastEaseInToSlowEaseOut,
  });

  AppMotionCurves copyWith({
    Curve? standard,
    Curve? enter,
    Curve? exit,
    Curve? emphasized,
  }) => AppMotionCurves(
    standard: standard ?? this.standard,
    enter: enter ?? this.enter,
    exit: exit ?? this.exit,
    emphasized: emphasized ?? this.emphasized,
  );

  @override
  bool operator ==(Object other) =>
      other is AppMotionCurves &&
      other.standard == standard &&
      other.enter == enter &&
      other.exit == exit &&
      other.emphasized == emphasized;

  @override
  int get hashCode => Object.hash(standard, enter, exit, emphasized);
}

/// 动效时长与曲线,全平台一致。时长与曲线同名(standard)故曲线收进 [curves]。
@immutable
class AppMotion {
  final Duration fast;
  final Duration standard;
  final Duration slow;
  final AppMotionCurves curves;

  const AppMotion({
    this.fast = const Duration(milliseconds: 150),
    this.standard = const Duration(milliseconds: 250),
    this.slow = const Duration(milliseconds: 350),
    this.curves = const AppMotionCurves(),
  });

  AppMotion copyWith({
    Duration? fast,
    Duration? standard,
    Duration? slow,
    AppMotionCurves? curves,
  }) => AppMotion(
    fast: fast ?? this.fast,
    standard: standard ?? this.standard,
    slow: slow ?? this.slow,
    curves: curves ?? this.curves,
  );

  /// 时长/曲线无法有意义地插值:t>=0.5 取 [b]。
  static AppMotion lerp(AppMotion a, AppMotion b, double t) => t >= 0.5 ? b : a;

  @override
  bool operator ==(Object other) =>
      other is AppMotion &&
      other.fast == fast &&
      other.standard == standard &&
      other.slow == slow &&
      other.curves == curves;

  @override
  int get hashCode => Object.hash(fast, standard, slow, curves);
}

/// 一档模糊材质:高斯模糊 sigma + 表面不透明度。
@immutable
class AppBlurLevel {
  final double sigma;
  final double surfaceAlpha;

  const AppBlurLevel({required this.sigma, required this.surfaceAlpha});

  static AppBlurLevel lerp(AppBlurLevel a, AppBlurLevel b, double t) =>
      AppBlurLevel(
        sigma: lerpDouble(a.sigma, b.sigma, t)!,
        surfaceAlpha: lerpDouble(a.surfaceAlpha, b.surfaceAlpha, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AppBlurLevel &&
      other.sigma == sigma &&
      other.surfaceAlpha == surfaceAlpha;

  @override
  int get hashCode => Object.hash(sigma, surfaceAlpha);
}

/// 材质与层级:三档模糊 + 悬浮阴影。
///
/// 第一阶段只定义,不接到任何组件上。
@immutable
class AppMaterials {
  final AppBlurLevel thin;
  final AppBlurLevel regular;
  final AppBlurLevel thick;

  /// 悬浮表面(浮层/菜单/悬浮条)的阴影。
  final BoxShadow floatingShadow;

  /// 普通卡片是否带阴影(iOS 平面卡片,不带)。
  final bool cardShadows;

  const AppMaterials({
    this.thin = const AppBlurLevel(sigma: 10, surfaceAlpha: 0.72),
    this.regular = const AppBlurLevel(sigma: 20, surfaceAlpha: 0.80),
    this.thick = const AppBlurLevel(sigma: 30, surfaceAlpha: 0.88),
    required this.floatingShadow,
    required this.cardShadows,
  });

  /// [dark] 时阴影更重(深色底上 0.08 几乎看不见)。
  factory AppMaterials.resolve({
    required TargetPlatform platform,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    return AppMaterials(
      floatingShadow: BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
      // 应用的 cardTheme 各平台都是 elevation 0（无阴影）
      cardShadows: false,
    );
  }

  AppMaterials copyWith({
    AppBlurLevel? thin,
    AppBlurLevel? regular,
    AppBlurLevel? thick,
    BoxShadow? floatingShadow,
    bool? cardShadows,
  }) => AppMaterials(
    thin: thin ?? this.thin,
    regular: regular ?? this.regular,
    thick: thick ?? this.thick,
    floatingShadow: floatingShadow ?? this.floatingShadow,
    cardShadows: cardShadows ?? this.cardShadows,
  );

  static AppMaterials lerp(AppMaterials a, AppMaterials b, double t) =>
      AppMaterials(
        thin: AppBlurLevel.lerp(a.thin, b.thin, t),
        regular: AppBlurLevel.lerp(a.regular, b.regular, t),
        thick: AppBlurLevel.lerp(a.thick, b.thick, t),
        floatingShadow: BoxShadow.lerp(a.floatingShadow, b.floatingShadow, t)!,
        cardShadows: t < 0.5 ? a.cardShadows : b.cardShadows,
      );

  @override
  bool operator ==(Object other) =>
      other is AppMaterials &&
      other.thin == thin &&
      other.regular == regular &&
      other.thick == thick &&
      other.floatingShadow == floatingShadow &&
      other.cardShadows == cardShadows;

  @override
  int get hashCode => Object.hash(thin, regular, thick, floatingShadow, cardShadows);
}

/// 语义色角色:只从 [ColorScheme] + 明暗派生,不引入任何新色值,
/// 因此品牌色/调色板/中性/纯黑等开关继续沿现有主题链路生效。
@immutable
class AppColorRoles {
  /// 主文字。
  final Color label;

  /// 次级文字。
  final Color secondaryLabel;

  /// 三级文字(占位/禁用感)。
  final Color tertiaryLabel;

  /// 分隔线。
  final Color separator;

  /// 强调/可交互着色。
  final Color tint;

  /// 分组列表的页面底色。
  final Color groupedBackground;

  /// 分组列表的单元格底色(叠在 [groupedBackground] 之上)。
  final Color groupedCell;

  const AppColorRoles({
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.tint,
    required this.groupedBackground,
    required this.groupedCell,
  });

  factory AppColorRoles.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return AppColorRoles(
      label: scheme.onSurface,
      secondaryLabel: scheme.onSurfaceVariant,
      tertiaryLabel: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      separator: scheme.outlineVariant,
      tint: scheme.primary,
      groupedBackground: isDark ? scheme.surface : scheme.surfaceContainer,
      groupedCell: isDark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLowest,
    );
  }

  AppColorRoles copyWith({
    Color? label,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? separator,
    Color? tint,
    Color? groupedBackground,
    Color? groupedCell,
  }) => AppColorRoles(
    label: label ?? this.label,
    secondaryLabel: secondaryLabel ?? this.secondaryLabel,
    tertiaryLabel: tertiaryLabel ?? this.tertiaryLabel,
    separator: separator ?? this.separator,
    tint: tint ?? this.tint,
    groupedBackground: groupedBackground ?? this.groupedBackground,
    groupedCell: groupedCell ?? this.groupedCell,
  );

  static AppColorRoles lerp(AppColorRoles a, AppColorRoles b, double t) =>
      AppColorRoles(
        label: Color.lerp(a.label, b.label, t)!,
        secondaryLabel: Color.lerp(a.secondaryLabel, b.secondaryLabel, t)!,
        tertiaryLabel: Color.lerp(a.tertiaryLabel, b.tertiaryLabel, t)!,
        separator: Color.lerp(a.separator, b.separator, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        groupedBackground:
            Color.lerp(a.groupedBackground, b.groupedBackground, t)!,
        groupedCell: Color.lerp(a.groupedCell, b.groupedCell, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AppColorRoles &&
      other.label == label &&
      other.secondaryLabel == secondaryLabel &&
      other.tertiaryLabel == tertiaryLabel &&
      other.separator == separator &&
      other.tint == tint &&
      other.groupedBackground == groupedBackground &&
      other.groupedCell == groupedCell;

  @override
  int get hashCode => Object.hash(label, secondaryLabel, tertiaryLabel, separator, tint, groupedBackground, groupedCell);

  /// WCAG 2.x 对比度 (L1+0.05)/(L2+0.05),L 为相对亮度,结果 1~21。
  /// 与参数顺序无关。只看 RGB,不处理 alpha(半透明色需先和底色混合)。
  /// 第二阶段用它保证派生文字色 ≥4.5:1(AA)。
  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color c) {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  }
}

/// 全局设计 token(ThemeExtension):间距/圆角/行高/字阶/动效/材质/语义色。
///
/// 零业务依赖、无品牌值;颜色只来自传入的 [ColorScheme]。分档(密度/圆角)
/// 由 [resolve] 缩放,第二阶段只需把设置接到这两个参数。
///
/// 注意:light/dark 两个 ThemeData 必须对称注册(见 main.dart 的
/// `_buildAppTheme` 注释)。
@immutable
class AppDesignTokens extends ThemeExtension<AppDesignTokens> {
  // 间距
  final double space1;
  final double space2;
  final double space3;
  final double space4;
  final double space5;
  final double space6;

  /// 页面左右边距。第一阶段仅 iOS 适配层使用。
  final double pageMargin;

  // 圆角
  final double radiusS;
  final double radiusM;
  final double radiusL;

  /// 底部弹框顶部圆角(iOS 12)。
  final double radiusSheet;

  /// 列表行最小高度。
  final double rowMinHeight;

  /// 分隔线用发丝线(1 物理像素)而非 1 逻辑像素。
  final bool useHairlineSeparators;

  /// 字阶。不能叫 `type`:会覆盖 [ThemeExtension.type](extensions 的 key)。
  final AppTypeScale typeScale;
  final AppMotion motion;
  final AppMaterials materials;
  final AppColorRoles colors;

  const AppDesignTokens({
    required this.space1,
    required this.space2,
    required this.space3,
    required this.space4,
    required this.space5,
    required this.space6,
    required this.pageMargin,
    required this.radiusS,
    required this.radiusM,
    required this.radiusL,
    required this.radiusSheet,
    required this.rowMinHeight,
    required this.useHairlineSeparators,
    required this.typeScale,
    required this.motion,
    required this.materials,
    required this.colors,
  });

  /// 按平台 + 配色方案 + 档位解析出一套 token。
  ///
  /// 基准值(standard/medium):
  /// - iOS:圆角 6/10/14(弹框 12),行高 44,发丝线分隔;
  /// - 其他:圆角取现有 SegmentedCardGroup/卡片外观(5/12/20,弹框 20),
  ///   行高 48。
  /// 密度缩放间距 ×0.75/1/1.25(取整像素)并平移行高;圆角档 ×0.7/1/1.3(取整)。
  factory AppDesignTokens.resolve({
    required TargetPlatform platform,
    required ColorScheme scheme,
    AppDensity density = AppDensity.standard,
    AppRadiusTier radius = AppRadiusTier.medium,
  }) {
    final isIOS = platform == TargetPlatform.iOS;

    final spaceFactor = switch (density) {
      AppDensity.compact => 0.75,
      AppDensity.standard => 1.0,
      AppDensity.comfortable => 1.25,
    };
    double sp(double v) => (v * spaceFactor).roundToDouble();

    // iOS 行高 40/44/52;其他平台沿用同样的增减量(44/48/56)。
    final rowBase = isIOS ? 44.0 : 48.0;
    final rowMinHeight = switch (density) {
      AppDensity.compact => rowBase - 4,
      AppDensity.standard => rowBase,
      AppDensity.comfortable => rowBase + 8,
    };

    final radiusFactor = switch (radius) {
      AppRadiusTier.small => 0.7,
      AppRadiusTier.medium => 1.0,
      AppRadiusTier.large => 1.3,
    };
    double rd(double v) => (v * radiusFactor).roundToDouble();

    return AppDesignTokens(
      space1: sp(4),
      space2: sp(8),
      space3: sp(12),
      space4: sp(16),
      space5: sp(20),
      space6: sp(24),
      pageMargin: sp(16),
      radiusS: rd(isIOS ? 6 : 5),
      radiusM: rd(isIOS ? 10 : 12),
      radiusL: rd(isIOS ? 14 : 20),
      radiusSheet: rd(isIOS ? 12 : 20),
      rowMinHeight: rowMinHeight,
      useHairlineSeparators: isIOS,
      typeScale: isIOS ? AppTypeScale.ios : AppTypeScale.material,
      motion: const AppMotion(),
      materials: AppMaterials.resolve(
        platform: platform,
        brightness: scheme.brightness,
      ),
      colors: AppColorRoles.fromScheme(scheme),
    );
  }

  /// 取当前主题的 token;宿主未注册(裸 MaterialApp/测试)时按当前主题的
  /// 平台与配色就地解析一份,保证非空。
  static AppDesignTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppDesignTokens>() ??
        AppDesignTokens.resolve(
          platform: theme.platform,
          scheme: theme.colorScheme,
        );
  }

  @override
  AppDesignTokens copyWith({
    double? space1,
    double? space2,
    double? space3,
    double? space4,
    double? space5,
    double? space6,
    double? pageMargin,
    double? radiusS,
    double? radiusM,
    double? radiusL,
    double? radiusSheet,
    double? rowMinHeight,
    bool? useHairlineSeparators,
    AppTypeScale? typeScale,
    AppMotion? motion,
    AppMaterials? materials,
    AppColorRoles? colors,
  }) => AppDesignTokens(
    space1: space1 ?? this.space1,
    space2: space2 ?? this.space2,
    space3: space3 ?? this.space3,
    space4: space4 ?? this.space4,
    space5: space5 ?? this.space5,
    space6: space6 ?? this.space6,
    pageMargin: pageMargin ?? this.pageMargin,
    radiusS: radiusS ?? this.radiusS,
    radiusM: radiusM ?? this.radiusM,
    radiusL: radiusL ?? this.radiusL,
    radiusSheet: radiusSheet ?? this.radiusSheet,
    rowMinHeight: rowMinHeight ?? this.rowMinHeight,
    useHairlineSeparators:
        useHairlineSeparators ?? this.useHairlineSeparators,
    typeScale: typeScale ?? this.typeScale,
    motion: motion ?? this.motion,
    materials: materials ?? this.materials,
    colors: colors ?? this.colors,
  );

  @override
  AppDesignTokens lerp(ThemeExtension<AppDesignTokens>? other, double t) {
    if (other is! AppDesignTokens) return this;
    double l(double a, double b) => lerpDouble(a, b, t)!;
    return AppDesignTokens(
      space1: l(space1, other.space1),
      space2: l(space2, other.space2),
      space3: l(space3, other.space3),
      space4: l(space4, other.space4),
      space5: l(space5, other.space5),
      space6: l(space6, other.space6),
      pageMargin: l(pageMargin, other.pageMargin),
      radiusS: l(radiusS, other.radiusS),
      radiusM: l(radiusM, other.radiusM),
      radiusL: l(radiusL, other.radiusL),
      radiusSheet: l(radiusSheet, other.radiusSheet),
      rowMinHeight: l(rowMinHeight, other.rowMinHeight),
      useHairlineSeparators: t < 0.5
          ? useHairlineSeparators
          : other.useHairlineSeparators,
      typeScale: AppTypeScale.lerp(typeScale, other.typeScale, t),
      motion: AppMotion.lerp(motion, other.motion, t),
      materials: AppMaterials.lerp(materials, other.materials, t),
      colors: AppColorRoles.lerp(colors, other.colors, t),
    );
  }

  // ThemeData 每次 build 都是新实例：extension 不可比较时 MaterialApp 的
  // AnimatedTheme 会把每次重建都当成换主题，空跑一段整树 lerp 动画。
  @override
  bool operator ==(Object other) =>
      other is AppDesignTokens &&
      other.space1 == space1 &&
      other.space2 == space2 &&
      other.space3 == space3 &&
      other.space4 == space4 &&
      other.space5 == space5 &&
      other.space6 == space6 &&
      other.pageMargin == pageMargin &&
      other.radiusS == radiusS &&
      other.radiusM == radiusM &&
      other.radiusL == radiusL &&
      other.radiusSheet == radiusSheet &&
      other.rowMinHeight == rowMinHeight &&
      other.useHairlineSeparators == useHairlineSeparators &&
      other.typeScale == typeScale &&
      other.motion == motion &&
      other.materials == materials &&
      other.colors == colors;

  @override
  int get hashCode => Object.hash(
    space1,
    space2,
    space3,
    space4,
    space5,
    space6,
    pageMargin,
    radiusS,
    radiusM,
    radiusL,
    radiusSheet,
    rowMinHeight,
    useHairlineSeparators,
    typeScale,
    motion,
    materials,
    colors,
  );
}
