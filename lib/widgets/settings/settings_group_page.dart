import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../settings/settings_model.dart';
import '../../settings/settings_renderer.dart';

/// 通用数据驱动设置页（0.4.0 v2 分组列表）
///
/// 接收 [SettingsGroup] 列表，渲染为：组页眉（13 meta）+ 分组行 + 组页脚（13 meta）。
/// 导航栏是 v2 单行导航，内容限宽 [kReadableMaxWidth] 居中。
/// 支持通过 [highlightId] 滚动定位到指定设置项并高亮。
class SettingsGroupPage extends ConsumerStatefulWidget {
  final String title;
  final List<SettingsGroup> Function(BuildContext context) groupsBuilder;

  /// 搜索跳转时传入，用于定位高亮
  final String? highlightId;

  /// 导航栏右侧操作按钮
  final List<Widget>? actions;

  /// 内容最大宽度。为 null 时用阅读列宽。
  final double? maxContentWidth;

  /// 列表最上方、随列表滚动的内容
  final Widget? header;

  /// 固定在导航栏下方、不随列表滚动的内容（如外观页的实时预览卡）
  final Widget? pinnedHeader;

  const SettingsGroupPage({
    super.key,
    required this.title,
    required this.groupsBuilder,
    this.highlightId,
    this.actions,
    this.maxContentWidth,
    this.header,
    this.pinnedHeader,
  });

  @override
  ConsumerState<SettingsGroupPage> createState() => _SettingsGroupPageState();
}

class _SettingsGroupPageState extends ConsumerState<SettingsGroupPage> {
  final Map<String, GlobalKey> _itemKeys = {};
  String? _highlightedId;

  @override
  void initState() {
    super.initState();
    if (widget.highlightId != null) {
      _highlightedId = widget.highlightId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
  }

  void _scrollToHighlight() {
    final key = _itemKeys[_highlightedId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }
    // 2 秒后清除高亮
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groupsBuilder(context);
    final tokens = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final listView = ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.pageMargin,
        AppSpace.s,
        AppSpace.pageMargin,
        bottom + AppSpace.x32,
      ),
      // 搜索跳转定位依赖 GlobalKey.currentContext,而懒加载列表不会为视口外
      // 的条目挂载 Element,ensureVisible 拿不到 context 会静默失败。带
      // highlightId 进来时强制全量布局(设置页条目有限,代价可控)保证可达。
      scrollCacheExtent: widget.highlightId != null
          ? const ScrollCacheExtent.pixels(double.maxFinite)
          : null,
      children: [
        ?widget.header,
        for (final group in groups)
          if (_hasVisibleItems(group)) ...[
            if (group.title.isNotEmpty) _buildSectionHeader(context, group),
            _buildGroupItems(context, group),
            if (group.footer != null) _buildFooter(context, group.footer!),
            SizedBox(
              height: group.footer != null ? AppSpace.l : AppSpace.xxl,
            ),
          ],
      ],
    );

    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      appBar: AppNavBar(
        title: widget.title,
        showDivider: false,
        trailing: widget.actions ?? const [],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxContentWidth ?? kReadableMaxWidth,
          ),
          child: widget.pinnedHeader == null
              ? listView
              : Column(
                  children: [
                    widget.pinnedHeader!,
                    Expanded(child: listView),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildGroupItems(BuildContext context, SettingsGroup group) {
    // 先按 isVisible 过滤（含 SwitchModel.enabledWhen / PlatformConditionalModel）：
    // 隐藏项若留在分段卡片组里会以零高占位，顶掉组尾的大圆角。
    final effectiveItems = group.items
        .where((item) => item.isVisible(ref))
        .toList();
    if (!group.wrapInCard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < effectiveItems.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.m),
            _buildItem(context, effectiveItems[i]),
          ],
        ],
      );
    }

    return SegmentedCardGroup(
      children: [
        for (final item in effectiveItems) _buildItem(context, item),
      ],
    );
  }

  Widget _buildItem(BuildContext context, SettingsModel item) {
    final model = item is PlatformConditionalModel ? item.inner : item;
    final key = _itemKeys.putIfAbsent(model.id, () => GlobalKey());
    final isHighlighted = _highlightedId == model.id;

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 500),
      color: isHighlighted
          ? context.tokens.colors.brandPrimary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: SettingsRenderer(model: model),
    );
  }

  bool _hasVisibleItems(SettingsGroup group) {
    return group.items.any((item) => item.isVisible(ref));
  }

  /// 组页眉：13 meta，贴着分组上沿；右侧可放文字按钮
  Widget _buildSectionHeader(BuildContext context, SettingsGroup group) {
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.m,
        AppSpace.s,
        AppSpace.m,
        AppSpace.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(group.title, style: style),
            ),
          ),
          ?group.headerAction,
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, String text) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.m,
        AppSpace.s,
        AppSpace.m,
        0,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall!
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta),
      ),
    );
  }
}
