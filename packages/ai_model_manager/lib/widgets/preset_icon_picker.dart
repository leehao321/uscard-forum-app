import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/ai_l10n.dart';
import 'preset_icon.dart';

/// 快捷词图标选择（补充稿 44 / 45）：
/// - 默认显示 [kPresetIconGrid] 的 18 个 Lucide 图标（6 列），上方一行「已选：图标名」；
/// - 组页眉右侧的放大镜打开搜索框，按英文名搜索全部 Lucide 图标，选中项描边高亮；
/// - 不再提供 Emoji。
///
/// 输出是图标名（kebab-case，如 `heart`）。旧数据里的 Material 图标名会按对应的
/// Lucide 图标高亮；旧数据里的 emoji 只在「已选」行显示，网格里没有对应项。
class PresetIconPicker extends StatefulWidget {
  const PresetIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<PresetIconPicker> createState() => _PresetIconPickerState();
}

class _PresetIconPickerState extends State<PresetIconPicker> {
  final _controller = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _query => _controller.text.trim();

  /// 搜索词非空：网格换成搜索结果，「已选」行收起
  bool get _showingResults => _searching && _query.isNotEmpty;

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodySmall!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final l10n = AiL10n.current;
    final names = _showingResults
        ? searchLucideIconNames(_query)
        : kPresetIconGrid;
    final selectedName = presetLucideName(widget.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 组页眉（稿里 48 高）：「图标」13 meta + 右侧放大镜（44 热区，图标贴右边）
        SizedBox(
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                bottom: AppSpace.s,
                child: Text(l10n.quickPromptsIcon, style: meta),
              ),
              Positioned(
                right: -(AppSize.hit - AppSize.iconM) / 2,
                bottom: 0,
                child: AppIconButton(
                  icon: AppIcons.search,
                  size: AppSize.iconM,
                  color: _searching ? colors.brandPrimary : colors.textMeta,
                  semanticLabel: l10n.quickPromptsIconSearch,
                  selected: _searching,
                  onPressed: _toggleSearch,
                ),
              ),
            ],
          ),
        ),
        if (_searching) ...[
          AppFilledField(
            controller: _controller,
            hintText: l10n.quickPromptsIconSearchHint,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            prefix: Icon(
              AppIcons.search,
              size: AppSize.iconM,
              color: colors.textMeta,
            ),
            suffix: _query.isEmpty
                ? null
                : AppIconButton(
                    icon: AppIcons.cancelCircle,
                    size: AppSize.iconM,
                    color: colors.textMeta,
                    semanticLabel: l10n.quickPromptsIconSearchClear,
                    onPressed: () => setState(_controller.clear),
                  ),
          ),
          const SizedBox(height: AppSpace.m),
        ],
        if (!_showingResults)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s),
            child: SizedBox(
              height: 40 - AppSpace.s,
              child: Row(
                children: [
                  PresetIcon(
                    iconRaw: widget.value,
                    size: AppSize.iconL,
                    color: colors.brandPrimary,
                  ),
                  const SizedBox(width: AppSpace.s),
                  Expanded(
                    child: Text(
                      l10n.quickPromptsIconSelected(
                        selectedName ?? widget.value,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_showingResults && names.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
            child: Text(
              l10n.quickPromptsIconNoResult,
              textAlign: TextAlign.center,
              style: meta,
            ),
          )
        else
          _IconGrid(
            names: names,
            selected: selectedName,
            onSelected: widget.onChanged,
          ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s),
            child: Text(l10n.quickPromptsIconSearchNote, style: meta),
          ),
      ],
    );
  }
}

/// 6 列图标网格：格子随宽度等分（稿宽 398 时 56，格间 12 / 行间 8）
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.names,
    required this.selected,
    required this.onSelected,
  });

  final List<String> names;
  final String? selected;
  final ValueChanged<String> onSelected;

  static const int columns = 6;
  static const double columnGap = AppSpace.m;
  static const double rowGap = AppSpace.s;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell =
            ((constraints.maxWidth - (columns - 1) * columnGap) / columns)
                .floorToDouble();
        return Wrap(
          spacing: columnGap,
          runSpacing: rowGap,
          children: [
            for (final name in names)
              _IconCell(
                name: name,
                size: cell,
                selected: name == selected,
                onTap: () => onSelected(name),
              ),
          ],
        );
      },
    );
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.name,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    return AppPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: name,
      excludeChildSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceGrouped,
          borderRadius: BorderRadius.circular(tokens.radius.card),
          border: selected
              ? Border.all(color: colors.brandPrimary, width: 1.5)
              : null,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              presetIconData(name),
              size: AppSize.iconL,
              color: selected ? colors.brandPrimary : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
