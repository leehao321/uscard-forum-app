import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../models/ai_provider.dart';
import '../providers/ai_chat_providers.dart';
import '../providers/ai_provider_providers.dart';
import '../utils/dialog_utils.dart';
import '../widgets/model_icon.dart';

class AiModelConfigPage extends ConsumerWidget {
  const AiModelConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allModels = ref.watch(allAvailableAiModelsProvider);
    final textDefaultKey = ref.watch(defaultTextAiModelKeyProvider);
    final imageDefaultKey = ref.watch(defaultImageAiModelKeyProvider);
    final titleModel = ref.watch(aiTitleModelProvider);
    final optimizer = ref.watch(aiImagePromptOptimizerModelProvider);

    final textDefault = _resolveModel(allModels, textDefaultKey);
    final imageDefault = _resolveModel(allModels, imageDefaultKey);

    return Scaffold(
      appBar: ReadableAppBar(child: AppBar(title: Text(AiL10n.current.modelConfig))),
      body: ReadableBody(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _ModelCard(
            icon: AppIcons.message,
            title: AiL10n.current.defaultChatModel,
            current: textDefault,
            onPick: () => _showPicker(
              context,
              ref,
              allModels
                  .where((m) => m.model.output.contains(Modality.text))
                  .toList(),
              currentKey: textDefaultKey,
              onSelect: (p, m) =>
                  setDefaultAiModel(ref, p, m, isImageMode: false),
              onClear: () => clearDefaultAiModel(ref, isImageMode: false),
            ),
            onReset: textDefaultKey != null
                ? () => clearDefaultAiModel(ref, isImageMode: false)
                : null,
          ),
          const SizedBox(height: AppSpace.xl),
          _ModelCard(
            icon: AppIcons.image,
            title: AiL10n.current.defaultImageModel,
            current: imageDefault,
            onPick: () => _showPicker(
              context,
              ref,
              allModels
                  .where((m) => m.model.output.contains(Modality.image))
                  .toList(),
              currentKey: imageDefaultKey,
              onSelect: (p, m) =>
                  setDefaultAiModel(ref, p, m, isImageMode: true),
              onClear: () => clearDefaultAiModel(ref, isImageMode: true),
            ),
            onReset: imageDefaultKey != null
                ? () => clearDefaultAiModel(ref, isImageMode: true)
                : null,
          ),
          const SizedBox(height: AppSpace.xl),
          _ModelCard(
            icon: AppIcons.heading,
            title: AiL10n.current.titleGenerationModel,
            subtitle: AiL10n.current.autoGenerateTitleSubtitle,
            current: titleModel,
            onPick: () => _showPicker(
              context,
              ref,
              allModels,
              current: titleModel,
              clearLabel: AiL10n.current.noAutoGenerateTitle,
              onSelect: (p, m) => setAiTitleModel(ref, p, m),
              onClear: () => setAiTitleModel(ref, null, null),
            ),
            onReset: titleModel != null
                ? () => setAiTitleModel(ref, null, null)
                : null,
          ),
          const SizedBox(height: AppSpace.xl),
          _ModelCard(
            icon: AppIcons.autoFixHigh,
            title: AiL10n.current.imagePromptOptimizerModel,
            subtitle: AiL10n.current.imagePromptOptimizerSubtitle,
            current: optimizer,
            onPick: () => _showPicker(
              context,
              ref,
              allModels
                  .where((m) => m.model.output.contains(Modality.text))
                  .toList(),
              current: optimizer,
              clearLabel: AiL10n.current.optimizerNotSet,
              onSelect: (p, m) => setAiImagePromptOptimizerModel(ref, p, m),
              onClear: () => setAiImagePromptOptimizerModel(ref, null, null),
            ),
            onReset: optimizer != null
                ? () => setAiImagePromptOptimizerModel(ref, null, null)
                : null,
          ),
        ],
      )),
    );
  }

  ({AiProvider provider, AiModel model})? _resolveModel(
    List<({AiProvider provider, AiModel model})> allModels,
    String? key,
  ) {
    if (key == null) return null;
    final parts = key.split(':');
    if (parts.length < 2) return null;
    final pid = parts[0];
    final mid = parts.sublist(1).join(':');
    for (final m in allModels) {
      if (m.provider.id == pid && m.model.id == mid) return m;
    }
    return null;
  }

  void _showPicker(
    BuildContext context,
    WidgetRef ref,
    List<({AiProvider provider, AiModel model})> models, {
    String? currentKey,
    ({AiProvider provider, AiModel model})? current,
    String? clearLabel,
    required void Function(String providerId, String modelId) onSelect,
    required VoidCallback onClear,
  }) {
    showAppBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              title: Text(clearLabel ?? AiL10n.current.notSet),
              trailing: (currentKey == null && current == null)
                  ? const Icon(AppIcons.check)
                  : null,
              onTap: () {
                onClear();
                Navigator.pop(ctx);
              },
            ),
            ...models.map((item) {
              bool isCurrent;
              if (currentKey != null) {
                isCurrent =
                    '${item.provider.id}:${item.model.id}' == currentKey;
              } else {
                isCurrent = current != null &&
                    item.provider.id == current.provider.id &&
                    item.model.id == current.model.id;
              }
              return ListTile(
                leading: ModelIcon(
                  providerName: item.provider.name,
                  modelName: item.model.name ?? item.model.id,
                  size: 28,
                ),
                title: Text(item.model.name ?? item.model.id),
                subtitle: Text(item.provider.name),
                trailing: isCurrent ? const Icon(AppIcons.check) : null,
                onTap: () {
                  onSelect(item.provider.id, item.model.id);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// v2：每项一组。页眉写用途（标题 + 说明，13 meta），组里一行 =
/// 34 方块 + 模型名 + 服务商 13 meta + 重置 + chevron；未设置显示 meta「未设置」。
class _ModelCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ({AiProvider provider, AiModel model})? current;
  final VoidCallback onPick;
  final VoidCallback? onReset;

  const _ModelCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.current,
    required this.onPick,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final meta = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final model = current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.l,
            0,
            AppSpace.l,
            AppSpace.s,
          ),
          child: Text(
            subtitle == null ? title : '$title · $subtitle',
            style: meta,
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceGrouped,
            borderRadius: BorderRadius.circular(tokens.radius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPick,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSize.row48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.l,
                        vertical: AppSpace.s,
                      ),
                      child: Row(
                        children: [
                          if (model != null)
                            ModelIcon(
                              providerName: model.provider.name,
                              modelName: model.model.name ?? model.model.id,
                            )
                          else
                            Icon(icon,
                                size: AppSize.iconM, color: colors.textMeta),
                          const SizedBox(width: AppSpace.m),
                          Expanded(
                            child: model != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.model.name ?? model.model.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyLarge
                                            ?.merge(tokens.text.control)
                                            .copyWith(
                                              color: colors.textPrimary,
                                            ),
                                      ),
                                      Text(model.provider.name, style: meta),
                                    ],
                                  )
                                : Text(AiL10n.current.notSet, style: meta),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onReset != null)
                AppIconButton(
                  icon: AppIcons.restartAlt,
                  semanticLabel: AiL10n.current.modelDetailResetAuto,
                  onPressed: onReset,
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.l),
                child: Icon(
                  AppIcons.chevronRight,
                  size: AppSize.iconM,
                  color: colors.textMeta,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
