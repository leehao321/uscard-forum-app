import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';
import 'app_icon_button.dart';
import 'readable.dart';
import 'surfaces.dart';

/// 框架类控件的字号封顶（计划 §8）：导航栏标题、Tab 胶囊、分类条等。
const double kChromeMaxTextScale = 1.3;

/// v2 导航栏：44 高（不含状态栏），左右两个等宽槽（单行页 70、首页 90），
/// 标题 17 Semibold 居中、单行省略。底色铺满整宽，控件按阅读列对齐。
///
/// 当作 [Scaffold.appBar] 用：自己处理状态栏高度和状态栏文字颜色。
class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  const AppNavBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.trailing = const [],
    this.slotWidth = 70,
    this.showDivider = false,
    this.translucent = false,
    this.automaticallyImplyLeading = true,
    this.onBack,
  });

  final String? title;

  /// 自定义标题（首页的标题菜单等），优先于 [title]
  final Widget? titleWidget;

  /// 左槽；null 且能返回时放返回按钮
  final Widget? leading;

  /// 右槽，从左到右排列
  final List<Widget> trailing;

  /// 左右槽宽：单行导航 70，首页（带发帖入口）90
  final double slotWidth;

  /// 底部 0.5 分隔线
  final bool showDivider;

  /// 半透明工具栏材质（内容在下面滚动的页）；false 时用页面底色
  final bool translucent;

  final bool automaticallyImplyLeading;

  /// 返回按钮的动作；默认 `Navigator.maybePop`
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(AppSize.navBar);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final route = ModalRoute.of(context);
    final canPop = route?.impliesAppBarDismissal ?? false;
    final leading =
        this.leading ??
        (automaticallyImplyLeading && (canPop || onBack != null)
            ? AppBackButton(onPressed: onBack)
            : null);

    // 设计是 pad 0 20 0 16、两侧各一个 [slotWidth] 宽的槽；16 / 20 是图标
    // 的视觉边，44 热区向外多出 10，所以内边距减 10、槽宽加 10
    final insets = readableInsets(context, gutter: 0);
    const hitOverhang = (AppSize.hit - AppSize.iconL) / 2;
    // 右槽放得下全部按钮：每个 44 热区一个；放 2 个以上时两侧槽一起加宽，
    // 标题仍然居中
    // 相邻图标的视觉间距 24（图标 24、热区 44，并排只有 20），每两个之间补 4
    final trailingWidth = trailing.isEmpty
        ? 0.0
        : trailing.length * AppSize.hit + (trailing.length - 1) * 4.0;
    final slot = math.max(slotWidth + hitOverhang, trailingWidth);

    final titleText =
        titleWidget ??
        (title == null
            ? null
            : Semantics(
                header: true,
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleMedium!
                      .merge(tokens.text.headline)
                      .copyWith(color: tokens.colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ));

    Widget bar = SizedBox(
      height: AppSize.navBar,
      child: Padding(
        padding: EdgeInsets.only(
          left: insets.left + 16 - hitOverhang,
          right: insets.right + AppSpace.pageMargin - hitOverhang,
        ),
        child: NavigationToolbar(
          middleSpacing: 0,
          leading: SizedBox(
            width: slot,
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
          middle: titleText,
          trailing: SizedBox(
            width: slot,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < trailing.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    trailing[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    bar = MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: bar,
    );

    final content = Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: bar,
    );
    final edge = showDivider ? BarEdge.bottom : BarEdge.none;
    final Widget surface = translucent
        ? BarSurface(edge: edge, child: content)
        : DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.surfacePage,
              border: showDivider
                  ? Border(
                      bottom: BorderSide(
                        color: tokens.colors.separator,
                        width: AppSpace.hairline,
                      ),
                    )
                  : null,
            ),
            child: content,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Material(type: MaterialType.transparency, child: surface),
    );
  }
}

/// 导航栏返回按钮：chevron-left 24，朗读「返回」
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: AppIcons.back,
    semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: onPressed ?? () => Navigator.maybePop(context),
  );
}

/// 关闭按钮：x，默认 22（半屏头行），朗读「关闭」
class AppCloseButton extends StatelessWidget {
  const AppCloseButton({super.key, this.onPressed, this.size = 22});

  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: AppIcons.close,
    size: size,
    semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
    onPressed: onPressed ?? () => Navigator.maybePop(context),
  );
}
