import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_icon_button.dart';
import 'app_pressable.dart';
import 'surfaces.dart';

/// 菜单里的一项。[value] 是选中后 [showAppMenu] 返回的值；[onTap] 在菜单
/// 关闭后调用（两者可只用一个）。
@immutable
class AppMenuItem<T> {
  const AppMenuItem({
    required this.label,
    this.value,
    this.icon,
    this.checked = false,
    this.destructive = false,
    this.enabled = true,
    this.submenu,
    this.detail,
    this.onTap,
  });

  final String label;
  final T? value;

  /// 20 的前导图标
  final IconData? icon;

  /// 勾选态：右侧 check 20 brand
  final bool checked;

  /// 破坏性：文字和图标 text/destructive
  final bool destructive;
  final bool enabled;

  /// 子菜单：点这一项在原位换成子菜单（带返回头行）
  final List<List<AppMenuItem<T>>>? submenu;

  /// 右侧 13 meta 说明（当前值等）
  final String? detail;

  final VoidCallback? onTap;
}

/// 菜单面板（标题菜单 240 / 上下文菜单 260）：r12；浅色 page 底 + 0.5
/// separator 描边 + 浮动阴影，深色 elevated 底、无描边。项 44 高、17/20；
/// 分组之间 8 高 surface/grouped 间隔（设计说明 §4）。
class AppMenuPanel<T> extends StatefulWidget {
  const AppMenuPanel({
    super.key,
    required this.sections,
    required this.onSelected,
    this.width = AppSize.menuWidth,
    this.maxHeight,
  });

  final List<List<AppMenuItem<T>>> sections;

  /// 选中一项（非子菜单项）
  final ValueChanged<AppMenuItem<T>> onSelected;
  final double width;
  final double? maxHeight;

  @override
  State<AppMenuPanel<T>> createState() => _AppMenuPanelState<T>();
}

class _AppMenuPanelState<T> extends State<AppMenuPanel<T>> {
  /// 子菜单栈：每层是（父项, 子菜单分组）
  final _stack = <AppMenuItem<T>>[];

  List<List<AppMenuItem<T>>> get _sections =>
      _stack.isEmpty ? widget.sections : _stack.last.submenu!;

  void _tap(AppMenuItem<T> item) {
    if (item.submenu != null) {
      setState(() => _stack.add(item));
      return;
    }
    widget.onSelected(item);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final dark = tokens.brightness == Brightness.dark;
    final radius = BorderRadius.circular(tokens.radius.card);

    final children = <Widget>[];
    if (_stack.isNotEmpty) {
      children
        ..add(
          _AppMenuHeader(
            label: _stack.last.label,
            onBack: () => setState(_stack.removeLast),
          ),
        )
        ..add(_SectionGap(color: colors.surfaceGrouped));
    }
    final sections = _sections.where((s) => s.isNotEmpty).toList();
    for (var s = 0; s < sections.length; s++) {
      if (s > 0) children.add(_SectionGap(color: colors.surfaceGrouped));
      final items = sections[s];
      for (var i = 0; i < items.length; i++) {
        if (i > 0) children.add(const AppHairline());
        children.add(_AppMenuRow<T>(item: items[i], onTap: _tap));
      }
    }

    Widget body = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    if (widget.maxHeight != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: body,
      );
    }

    return Semantics(
      explicitChildNodes: true,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: dark ? colors.surfaceElevated : colors.surfacePage,
          borderRadius: radius,
          border: dark
              ? null
              : Border.all(color: colors.separator, width: AppSpace.hairline),
          boxShadow: const [AppMaterials.floatingShadow],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(type: MaterialType.transparency, child: body),
        ),
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: AppSpace.s,
      child: ColoredBox(color: color),
    ),
  );
}

class _AppMenuRow<T> extends StatelessWidget {
  const _AppMenuRow({required this.item, required this.onTap});

