import 'dart:convert';

import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/ai_l10n.dart';
import '../models/prompt_preset.dart';
import '../providers/prompt_preset_providers.dart';
import '../services/toast_delegate.dart';
import '../utils/dialog_utils.dart';
import '../widgets/preset_icon.dart';
import 'prompt_preset_edit_page.dart';

/// 快捷词管理页
///
/// - 顶部 segmented：图像 / 文本
/// - 列表分两段：内置 / 自定义
/// - 拖拽排序（分组内）
/// - swipe 编辑/删除/隐藏
/// - 右上 + 新建；溢出菜单 恢复内置默认
class PromptPresetsPage extends ConsumerStatefulWidget {
  const PromptPresetsPage({super.key, this.initialType = PromptType.image});

  final PromptType initialType;

  @override
  ConsumerState<PromptPresetsPage> createState() => _PromptPresetsPageState();
}

class _PromptPresetsPageState extends ConsumerState<PromptPresetsPage> {
  late PromptType _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final all = ref.watch(promptPresetsByTypeProvider(_type));
    final builtIns = all.where((p) => p.builtIn).toList(growable: false);
    final customs = all.where((p) => !p.builtIn).toList(growable: false);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      // 补充稿 43：返回 + 标题 + 右上「+」和「⋯」（iOS 圆角浮层菜单）
      appBar: AppNavBar(
        title: AiL10n.current.quickPromptsManageTitle,
        trailing: [
          AppIconButton(
            icon: AppIcons.add,
            semanticLabel: AiL10n.current.quickPromptsAddNew,
            onPressed: _addNew,
          ),
          AppMenuButton<String>(
            icon: AppIcons.moreHoriz,
            semanticLabel: AiL10n.current.manage,
            onSelected: (v) {
              switch (v) {
                case 'reset':
                  _confirmReset();
                case 'export_all':
                  _exportAll(customs);
                case 'import':
                  _importFromClipboard();
              }
            },
            sectionsBuilder: (_) => [
              [
                AppMenuItem<String>(
                  label: AiL10n.current.presetImport,
                  value: 'import',
                  icon: AppIcons.paste,
                ),
                if (customs.isNotEmpty)
                  AppMenuItem<String>(
                    label: AiL10n.current.presetExportAll,
                    value: 'export_all',
                    icon: AppIcons.upload,
                  ),
                AppMenuItem<String>(
                  label: AiL10n.current.quickPromptsResetBuiltIns,
                  value: 'reset',
                  icon: AppIcons.restartAlt,
                ),
              ],
            ],
          ),
        ],
      ),
      body: ReadableBody(
        child: Column(
          children: [
            // 分段：图像 / 文本
            AppSegmentedControl.indexed(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.pageMargin,
              ),
              labels: [
                AiL10n.current.quickPromptsImageTab,
                AiL10n.current.quickPromptsTextTab,
              ],
              selectedIndex: _type == PromptType.image ? 0 : 1,
              onChanged: (i) => setState(
                () => _type = i == 0 ? PromptType.image : PromptType.text,
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.pageMargin,
                  0,
                  AppSpace.pageMargin,
                  bottom + AppSpace.xxl,
                ),
                children: [
                  if (builtIns.isNotEmpty) ...[
                    _SectionLabel(
                      text: AiL10n.current.quickPromptsBuiltInSection,
                    ),
                    _ReorderableGroup(
                      presets: builtIns,
                      type: _type,
                      builtIn: true,
                      onEdit: _openEdit,
                    ),
                  ],
                  _SectionLabel(text: AiL10n.current.quickPromptsCustomSection),
                  if (customs.isEmpty)
                    // 空态：48 图标 + 标题 + 说明（稿里这一块 180 高）
                    SizedBox(
                      height: 180,
                      child: AppStateView(
                        bareIcon: true,
                        icon: AppIcons.sparkles,
                        title: AiL10n.current.quickPromptsEmpty,
                        message: AiL10n.current.quickPromptsEmptyHint,
                      ),
                    )
                  else
                    _ReorderableGroup(
                      presets: customs,
                      type: _type,
                      builtIn: false,
                      onEdit: _openEdit,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNew() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PromptPresetEditPage(initialType: _type),
      ),
    );
  }

  void _openEdit(PromptPreset preset) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PromptPresetEditPage(preset: preset),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        content: Text(AiL10n.current.quickPromptsResetBuiltInsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AiL10n.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AiL10n.current.quickPromptsResetBuiltIns),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(promptPresetListProvider.notifier)
          .resetBuiltInsToDefault();
    }
  }

