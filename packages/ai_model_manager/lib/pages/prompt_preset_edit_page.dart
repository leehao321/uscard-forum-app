import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../models/prompt_preset.dart';
import '../providers/prompt_preset_providers.dart';
import '../widgets/preset_icon.dart';
import '../widgets/preset_icon_picker.dart';

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
    _iconRaw = p?.iconRaw ?? kDefaultPresetIcon;
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
    final tokens = context.tokens;
    final isImage = _type == PromptType.image;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: tokens.colors.surfacePage,
      // 补充稿 44：返回 + 标题 + 右上「保存」（brand 文字）
      appBar: AppNavBar(
        title: _isEditing
            ? AiL10n.current.quickPromptsEditTitle
            : AiL10n.current.quickPromptsCreateTitle,
        trailing: [
          AppPressable(
            onTap: _save,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSize.hit,
                minHeight: AppSize.hit,
              ),
              child: Center(
                child: Text(
                  AiL10n.current.save,
                  style: tokens.text.control.copyWith(
                    color: tokens.colors.brandPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ReadableBody(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.pageMargin,
              0,
              AppSpace.pageMargin,
              bottom + AppSpace.xl,
            ),
            children: [
              _GroupLabel(AiL10n.current.quickPromptsType),
              // 分段：图像在前、文本在后（和管理页一致）
              AppSegmentedControl.indexed(
                labels: [
                  AiL10n.current.quickPromptsTypeImage,
                  AiL10n.current.quickPromptsTypeText,
                ],
                selectedIndex: _type == PromptType.image ? 0 : 1,
                onChanged: _isBuiltIn
                    ? null
                    : (i) => setState(
                        () => _type = i == 0 ? PromptType.image : PromptType.text,
                      ),
              ),
              _FieldBlock(
                child: AppFilledField(
                  label: AiL10n.current.quickPromptsName,
                  controller: _nameController,
                  enabled: !_isBuiltIn,
                  hintText: AiL10n.current.quickPromptsNameHint,
                  validator: (v) => v.trim().isEmpty
                      ? AiL10n.current.quickPromptsValidateNameRequired
                      : null,
                ),
              ),
              if (_isBuiltIn)
                _IconReadOnly(iconRaw: _iconRaw)
              else
                PresetIconPicker(
                  value: _iconRaw,
                  onChanged: (v) => setState(() => _iconRaw = v),
                ),
              _FieldBlock(
                child: AppFilledField(
                  label: AiL10n.current.quickPromptsTemplate,
                  controller: _templateController,
                  enabled: !_isBuiltIn,
                  minLines: 3,
                  maxLines: 12,
                  minHeight: 96,
                  hintText: AiL10n.current.quickPromptsTemplateHint,
                  validator: (v) => v.trim().isEmpty
                      ? AiL10n.current.quickPromptsValidateTemplateRequired
                      : null,
                ),
              ),
              if (isImage) ...[
                _GroupLabel(AiL10n.current.quickPromptsAspect),
                Wrap(
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
              ],
              _FieldBlock(
                child: AppFilledField(
                  label: AiL10n.current.quickPromptsTags,
                  controller: _tagsController,
                  enabled: !_isBuiltIn,
                  hintText: AiL10n.current.quickPromptsTagsHint,
                ),
              ),
              if (_isBuiltIn)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Text(
                    '内置快捷词的名称、模板、图标不可编辑，可调整比例与置顶 / 隐藏',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.merge(tokens.text.meta)
                        .copyWith(color: tokens.colors.textMeta),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// 组页眉：13 meta，上 24 下 8（稿里的 48 高页眉）
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

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

/// 带标签的输入框块：上下各 8（稿里 84 高的「输入框外框」）
class _FieldBlock extends StatelessWidget {
  const _FieldBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
      child: child,
    );
  }
}

/// 内置快捷词的图标：只读展示，不能改
class _IconReadOnly extends StatelessWidget {
  const _IconReadOnly({required this.iconRaw});

  final String iconRaw;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final meta = Theme.of(context).textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textMeta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupLabel(AiL10n.current.quickPromptsIcon),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              PresetIcon(
                iconRaw: iconRaw,
                size: AppSize.iconL,
                color: tokens.colors.textMeta,
              ),
              const SizedBox(width: AppSpace.s),
              Text(
                AiL10n.current.quickPromptsIconSelected(
                  presetLucideName(iconRaw) ?? iconRaw,
                ),
                style: meta,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
