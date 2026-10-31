import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';
import 'app_menu.dart';

/// 长按浮起（楼层长按等）：遮罩 32% + 背景模糊 10，被长按的内容浮成
/// r12 的卡片，菜单（260 宽）贴在卡片下方 8；下方放不下时把卡片往上推，
/// 卡片太高时只露出能放下的部分（设计说明 §4，楼层长按画板）。
Future<T?> showLiftedContextMenu<T>({
  required BuildContext context,
  required Rect sourceRect,
  required WidgetBuilder liftedBuilder,
  required List<List<AppMenuItem<T>>> sections,
  double menuWidth = AppSize.contextMenuWidth,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  HapticFeedback.mediumImpact();
  return navigator.push(
    _LiftedMenuRoute<T>(
      sourceRect: sourceRect,
      liftedBuilder: liftedBuilder,
      sections: sections,
      menuWidth: menuWidth,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      menuLabel: MaterialLocalizations.of(context).popupMenuLabel,
    ),
  );
}

/// 给子组件加上「长按浮起 + 上下文菜单」。浮起卡片里重新构建一份
/// [child]，所以 child 不能依赖只在原位置才有的状态（输入焦点等）。
class LiftedContextMenu<T> extends StatelessWidget {
  const LiftedContextMenu({
    super.key,
    required this.child,
    required this.sectionsBuilder,
    this.onSelected,
    this.enabled = true,
    this.liftedBuilder,
  });

  final Widget child;
  final List<List<AppMenuItem<T>>> Function(BuildContext context)
  sectionsBuilder;
  final ValueChanged<T>? onSelected;
  final bool enabled;

  /// 浮起卡片里显示的内容；默认就是 [child]
  final WidgetBuilder? liftedBuilder;

  Future<void> open(BuildContext context) async {
    final value = await showLiftedContextMenu<T>(
      context: context,
      sourceRect: globalRectOf(context),
      liftedBuilder: liftedBuilder ?? (_) => child,
      sections: sectionsBuilder(context),
    );
    if (value != null) onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Builder(
      builder: (itemContext) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => open(itemContext),
        child: child,
      ),
    );
  }
}

class _LiftedMenuRoute<T> extends PopupRoute<T> {
  _LiftedMenuRoute({
    required this.sourceRect,
    required this.liftedBuilder,
    required this.sections,
    required this.menuWidth,
    required this.capturedThemes,
    required this.barrierLabel,
    required this.menuLabel,
  });