  final AppMenuItem<T> item;
  final ValueChanged<AppMenuItem<T>> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final color = !item.enabled
        ? colors.textMeta
        : item.destructive
        ? colors.textDestructive
        : colors.textPrimary;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return AppPressable(
      highlight: true,
      onTap: item.enabled ? () => onTap(item) : null,
      selected: item.checked ? true : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.l,
            vertical: AppSpace.s,
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: AppSize.iconM, color: color),
                const SizedBox(width: AppSpace.m),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: base.merge(tokens.text.control).copyWith(color: color),
                ),
              ),
              if (item.detail != null) ...[
                const SizedBox(width: AppSpace.s),
                Text(
                  item.detail!,
                  maxLines: 1,
                  style: base
                      .merge(tokens.text.meta)
                      .copyWith(color: colors.textMeta),
                ),
              ],
              if (item.checked) ...[
                const SizedBox(width: AppSpace.s),
                Icon(
                  AppIcons.check,
                  size: AppSize.iconM,
                  color: colors.brandPrimary,
                ),
              ] else if (item.submenu != null) ...[
                const SizedBox(width: AppSpace.s),
                Icon(
                  AppIcons.chevronRight,
                  size: AppSize.iconS,
                  color: colors.textMeta,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMenuHeader extends StatelessWidget {
  const _AppMenuHeader({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppPressable(
      highlight: true,
      onTap: onBack,
      semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.l),
          child: Row(
            children: [
              Icon(
                AppIcons.chevronLeft,
                size: AppSize.iconM,
                color: tokens.colors.textMeta,
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium!
                      .merge(tokens.text.headline)
                      .copyWith(color: tokens.colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 某个组件在屏幕上的矩形（菜单、浮起卡片的锚点）
Rect globalRectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 在 [anchor]（全局坐标）旁边弹出菜单，返回选中项的 value。
///
/// 默认放在锚点下方 4；锚点在屏幕右半边时右对齐，否则左对齐；下方放不下
/// 时翻到上方。左右至少留页边距 20。
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<List<AppMenuItem<T>>> sections,
  double width = AppSize.menuWidth,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push(
    _AppMenuRoute<T>(
      anchor: anchor,
      sections: sections,
      width: width,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      menuLabel: MaterialLocalizations.of(context).popupMenuLabel,
    ),
  );
}

/// 菜单项被选中后：先关菜单，再在下一帧调 [AppMenuItem.onTap]
void _runAfterClose(VoidCallback? onTap) {
  if (onTap == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => onTap());
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.anchor,
    required this.sections,
    required this.width,
    required this.capturedThemes,
    required this.barrierLabel,
    required this.menuLabel,
  });

  final Rect anchor;
  final List<List<AppMenuItem<T>>> sections;
  final double width;
  final CapturedThemes capturedThemes;
  final String menuLabel;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final panel = AppMenuPanel<T>(
      sections: sections,
      width: width,
      maxHeight: math.max(
        AppSize.hit * 3,
        size.height - padding.vertical - AppSpace.pageMargin * 2,
      ),
      onSelected: (item) {
        Navigator.of(context).pop(item.value);
        _runAfterClose(item.onTap);
      },
    );
    return capturedThemes.wrap(
      Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: menuLabel,
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(anchor: anchor, padding: padding),
          child: _MenuTransition(
            animation: animation,
            alignment: _MenuLayout.growAlignment(anchor, size),
            child: panel,
          ),
        ),
      ),
    );
  }
}

class _MenuTransition extends StatelessWidget {
  const _MenuTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: alignment,
        scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.padding});

  final Rect anchor;
  final EdgeInsets padding;

  static const double _gap = AppSpace.xs;

  static bool _alignRight(Rect anchor, Size size) =>
      anchor.center.dx > size.width / 2;

  /// 缩放动画从靠近锚点的那个角长出来
  static Alignment growAlignment(Rect anchor, Size size) =>
      _alignRight(anchor, size) ? Alignment.topRight : Alignment.topLeft;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = AppSpace.pageMargin;
    final minX = padding.left + margin;
    final maxX = size.width - padding.right - margin - childSize.width;
    final x = _alignRight(anchor, size)
        ? anchor.right - childSize.width
        : anchor.left;

    final minY = padding.top + margin;
    final maxY = size.height - padding.bottom - margin - childSize.height;
    var y = anchor.bottom + _gap;
    if (y > maxY) {
      // 下面放不下：翻到上面
      final above = anchor.top - _gap - childSize.height;
      y = above >= minY ? above : maxY;
    }
    return Offset(
      x.clamp(minX, math.max(minX, maxX)),
      y.clamp(minY, math.max(minY, maxY)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.padding != padding;
}

/// 带菜单的图标按钮（取代 PopupMenuButton）：点按在按钮下方弹出
/// [AppMenuPanel]，选中后回调 [onSelected]。
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.sectionsBuilder,
    this.onSelected,
    this.width = AppSize.menuWidth,
    this.color,
    this.size = AppSize.iconL,
    this.enabled = true,
  });

  final IconData icon;
  final String semanticLabel;
  final List<List<AppMenuItem<T>>> Function(BuildContext context)
  sectionsBuilder;
  final ValueChanged<T>? onSelected;
  final double width;
  final Color? color;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => AppIconButton(
        icon: icon,
        semanticLabel: semanticLabel,
        color: color,
        size: size,
        onPressed: !enabled
            ? null
            : () async {
                final value = await showAppMenu<T>(
                  context: buttonContext,
                  anchor: globalRectOf(buttonContext),
                  sections: sectionsBuilder(buttonContext),
                  width: width,
                );
                if (value != null) onSelected?.call(value);
              },
      ),
    );
  }
}
