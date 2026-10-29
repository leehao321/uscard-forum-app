import 'package:common_ui/common_ui.dart' show AppSheetShellStyle;
import 'package:flutter/material.dart';
import 'package:m3e_ui/m3e_ui.dart' show SegmentedCardGroupStyle;

import 'design_tokens.dart';

/// iOS 列表行前导区最小宽度（图标 22–24 居中放在 28 宽里）
const double _kListLeadingWidth = 28;

/// 平台自适应层:在 [base] 上叠加设计 token 扩展与 iOS 专属组件主题。
///
/// - 所有平台:注册 [AppDesignTokens]。
/// - 仅 iOS([platform] == [TargetPlatform.iOS]):AppBar 居中、ListTile 行高与
///   字阶、Dialog 圆角与字阶,以及 m3e_ui [SegmentedCardGroupStyle]
///   (inset-grouped)与 common_ui [AppSheetShellStyle](弹框外壳)。
/// 非 iOS 除 token 扩展外保持 [base] 原样。
///
/// light/dark 两个 ThemeData 必须各调用一次(ThemeData.lerp 对单边缺失的
/// extension 不插值而是瞬时并入),因此本函数对 [scheme] 的明暗无分支差异。
///
/// 全局 textTheme 不改(布局风险);组件级文字样式 = 字阶 token 叠在
/// [base] 的字体(用户字体 + 可选 [fontFamilyFallback])之上 ——
/// ListTile/AppBar/Dialog 的标题样式会整体替换 DefaultTextStyle,
/// 不带上字体就会丢掉用户选的字体与中文 fallback。
ThemeData applyAppAdaptiveLayer(
  ThemeData base, {
  required ColorScheme scheme,
  required TargetPlatform platform,
  AppDensity density = AppDensity.standard,
  AppRadiusTier radiusTier = AppRadiusTier.medium,
  List<String>? fontFamilyFallback,
}) {
  final tokens = AppDesignTokens.resolve(
    platform: platform,
    scheme: scheme,
    density: density,
    radius: radiusTier,
  );
  final extensions = [...base.extensions.values, tokens];

  if (platform != TargetPlatform.iOS) {
    return base.copyWith(extensions: extensions);
  }

  // 字体底:取 textTheme 已解析好的 family(含用户字体选择),不带字号字重
  final bodyFont = base.textTheme.bodyLarge;
  final fontBase = TextStyle(
    fontFamily: bodyFont?.fontFamily,
    fontFamilyFallback: fontFamilyFallback ?? bodyFont?.fontFamilyFallback,
  );
  TextStyle styled(TextStyle token, Color color) =>
      fontBase.merge(token).copyWith(color: color);

  extensions.addAll([
    // 单元格底色暂沿用卡片色：groupedCell 要和页面底色 groupedBackground
    // 成对使用（浅色下 groupedCell 是纯白，放在现有的 surface 页面上分组
    // 边界几乎看不见；透明背景模式下还会变成不透明块）。页面底色在主框架
    // 那一期统一换，届时再在这里填 cellColor。
    SegmentedCardGroupStyle(
      insetGrouped: true,
      radius: tokens.radiusM,
      separatorIndent: tokens.space4,
      // 带前导图标的行：内边距 + 前导最小宽度 + 图标到文字的间距 = 文字起点
      leadingSeparatorIndent: tokens.space4 + _kListLeadingWidth + tokens.space3,
      separatorColor: scheme.outlineVariant,
    ),
    AppSheetShellStyle(
      topRadius: tokens.radiusSheet,
      titleStyle: tokens.typeScale.headline,
    ),
  ]);

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: true,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: styled(tokens.typeScale.headline, scheme.onSurface),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      minTileHeight: tokens.rowMinHeight,
      contentPadding: EdgeInsets.symmetric(horizontal: tokens.space4),
      titleTextStyle: styled(tokens.typeScale.body, scheme.onSurface),
      subtitleTextStyle: styled(tokens.typeScale.footnote, scheme.onSurfaceVariant),
      horizontalTitleGap: tokens.space3,
      minLeadingWidth: _kListLeadingWidth,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusL),
      ),
      titleTextStyle: styled(tokens.typeScale.headline, scheme.onSurface),
      contentTextStyle: styled(
        tokens.typeScale.subheadline,
        scheme.onSurfaceVariant,
      ),
    ),
    extensions: extensions,
  );
}
