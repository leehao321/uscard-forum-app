import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart' show M3eFlags, SegmentedCardGroupStyle;

/// v2 的 11 色映射到 Material ColorScheme，只给残留的 Material 组件兜底
/// （对照见 0.4.0 计划 §3.1）。页面取色用 `context.tokens.colors`。
ColorScheme appColorScheme(AppColors c, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final onPrimary = dark ? AppFixedColors.black : AppFixedColors.white;
  return ColorScheme(
    brightness: brightness,
    primary: c.brandPrimary,
    onPrimary: onPrimary,
    primaryContainer: c.brandButton,
    onPrimaryContainer: c.onBrandButton,
    secondary: c.brandPrimary,
    onSecondary: onPrimary,
    secondaryContainer: c.avatarFill,
    onSecondaryContainer: c.textPrimary,
    tertiary: c.brandPrimary,
    onTertiary: onPrimary,
    tertiaryContainer: c.avatarFill,
    onTertiaryContainer: c.textPrimary,
    error: c.textDestructive,
    onError: AppFixedColors.white,
    errorContainer: c.surfaceGrouped,
    onErrorContainer: c.textDestructive,
    surface: c.surfacePage,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textMeta,
    surfaceDim: c.surfaceGrouped,
    surfaceBright: c.surfaceElevated,
    surfaceContainerLowest: c.surfacePage,
    surfaceContainerLow: c.surfaceGrouped,
    surfaceContainer: c.surfaceGrouped,
    surfaceContainerHigh: c.surfaceElevated,
    surfaceContainerHighest: c.surfaceElevated,
    outline: c.quoteRule,
    outlineVariant: c.separator,
    shadow: AppFixedColors.black,
    scrim: AppFixedColors.black,
    // Toast 自己画，不用 inverseSurface；这里给个不刺眼的兜底
    inverseSurface: c.textPrimary,
    onInverseSurface: c.surfacePage,
    inversePrimary: c.brandPrimary,
    surfaceTint: Colors.transparent,
  );
}

