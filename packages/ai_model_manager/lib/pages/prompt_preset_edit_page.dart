import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../models/prompt_preset.dart';
import '../providers/prompt_preset_providers.dart';
import '../widgets/icon_emoji_picker.dart';

const List<String> _kAspectChoices = ['1:1', '16:9', '9:16', '4:3', '3:4'];

/// 快捷词新建/编辑页
///
/// - 新建: 不传 [preset]，可选 [initialType]
/// - 编辑: 传 [preset]
///   - 内置 preset 不可改 name/promptTemplate/icon/dimensions（这些字段
///     UI 仍展示但 disabled），仅可修改 aspectRatio / pinned 等
///   - 自定义 preset 可改全部
class PromptPresetEditPage extends ConsumerStatefulWidget {
  const PromptPresetEditPage({
    super.key,
    this.preset,
    this.initialType = PromptType.image,
  });

  final PromptPreset? preset;
  final PromptType initialType;

  @override
  ConsumerState<PromptPresetEditPage> createState() =>
      _PromptPresetEditPageState();
}

class _PromptPresetEditPageState extends ConsumerState<PromptPresetEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _templateController;
  late TextEditingController _tagsController;
  late PromptType _type;
  late String _iconRaw;
  String? _aspect;

  bool get _isEditing => widget.preset != null;
  bool get _isBuiltIn => widget.preset?.builtIn ?? false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _nameController = TextEditingController(text: p?.name ?? '');
    _templateController = TextEditingController(text: p?.promptTemplate ?? '');
    _tagsController = TextEditingController(text: p?.tags.join(', ') ?? '');
    _type = p?.type ?? widget.initialType;
    _iconRaw = p?.iconRaw ?? 'auto_awesome_outlined';
    _aspect = p?.aspectRatio;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _templateController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _type == PromptType.image;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? AiL10n.current.quickPromptsEditTitle
            : AiL10n.current.quickPromptsCreateTitle),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(AiL10n.current.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            AppSpace.s,
            AppSpace.pageMargin,
            AppSpace.xl,
          ),
          children: [
            // v2 分组行表单（设计说明 §5.3）：灰底 r12 的分组，行与行之间发丝线
            _FormGroup(
              header: AiL10n.current.quickPromptsType,
              children: [
                FilterTabs(
                  labels: [
                    AiL10n.current.quickPromptsTypeText,
                    AiL10n.current.quickPromptsTypeImage,
                  ],
                  selectedIndex: _type == PromptType.text ? 0 : 1,
                  scrollable: false,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                  onSelected: _isBuiltIn
                      ? (_) {}
                      : (i) => setState(
                            () => _type =
                                i == 0 ? PromptType.text : PromptType.image,
                          ),
                ),
              ],
            ),
            _FormGroup(
              header: AiL10n.current.quickPromptsName,
              children: [
                _FieldRow(
                  child: TextFormField(
                    controller: _nameController,
                    enabled: !_isBuiltIn,
                    decoration: _plainDecoration(
                      context,
                      AiL10n.current.quickPromptsNameHint,
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return AiL10n.current.quickPromptsValidateNameRequired;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            _FormGroup(
              header: AiL10n.current.quickPromptsIcon,
              children: [
                if (_isBuiltIn)
                  _FieldRow(
                    child: Row(
                      children: [
                        _DisabledIconPreview(iconRaw: _iconRaw),
                        const SizedBox(width: AppSpace.m),
                        Expanded(
                          child: Text(
                            _iconRaw,
                            style: theme.textTheme.bodySmall
                                ?.merge(context.tokens.text.meta)
                                .copyWith(
                                  color: context.tokens.colors.textMeta,
                                ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.m),
                    child: IconEmojiPicker(
                      value: _iconRaw,
                      onChanged: (v) => setState(() => _iconRaw = v),
                    ),
                  ),
              ],
            ),
            _FormGroup(
              header: AiL10n.current.quickPromptsTemplate,
              children: [
                _FieldRow(
                  child: TextFormField(
                    controller: _templateController,
                    enabled: !_isBuiltIn,
                    minLines: 4,
                    maxLines: 12,
                    decoration: _plainDecoration(
                      context,
                      AiL10n.current.quickPromptsTemplateHint,
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return AiL10n
                            .current.quickPromptsValidateTemplateRequired;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            if (isImage)
              _FormGroup(
                header: AiL10n.current.quickPromptsAspect,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.m),
                    child: Wrap(
                      spacing: AppSpace.s,
                      runSpacing: AppSpace.s,
                      children: [
                        FilterPill(
                          label: AiL10n.current.quickPromptsAspectAuto,
                          selected: _aspect == null,
                          showChevron: false,
                          onTap: () => setState(() => _aspect = null),
                        ),
                        for (final a in _kAspectChoices)
                          FilterPill(
                            label: a,
                            selected: _aspect == a,
                            showChevron: false,
                            onTap: () => setState(() => _aspect = a),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            _FormGroup(
              header: AiL10n.current.quickPromptsTags,
              footer: _isBuiltIn ? '内置快捷词的名称、模板、图标不可编辑，可调整比例与置顶 / 隐藏' : null,
              children: [
                _FieldRow(
                  child: TextFormField(
                    controller: _tagsController,
                    enabled: !_isBuiltIn,
                    decoration: _plainDecoration(
                      context,
                      AiL10n.current.quickPromptsTagsHint,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _plainDecoration(BuildContext context, String hint) {
    final tokens = context.tokens;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: tokens.colors.textMeta),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final template = _templateController.text.trim();
    final tags = _tagsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final notifier = ref.read(promptPresetListProvider.notifier);

    if (_isEditing) {
      final base = widget.preset!;
      final updated = base.copyWith(
        name: name,
        promptTemplate: template,
        iconRaw: _iconRaw,
        type: _type,
        tags: tags,
        aspectRatio: _aspect,
        clearAspectRatio: _aspect == null,
      );
      await notifier.updatePreset(updated);
    } else {
      final preset = PromptPreset(
        id: '',
        type: _type,
        name: name,
        iconRaw: _iconRaw,
        promptTemplate: template,
        aspectRatio: _aspect,
        tags: tags,
        pinned: false,
        builtIn: false,
      );
      await notifier.addUserPreset(preset);
    }
    if (mounted) Navigator.of(context).pop();
  }
}

/// 分组：组页眉（13 meta）+ 灰底 r12 的卡片（行间发丝线）+ 可选组页脚
class _FormGroup extends StatelessWidget {
  const _FormGroup({required this.header, required this.children, this.footer});

  final String header;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final meta = Theme.of(context)
        .textTheme
        .bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.m,
              0,
              AppSpace.m,
              AppSpace.xs,
            ),
            child: Text(header, style: meta),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.colors.surfaceGrouped,
              borderRadius: BorderRadius.circular(tokens.radius.card),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const AppHairline(),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.m,
                AppSpace.xs,
                AppSpace.m,
                0,
              ),
              child: Text(footer!, style: meta),
            ),
        ],
      ),
    );
  }
}

/// 组里的输入行：左右 12，至少 48 高，文字 17
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.row48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.m,
          vertical: AppSpace.s,
        ),
        child: DefaultTextStyle.merge(
          style: tokens.text.control.copyWith(color: tokens.colors.textPrimary),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );
  }
}

class _DisabledIconPreview extends StatelessWidget {
  const _DisabledIconPreview({required this.iconRaw});
  final String iconRaw;

  @override
  Widget build(BuildContext context) {
    // 简化版 PresetIcon（只为预览，避免循环导入复杂度）
    if (iconRaw.isNotEmpty && iconRaw.runes.first >= 0x80) {
      return Text(iconRaw, style: const TextStyle(fontSize: 22));
    }
    return const Icon(AppIcons.autoAwesome, size: 22);
  }
}
