import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart' show M3eFlags, SegmentedCardGroupStyle;

/// v2 的 11 色映射到 Material ColorScheme，只给残留的 Material 组件兜底
/// （对照见 0.4.0 计划 §3.1）。页面取色用 `context.tokens.colors`。
ColorScheme appColorScheme(AppColors c, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final onPrimary = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
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
    onError: const Color(0xFFFFFFFF),
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
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    // Toast 自己画，不用 inverseSurface；这里给个不刺眼的兜底
    inverseSurface: c.textPrimary,
    onInverseSurface: c.surfacePage,
    inversePrimary: c.brandPrimary,
    surfaceTint: const Color(0x00000000),
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
  PageTransitionsTheme? pageTransitionsTheme,
}) {
  final tokens = AppTokens.resolve(
    brightness: brightness,
    accent: accent,
    tiers: tiers,
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
    primaryIconTheme: IconThemeData(color: scheme.onPrimary, size: AppSize.iconL),
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
      surfaceTintColor: const Color(0x00000000),
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
      surfaceTintColor: const Color(0x00000000),
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
      surfaceTintColor: const Color(0x00000000),
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
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      trackColor: _SelectedOr(c.brandPrimary, c.avatarFill),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.brandPrimary,
      inactiveTrackColor: c.avatarFill,
      thumbColor: const Color(0xFFFFFFFF),
      overlayColor: c.brandPrimary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.brandPrimary,
      linearTrackColor: c.avatarFill,
      circularTrackColor: const Color(0x00000000),
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
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.card)),
      margin: EdgeInsets.zero,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: brightness == Brightness.light
          ? c.surfacePage
          : c.surfaceElevated,
      surfaceTintColor: const Color(0x00000000),
      elevation: 3,
      shadowColor: const Color(0xFF000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.card),
        side: menuSide,
      ),
      textStyle: styled(t.control, c.textPrimary),
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
    // 颜色跟 ColorScheme（primary）；主 / 次按钮分色在共享组件里做（M2）
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, AppSize.hit)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(fontBase.merge(t.control)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(fontBase.merge(t.control)),
      ),
    ),
    extensions: [
      tokens,
      // M3E 风格（按压形变、M3E 进度条等）在 v2 里去掉；组件删除前先关掉
      const M3eFlags(enabled: false),
      SegmentedCardGroupStyle(
        insetGrouped: true,
        radius: r.card,
        // 行 pad 0 12：无图标时分隔线对齐 12，有图标时对齐文字起点。
        // 设计是 20 的图标 → 44；现有行还是全局 24 的图标 → 48，
        // M2 分组列表换皮改用 20 图标时一起改成 44。
        separatorIndent: AppSpace.m,
        leadingSeparatorIndent: AppSpace.m + AppSize.iconL + AppSpace.m,
        separatorColor: c.separator,
        cellColor: c.surfaceGrouped,
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

/// 所有平台都直接用主题里的 [SwitchThemeData]（框架默认在 iOS / macOS 上
/// 换成空主题，开关就成了系统绿）。
class _KeepSwitchTheme extends Adaptation<SwitchThemeData> {
  const _KeepSwitchTheme();

  @override
  SwitchThemeData adapt(ThemeData theme, SwitchThemeData defaultValue) =>
      defaultValue;
}
