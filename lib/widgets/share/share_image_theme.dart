import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';

/// 分享图片某个样式的取色（全部来自 token，见 [ShareImageTheme.palette]）。
@immutable
class ShareImagePalette {
  const ShareImagePalette({
    required this.bg,
    required this.card,
    required this.text,
    required this.meta,
    required this.rule,
    required this.isDark,
  });

  /// 整张图的底色（预览卡片 / 色板圆点的颜色）
  final Color bg;

  /// 正文区块底色
  final Color card;

  /// 标题、正文
  final Color text;

  /// 次要文字（作者 @handle、链接）
  final Color meta;

  /// 分隔线、头像描边
  final Color rule;

  /// 渲染内容用暗色 Theme（正文里的链接、代码块等派生色按它取）
  final bool isDark;
}

/// 分享图片的 5 种样式（Figma「补充 · 话题阅读」分享图片组，设计说明 §6）。
///
/// 分享图是一张导出图片，样式不跟随 App 的深浅色：每个样式固定取某一套
/// 模式的 token——经典 = 浅色 surface/grouped，深色 = 深色 surface/grouped，
/// 纯黑 = 深色 surface/page，绿野 = brand/button 底 + text/on-brand 字，
/// 蓝调 = share/蓝调（[AppSharePalette.blue]，浅深同值），文字按浅色模式。
///
/// 枚举顺序即色板顺序，也是偏好里存的索引。
enum ShareImageTheme {
  classic(nameKey: 'share_themeClassic'),
  dark(nameKey: 'share_themeDark'),
  black(nameKey: 'share_themeBlack'),
  green(nameKey: 'share_themeGreen'),
  blue(nameKey: 'share_themeBlue');

  const ShareImageTheme({required this.nameKey});

  final String nameKey;

  String get name {
    final l10n = S.current;
    switch (nameKey) {
      case 'share_themeClassic':
        return l10n.share_themeClassic;
      case 'share_themeDark':
        return l10n.share_themeDark;
      case 'share_themeBlack':
        return l10n.share_themeBlack;
      case 'share_themeGreen':
        return l10n.share_themeGreen;
      case 'share_themeBlue':
        return l10n.share_themeBlue;
      default:
        return nameKey;
    }
  }

  /// 这个样式用到的全部颜色
  ShareImagePalette get palette {
    const light = AppColors.light;
    const dark = AppColors.dark;
    switch (this) {
      case ShareImageTheme.classic:
        return ShareImagePalette(
          bg: light.surfaceGrouped,
          card: light.surfacePage,
          text: light.textPrimary,
          meta: light.textMeta,
          rule: light.separator,
          isDark: false,
        );
      case ShareImageTheme.dark:
        return ShareImagePalette(
          bg: dark.surfaceGrouped,
          card: dark.surfaceElevated,
          text: dark.textPrimary,
          meta: dark.textMeta,
          rule: dark.separator,
          isDark: true,
        );
      case ShareImageTheme.black:
        return ShareImagePalette(
          bg: dark.surfacePage,
          card: dark.surfaceGrouped,
          text: dark.textPrimary,
          meta: dark.textMeta,
          rule: dark.separator,
          isDark: true,
        );
      case ShareImageTheme.green:
        // 绿野：brand/button 底 + text/on-brand 字；区块和次要文字是 on-brand 的透明度
        return ShareImagePalette(
          bg: light.brandButton,
          card: Color.alphaBlend(
            light.onBrandButton.withValues(alpha: 0.12),
            light.brandButton,
          ),
          text: light.onBrandButton,
          meta: light.onBrandButton.withValues(alpha: 0.7),
          rule: light.onBrandButton.withValues(alpha: 0.24),
          isDark: true,
        );
      case ShareImageTheme.blue:
        return ShareImagePalette(
          bg: AppSharePalette.blue,
          card: light.surfacePage,
          text: light.textPrimary,
          meta: light.textMeta,
          rule: light.separator,
          isDark: false,
        );
    }
  }

  Color get bgColor => palette.bg;
  Color get cardColor => palette.card;
  bool get isDark => palette.isDark;

  /// 根据索引获取样式（越界取经典）
  static ShareImageTheme fromIndex(int index) {
    if (index >= 0 && index < values.length) {
      return values[index];
    }
    return classic;
  }

  /// 旧版有 6 种样式（经典 / 纯白 / 深色 / 纯黑 / 蓝调 / 绿色调），存的
  /// 是那时的索引；这里换算成现在的索引。纯白并入经典。
  static int fromLegacyIndex(int legacy) {
    switch (legacy) {
      case 0:
      case 1:
        return classic.index;
      case 2:
        return dark.index;
      case 3:
        return black.index;
      case 4:
        return blue.index;
      case 5:
        return green.index;
    }
    return classic.index;
  }

  /// 预览里渲染分享图的 Theme：亮度跟样式走，文字色取样式里的 token；
  /// 字体沿用 [ambient]（用户选的字体 + 中文回退）
  ThemeData buildThemeData(ThemeData ambient) {
    final p = palette;
    final base = ambient.textTheme.bodyMedium;
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final tokens = AppTokens.resolve(brightness: brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.colors.brandButton,
      brightness: brightness,
    ).copyWith(surface: p.bg, onSurface: p.text, onSurfaceVariant: p.meta);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: base?.fontFamily,
      fontFamilyFallback: base?.fontFamilyFallback,
      colorScheme: scheme,
      extensions: [tokens],
    );
  }
}

/// 色板：一排圆点 + 11 号样式名，选中的圆点外加 2pt brand/primary 环
/// （Figma 分享图片组：圆点 32、选中 36，标签 11）。
class ShareThemeSwatches extends StatelessWidget {
  const ShareThemeSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ShareImageTheme selected;
  final ValueChanged<ShareImageTheme> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        for (final t in ShareImageTheme.values)
          _Swatch(
            theme: t,
            selected: t == selected,
            onTap: () => onSelected(t),
            tokens: tokens,
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.theme,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final ShareImageTheme theme;
  final bool selected;
  final VoidCallback onTap;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final c = tokens.colors;
    final palette = theme.palette;
    final label = theme.name;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSize.hit,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 圆点区固定 36 高：选中的 36（含环）和未选中的 32 底部对齐不抖动
              SizedBox(
                height: 36,
                child: Center(
                  child: Container(
                    key: ValueKey('share_swatch_${theme.nameKey}'),
                    width: selected ? 36 : 32,
                    height: selected ? 36 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: c.brandPrimary, width: 2)
                          : Border.all(
                              color: c.separator,
                              width: AppSpace.hairline,
                            ),
                    ),
                    // 选中时圆点与环之间留 2 的空隙
                    padding: EdgeInsets.all(selected ? 2 : 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.bg,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.merge(tokens.text.caption)
                    .copyWith(
                      color: selected ? c.brandPrimary : c.textMeta,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
