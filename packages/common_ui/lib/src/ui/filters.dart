import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'app_nav_bar.dart' show kChromeMaxTextScale;
import 'app_pressable.dart';

/// 页内筛选 / 分类条（Components「分类条项」）：13 字 + 22×2.5 下划线，
/// 项内间距 8，项间 20，底对齐；选中 brand/primary，未选 text/meta、
/// 下划线透明。每项热区 44，可横滑；选中项变化时自动滚进可见区。
class FilterTabs extends StatefulWidget {
  const FilterTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.pageMargin),
    this.gap = AppSpace.xl,
    this.scrollable = true,
    this.dividerAfter,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;
  final double gap;
  final bool scrollable;

  /// 在这一项后面插一根 0.5×16 竖线（首页「全部 · 精彩 · 难绷」与分类之间）
  final int? dividerAfter;

  @override
  State<FilterTabs> createState() => _FilterTabsState();
}

class _FilterTabsState extends State<FilterTabs> {
  final _keys = <int, GlobalKey>{};

  GlobalKey _keyOf(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  @override
  void didUpdateWidget(FilterTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 标签变少时丢掉越界的 key，不留着没人用的 GlobalKey（L-5）
    _keys.removeWhere((index, _) => index >= widget.labels.length);
    if (oldWidget.selectedIndex != widget.selectedIndex && widget.scrollable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.selectedIndex]?.currentContext;
        if (ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(ctx)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final children = <Widget>[];
    for (var i = 0; i < widget.labels.length; i++) {
      if (i > 0) children.add(SizedBox(width: widget.gap));
      children.add(
        KeyedSubtree(
          key: _keyOf(i),
          child: FilterTabItem(
            label: widget.labels[i],
            selected: i == widget.selectedIndex,
            onTap: () => widget.onSelected(i),
          ),
        ),
      );
      if (widget.dividerAfter == i) {
        children
          ..add(SizedBox(width: widget.gap))
          ..add(
            Padding(
              // 竖线底部留 12，和文字底对齐（设计说明 §3.1）
              padding: const EdgeInsets.only(bottom: AppSpace.m),
              child: SizedBox(
                width: AppSpace.hairline,
                height: AppSpace.l,
                child: ColoredBox(color: colors.separator),
              ),
            ),
          );
      }
    }
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );
    Widget content = widget.scrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: row,
          )
        : Padding(padding: widget.padding, child: row);
    content = MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: content,
    );
    return SizedBox(height: AppSize.categoryBar, child: content);
  }
}

/// 分类条的一项（也可单独用在别处的页内筛选）
class FilterTabItem extends StatelessWidget {
  const FilterTabItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected
        ? tokens.colors.brandPrimary
        : tokens.colors.textMeta;
    return AppPressable(
      onTap: onTap,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSize.hit,
          minHeight: AppSize.categoryBar,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: color),
            ),
            const SizedBox(height: AppSpace.s),
            ExcludeSemantics(
              child: Container(
                width: 22,
                height: 2.5,
                decoration: BoxDecoration(
                  color: selected ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(tokens.radius.bar),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选胶囊：32 高（浅色 surface/grouped、深色 surface/elevated），13 字 + chevron-down 16；选中（筛选
/// 生效）时文字和图标换成 brand/primary。上下各留 6 透明热区凑足 44。
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.showChevron = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool showChevron;

  /// 文字前的图标（可选，16）
  final IconData? icon;

  /// 胶囊底色：深色用 surface/elevated（和页面 #000、半屏 #1C1C1E 都不同），浅色用 surface/grouped
  static Color _fill(AppTokens tokens) => tokens.brightness == Brightness.dark
      ? tokens.colors.surfaceElevated
      : tokens.colors.surfaceGrouped;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected
        ? tokens.colors.brandPrimary
        : tokens.colors.textPrimary;
    // 宽度至少 44：「@」「#」这类单字符的胶囊也要满足最小点击区
    final pill = Container(
      height: AppSize.floorPill,
      constraints: const BoxConstraints(minWidth: AppSize.hit),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
      decoration: ShapeDecoration(
        // 深色下半屏底（sheetFill）就是 surface/grouped，胶囊换成 elevated 才分得出来；
        // 浅色下页面和半屏都是白底，grouped 本来就够。选中时叠一层 brand 淡底 + 细描边
        color: selected
            ? Color.alphaBlend(
                tokens.colors.brandPrimary.withValues(alpha: 0.14),
                _fill(tokens),
              )
            : _fill(tokens),
        shape: StadiumBorder(
          side: selected
              ? BorderSide(
                  color: tokens.colors.brandPrimary,
                  width: AppSpace.hairline,
                )
              : BorderSide.none,
        ),
      ),
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppSize.iconS, color: color),
              const SizedBox(width: AppSpace.xs),
            ],
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: color),
            ),
            if (showChevron) ...[
              const SizedBox(width: AppSpace.xs),
              Icon(AppIcons.chevronDown, size: AppSize.iconS, color: color),
            ],
          ],
        ),
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kChromeMaxTextScale,
      child: AppPressable(
        onTap: onTap,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: (AppSize.hit - AppSize.floorPill) / 2,
          ),
          child: pill,
        ),
      ),
    );
  }
}