  final Rect sourceRect;
  final WidgetBuilder liftedBuilder;
  final List<List<AppMenuItem<T>>> sections;
  final double menuWidth;
  final CapturedThemes capturedThemes;
  final String menuLabel;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => AppMaterials.scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    return AnimatedBuilder(
      animation: animation!,
      builder: (context, child) {
        final sigma = AppMaterials.sigmaOf(10) * animation!.value;
        if (sigma <= 0.01) return child!;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      },
      child: barrier,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: menuLabel,
        child: _LiftedMenuBody<T>(
          animation: animation,
          sourceRect: sourceRect,
          liftedBuilder: liftedBuilder,
          menu: AppMenuPanel<T>(
            sections: sections,
            width: menuWidth,
            onSelected: (item) {
              Navigator.of(context).pop(item.value);
              if (item.onTap != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => item.onTap!(),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _LiftedMenuBody<T> extends StatelessWidget {
  const _LiftedMenuBody({
    required this.animation,
    required this.sourceRect,
    required this.liftedBuilder,
    required this.menu,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final WidgetBuilder liftedBuilder;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    const margin = AppSpace.pageMargin;
    const gap = AppSpace.s;

    // 一屏放得下卡片 + 菜单时卡片原位不动；放不下时卡片往上挪，再不行
    // 就截短（见 _LiftedLayoutDelegate）
    final top = padding.top + margin;
    final bottom = size.height - padding.bottom - margin;
    final cardWidth = math.min(
      sourceRect.width,
      size.width - padding.horizontal - margin,
    );
    return _LiftedLayout(
      sourceRect: sourceRect,
      top: top,
      bottom: bottom,
      gap: gap,
      animation: animation,
      card: SizedBox(
        width: cardWidth,
        child: Material(
          color: tokens.colors.surfacePage,
          borderRadius: BorderRadius.circular(tokens.radius.card),
          clipBehavior: Clip.antiAlias,
          // 卡片可能被截短：内容按原高度排版，多出的部分裁掉
          child: IgnorePointer(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: liftedBuilder(context),
            ),
          ),
        ),
      ),
      menu: FadeTransition(opacity: animation, child: menu),
    );
  }
}

/// 两个子组件：卡片（0）和菜单（1）。卡片从原位置动画到目标位置。
class _LiftedLayout extends StatelessWidget {
  const _LiftedLayout({
    required this.sourceRect,
    required this.top,
    required this.bottom,
    required this.gap,
    required this.animation,
    required this.card,
    required this.menu,
  });

  final Rect sourceRect;
  final double top;
  final double bottom;
  final double gap;
  final Animation<double> animation;
  final Widget card;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) => CustomMultiChildLayout(
        delegate: _LiftedLayoutDelegate(
          sourceRect: sourceRect,
          top: top,
          bottom: bottom,
          gap: gap,
          t: curved.value,
          pageMargin: AppSpace.pageMargin,
        ),
        children: [
          LayoutId(
            id: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(context.tokens.radius.card),
                boxShadow: [
                  BoxShadow(
                    color: AppMaterials.floatingShadow.color.withValues(
                      alpha: AppMaterials.floatingShadow.color.a * curved.value,
                    ),
                    blurRadius: AppMaterials.floatingShadow.blurRadius,
                    offset: AppMaterials.floatingShadow.offset,
                  ),
                ],
              ),
              child: card,
            ),
          ),
          LayoutId(id: 1, child: menu),
        ],
      ),
    );
  }
}

class _LiftedLayoutDelegate extends MultiChildLayoutDelegate {
  _LiftedLayoutDelegate({
    required this.sourceRect,
    required this.top,
    required this.bottom,
    required this.gap,
    required this.t,
    required this.pageMargin,
  });

  final Rect sourceRect;
  final double top;
  final double bottom;
  final double gap;
  final double t;
  final double pageMargin;

  @override
  void performLayout(Size size) {
    final menuSize = layoutChild(1, BoxConstraints.loose(size));
    final available = bottom - top;
    // 卡片最多占到「可用高 − 菜单 − 间距」，至少留 88（两行正文）
    final maxCard = math.max(88.0, available - menuSize.height - gap);
    final cardSize = layoutChild(
      0,
      BoxConstraints(
        maxWidth: sourceRect.width,
        maxHeight: math.min(sourceRect.height, maxCard),
      ),
    );

    // 目标位置：菜单始终在卡片下方（楼层长按画板、iOS 上下文菜单同样）。
    // 卡片尽量待在原位；下方放不下菜单时把卡片往上推，卡片已被截短到
    // 「可用高 − 菜单 − 间距」，所以总能放下。
    final cardTop = math.max(
      top,
      math.min(
        sourceRect.top,
        bottom - menuSize.height - gap - cardSize.height,
      ),
    );
    final menuTop = cardTop + cardSize.height + gap;

    final cardLeft = sourceRect.left
        .clamp(
          pageMargin,
          math.max(pageMargin, size.width - pageMargin - cardSize.width),
        )
        .toDouble();
    final animatedTop = sourceRect.top + (cardTop - sourceRect.top) * t;
    final animatedLeft = sourceRect.left + (cardLeft - sourceRect.left) * t;
    positionChild(0, Offset(animatedLeft, animatedTop));

    // 菜单左缘对齐卡片左缘，超出右边距就往左收
    final menuLeft = cardLeft
        .clamp(
          pageMargin,
          math.max(pageMargin, size.width - pageMargin - menuSize.width),
        )
        .toDouble();
    positionChild(1, Offset(menuLeft, menuTop));
  }

  @override
  bool shouldRelayout(_LiftedLayoutDelegate oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.sourceRect != sourceRect ||
      oldDelegate.top != top ||
      oldDelegate.bottom != bottom;
}