/// 应用主题：全平台一套 v2（计划 P2），浅色 / 深色各调用一次。
///
/// [fontFamily] 为 null 时走系统字体（iOS 上是 SF + PingFang）；组件级
/// 文字样式会整体替换 DefaultTextStyle，所以都要带上字体与中文回退。
/// 布局尺寸（导航栏高度、列表边距等）这一期不动，只换颜色、字号、
/// 圆角和材质。
ThemeData buildAppTheme({
  required Brightness brightness,
  required TargetPlatform platform,
  String? fontFamily,
  List<String>? fontFamilyFallback,
  AccentPreset accent = AccentPreset.meika,
  AppearanceTiers tiers = const AppearanceTiers(),
  String? bodyFontFamily,
  PageTransitionsTheme? pageTransitionsTheme,
}) {
  final tokens = AppTokens.resolve(
    brightness: brightness,
    accent: accent,
    tiers: tiers,
    bodyFontFamily: bodyFontFamily,
  );
  final c = tokens.colors;
  final t = tokens.text;
  final r = tokens.radius;
  final scheme = appColorScheme(c, brightness);

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    platform: platform,
    fontFamily: fontFamily,
    pageTransitionsTheme: pageTransitionsTheme,
  );
  final textTheme = t
      .applyTo(base.textTheme)
      .apply(fontFamilyFallback: fontFamilyFallback);
  final primaryTextTheme = t
      .applyTo(base.primaryTextTheme)
      .apply(fontFamilyFallback: fontFamilyFallback);

  // 组件级样式：字号 token + 字体（用户选择 + 中文回退）+ 颜色
  final fontBase = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );
  TextStyle styled(TextStyle token, Color color) =>
      fontBase.merge(token).copyWith(color: color);

  // 按钮最小高就是 44，不再让 Material 额外补到 48 的点按区
  final secondaryButton = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, AppSize.hit)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    textStyle: WidgetStatePropertyAll(fontBase.merge(t.control)),
    backgroundColor: WidgetStatePropertyAll(c.avatarFill),
    foregroundColor: _DisabledOr(c.textMeta, c.textPrimary),
    iconColor: _DisabledOr(c.textMeta, c.textPrimary),
  );

  final menuSide = brightness == Brightness.light
      ? BorderSide(color: c.separator, width: AppSpace.hairline)
      : BorderSide.none;

  return base.copyWith(
    // iOS 上 Switch.adaptive 默认丢掉 Material 开关主题、用系统绿；v2 的
    // 开关是 brand/primary（设计说明 §4），全平台沿用下面的 switchTheme
    adaptations: const [_KeepSwitchTheme()],
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    scaffoldBackgroundColor: c.surfacePage,
    canvasColor: c.surfacePage,
    dividerColor: c.separator,
    iconTheme: IconThemeData(color: c.textPrimary, size: AppSize.iconL),
    primaryIconTheme: IconThemeData(
      color: scheme.onPrimary,
      size: AppSize.iconL,
    ),
    cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
      primaryColor: c.brandPrimary,
      scaffoldBackgroundColor: c.surfacePage,
      barBackgroundColor: tokens.materials.barFill,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.brandPrimary,
      selectionColor: c.brandPrimary.withValues(alpha: 0.25),
      selectionHandleColor: c.brandPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surfacePage,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: styled(t.headline, c.textPrimary),
      iconTheme: IconThemeData(color: c.textPrimary, size: AppSize.iconL),
      actionsIconTheme: IconThemeData(
        color: c.textPrimary,
        size: AppSize.iconL,
      ),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: AppSize.row48,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
      horizontalTitleGap: AppSpace.m,
      minLeadingWidth: AppSize.iconM,
      titleTextStyle: styled(t.control, c.textPrimary),
      subtitleTextStyle: styled(t.meta, c.textMeta),
      leadingAndTrailingTextStyle: styled(t.control, c.textMeta),
      iconColor: c.textMeta,
    ),
    dividerTheme: DividerThemeData(
      color: c.separator,
      thickness: AppSpace.hairline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.materials.sheetFill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.sheet),
      ),
      titleTextStyle: styled(t.headline, c.textPrimary),
      contentTextStyle: styled(t.meta, c.textMeta),
      barrierColor: AppMaterials.scrim,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.materials.sheetFill,
      modalBackgroundColor: tokens.materials.sheetFill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: AppMaterials.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(r.sheet)),
      ),
      dragHandleColor: c.quoteRule,
      dragHandleSize: const Size(
        AppSize.sheetHandleWidth,
        AppSize.sheetHandleHeight,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppFixedColors.white),
      trackColor: _SelectedOr(c.brandPrimary, c.avatarFill),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.brandPrimary,
      inactiveTrackColor: c.avatarFill,
      thumbColor: AppFixedColors.white,
      overlayColor: c.brandPrimary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.brandPrimary,
      linearTrackColor: c.avatarFill,
      circularTrackColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceGrouped,
      selectedColor: c.surfaceGrouped,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: styled(t.meta, c.textPrimary),
      secondaryLabelStyle: styled(t.meta, c.brandPrimary),
      checkmarkColor: c.brandPrimary,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.surfaceGrouped,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.card),
      ),
      margin: EdgeInsets.zero,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: brightness == Brightness.light ? c.surfacePage : c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: AppFixedColors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.card),
        side: menuSide,
      ),
      textStyle: styled(t.control, c.textPrimary),
      labelTextStyle: WidgetStatePropertyAll(styled(t.control, c.textPrimary)),
      iconColor: c.textPrimary,
      iconSize: AppSize.iconM,
      menuPadding: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceElevated,
      contentTextStyle: styled(t.meta, c.textPrimary),
      actionTextColor: c.brandPrimary,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: c.surfaceGrouped,
      hintStyle: styled(t.control, c.textMeta),
      focusColor: c.brandPrimary,
    ),
    // 主按钮 brand/button 白字；次按钮（OutlinedButton / ElevatedButton，
    // 以及 FilledButton + AppButtonStyles.secondary）avatar/fill 底、
    // text/primary 字；文字按钮 brand/primary（设计说明 §4）。
    // FilledButton.tonal 和 FilledButton 共用这一份主题，所以不用 tonal。
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, AppSize.hit)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(fontBase.merge(t.control)),
        backgroundColor: _DisabledOr(c.avatarFill, c.brandButton),
        foregroundColor: _DisabledOr(c.textMeta, c.onBrandButton),
        iconColor: _DisabledOr(c.textMeta, c.onBrandButton),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
    elevatedButtonTheme: ElevatedButtonThemeData(style: secondaryButton),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(AppSize.hit, AppSize.hit),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(fontBase.merge(t.control)),
        foregroundColor: _DisabledOr(c.textMeta, c.brandPrimary),
        iconColor: _DisabledOr(c.textMeta, c.brandPrimary),
      ),
    ),
    extensions: [
      tokens,
      // M3E 风格（按压形变、M3E 进度条等）在 v2 里去掉；组件删除前先关掉
      const M3eFlags(enabled: false),
      SegmentedCardGroupStyle(
        insetGrouped: true,
        radius: r.card,
        // 行 pad 0 12、组内图标 20：无图标时分隔线对齐 12，有图标时对齐
        // 文字起点 12 + 20 + 12 = 44（设计说明 §4「分组列表」）
        separatorIndent: AppSpace.m,
        leadingSeparatorIndent: AppSpace.m + AppSize.iconM + AppSpace.m,
        separatorColor: c.separator,
        // 不写死底色：取 cardTheme.color，半屏里换成 surface/elevated
        // （AppSheetScaffold.innerTheme）
      ),
      AppSheetShellStyle(topRadius: r.sheet, titleStyle: t.control),
    ],
  );
}

/// 选中 / 未选中两个取值的 WidgetStateProperty。
///
/// 不用 `WidgetStateProperty.resolveWith`：闭包每次新建都不相等，会让每次
/// 装配出的 ThemeData 都不相等，MaterialApp 的 AnimatedTheme 因此在每次
/// 重建时都空跑一段整树主题插值动画。
@immutable
class _SelectedOr<T> implements WidgetStateProperty<T> {
  const _SelectedOr(this.selected, this.other);

  final T selected;
  final T other;

  @override
  T resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) ? selected : other;

  @override
  bool operator ==(Object other) =>
      other is _SelectedOr<T> &&
      other.selected == selected &&
      other.other == this.other;

  @override
  int get hashCode => Object.hash(selected, other);
}

/// 不可用 / 可用两个取值的 WidgetStateProperty（理由同 [_SelectedOr]）
@immutable
class _DisabledOr<T> implements WidgetStateProperty<T> {
  const _DisabledOr(this.disabled, this.other);

  final T disabled;
  final T other;

  @override
  T resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled) ? disabled : other;

  @override
  bool operator ==(Object other) =>
      other is _DisabledOr<T> &&
      other.disabled == disabled &&
      other.other == this.other;

  @override
  int get hashCode => Object.hash(disabled, other);
}

/// 所有平台都直接用主题里的 [SwitchThemeData]（框架默认在 iOS / macOS 上
/// 换成空主题，开关就成了系统绿）。
class _KeepSwitchTheme extends Adaptation<SwitchThemeData> {
  const _KeepSwitchTheme();

  @override
  SwitchThemeData adapt(ThemeData theme, SwitchThemeData defaultValue) =>
      defaultValue;
}