  // ────────────── 导入/导出 ──────────────

  static Map<String, dynamic> _presetToExport(PromptPreset p) => {
        'type': p.type.toJson(),
        'name': p.name,
        'iconRaw': p.iconRaw,
        'promptTemplate': p.promptTemplate,
        if (p.aspectRatio != null) 'aspectRatio': p.aspectRatio,
        if (p.tags.isNotEmpty) 'tags': p.tags,
        if (p.dimensions != null)
          'dimensions': p.dimensions!.map((d) => d.toJson()).toList(),
        if (p.defaultDimensionValues != null)
          'defaultDimensionValues': p.defaultDimensionValues,
      };

  static void exportPreset(PromptPreset preset) {
    final json = jsonEncode({
      'version': 1,
      'presets': [_presetToExport(preset)],
    });
    Clipboard.setData(ClipboardData(text: json));
    AiToastDelegate.showSuccess(AiL10n.current.presetExportSuccess);
  }

  void _exportAll(List<PromptPreset> customs) {
    if (customs.isEmpty) return;
    final json = jsonEncode({
      'version': 1,
      'presets': customs.map(_presetToExport).toList(),
    });
    Clipboard.setData(ClipboardData(text: json));
    AiToastDelegate.showSuccess(AiL10n.current.presetExportSuccess);
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.presetImportEmpty);
      return;
    }

    List<PromptPreset> parsed;
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        final list = json['presets'] as List<dynamic>?;
        if (list == null || list.isEmpty) throw FormatException('no presets');
        parsed = list
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (json is List) {
        parsed = json
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw FormatException('invalid format');
      }
    } catch (_) {
      AiToastDelegate.showError(AiL10n.current.presetImportEmpty);
      return;
    }

    if (parsed.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.presetImportEmpty);
      return;
    }

    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(AiL10n.current.presetImportPreview),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: parsed.length,
            itemBuilder: (_, i) {
              final p = parsed[i];
              return ListTile(
                leading: PresetIcon(iconRaw: p.iconRaw, size: 28),
                title: Text(p.name),
                subtitle: Text(p.type == PromptType.image
                    ? AiL10n.current.quickPromptsImageTab
                    : AiL10n.current.quickPromptsTextTab),
                dense: true,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AiL10n.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AiL10n.current.presetImportConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    const uuid = Uuid();
    final notifier = ref.read(promptPresetListProvider.notifier);
    var count = 0;
    for (final p in parsed) {
      await notifier.addUserPreset(p.copyWith(
        id: uuid.v4(),
        builtIn: false,
        hidden: false,
        pinned: false,
        sortOrder: 999 + count,
      ));
      count++;
    }
    AiToastDelegate.showSuccess(AiL10n.current.presetImportCount(count));
  }
}

/// 组页眉：13 meta，上 24 下 8（稿里 48 高的页眉）
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxl, bottom: AppSpace.s),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta),
      ),
    );
  }
}

class _ReorderableGroup extends ConsumerStatefulWidget {
  const _ReorderableGroup({
    required this.presets,
    required this.type,
    required this.builtIn,
    required this.onEdit,
  });

  final List<PromptPreset> presets;
  final PromptType type;
  final bool builtIn;
  final void Function(PromptPreset) onEdit;

  @override
  ConsumerState<_ReorderableGroup> createState() => _ReorderableGroupState();
}

