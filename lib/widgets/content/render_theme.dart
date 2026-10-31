import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

/// 给正文渲染器（fluxdo_render 子模块，只能从 App 侧换皮，计划 P4）包一层
/// Theme：渲染器按 ColorScheme 取色，这里把角色映射到 v2 token。
///
/// - primary = brand/primary（链接、强调）
/// - outline = quote/rule（引用左侧竖线）
/// - outlineVariant = separator（分隔线、表格线）
/// - surfaceContainerHighest = 页面底色（引用块不加底色，只留竖线）
/// - surfaceContainerHigh = surface/grouped（行内代码、代码块、表头）
class RenderTheme extends StatelessWidget {
  const RenderTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tokens.colors;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: colors.brandPrimary,
          outline: colors.quoteRule,
          outlineVariant: colors.separator,
          // 渲染器给它叠 30% / 50% 透明度做底；取页面底色，叠上去等于没有底
          surfaceContainerHighest: colors.surfacePage,
          surfaceContainerHigh: colors.surfaceGrouped,
        ),
      ),
      child: child,
    );
  }
}