/// 分组卡片（surface/grouped r12）：每行 48 高（有比例 / 标签说明时 64）——
/// 拖拽柄 20（44 热区）+ 图标 20 + 名称 17 + 右侧图钉 20（44 热区），
/// 行间发丝线从文字起点（76）开始。
class _ReorderableGroupState extends ConsumerState<_ReorderableGroup> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.card),
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.presets.length,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) =>
              ColoredBox(color: tokens.colors.surfaceGrouped, child: child),
          onReorderItem: (oldIndex, newIndex) async {
            final ids = [for (final p in widget.presets) p.id];
            final id = ids.removeAt(oldIndex);
            ids.insert(newIndex, id);
            await ref
                .read(promptPresetListProvider.notifier)
                .reorderInGroup(widget.type, widget.builtIn, ids);
          },
          itemBuilder: (context, index) {
            final preset = widget.presets[index];
            return KeyedSubtree(
              key: ValueKey(preset.id),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.only(left: _kTextInset),
                      child: AppHairline(),
                    ),
                  _PresetRow(
                    preset: preset,
                    index: index,
                    onEdit: widget.onEdit,
                    onDelete: () async {
                      final ok = await _confirmDelete(context, preset.name);
                      if (ok) {
                        await ref
                            .read(promptPresetListProvider.notifier)
                            .deletePreset(preset.id);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        content: Text(AiL10n.current.quickPromptsDeleteConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AiL10n.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AiL10n.current.delete),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 文字起点（拖拽柄 44 + 图标 20 + 间距 12）
const double _kTextInset = 76;

class _PresetRow extends ConsumerWidget {
  const _PresetRow({
    required this.preset,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  final PromptPreset preset;
  final int index;
  final void Function(PromptPreset) onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final notifier = ref.read(promptPresetListProvider.notifier);
    // 比例 / 标签收成一行 13 meta 说明
    final note = [
      if (preset.aspectRatio != null) preset.aspectRatio!,
      ...preset.tags,
    ].join(' · ');

    final actions = [
      if (!preset.builtIn)
        SwipeActionItem(
          icon: AppIcons.edit,
          label: AiL10n.current.edit,
          onTap: () => onEdit(preset),
        ),
      if (preset.builtIn)
        SwipeActionItem(
          icon: preset.hidden ? AppIcons.visibility : AppIcons.visibilityOff,
          label: preset.hidden
              ? AiL10n.current.quickPromptsUnhide
              : AiL10n.current.quickPromptsHide,
          onTap: () {
            if (preset.hidden) {
              notifier.unhide(preset.id);
            } else {
              notifier.hide(preset.id);
            }
          },
        ),
      if (!preset.builtIn)
        SwipeActionItem(
          icon: AppIcons.copy,
          label: AiL10n.current.presetExport,
          onTap: () => _PromptPresetsPageState.exportPreset(preset),
        ),
      if (!preset.builtIn)
        SwipeActionItem(
          icon: AppIcons.delete,
          label: AiL10n.current.delete,
          background: colors.textDestructive,
          onTap: onDelete,
        ),
    ];

    return SwipeActions(
      actions: actions,
      child: AppPressable(
        highlight: true,
        onTap: preset.builtIn ? null : () => onEdit(preset),
        button: !preset.builtIn,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.row48),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: SizedBox(
                  width: AppSize.hit,
                  height: AppSize.row48,
                  child: Center(
                    child: Icon(
                      AppIcons.grip,
                      size: AppSize.iconM,
                      color: colors.textMeta,
                    ),
                  ),
                ),
              ),
              PresetIcon(
                iconRaw: preset.iconRaw,
                size: AppSize.iconM,
                color: preset.hidden ? colors.textMeta : colors.textPrimary,
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: note.isEmpty ? 0 : AppSpace.m,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: base
                                  .merge(tokens.text.control)
                                  .copyWith(
                                    color: preset.hidden
                                        ? colors.textMeta
                                        : colors.textPrimary,
                                  ),
                            ),
                          ),
                          if (preset.hidden) ...[
                            const SizedBox(width: AppSpace.xs + AppSpace.xxs),
                            Icon(
                              AppIcons.visibilityOff,
                              size: AppSize.iconS,
                              color: colors.textMeta,
                            ),
                          ],
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base
                              .merge(tokens.text.meta)
                              .copyWith(color: colors.textMeta),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.pushPin,
                size: AppSize.iconM,
                color: preset.pinned ? colors.brandPrimary : colors.textMeta,
                selected: preset.pinned,
                semanticLabel: preset.pinned
                    ? AiL10n.current.quickPromptsUnpin
                    : AiL10n.current.quickPromptsPin,
                onPressed: () => notifier.togglePin(preset.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
