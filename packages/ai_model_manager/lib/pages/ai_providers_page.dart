import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../providers/ai_chat_providers.dart';
import '../providers/ai_provider_providers.dart';
import '../providers/mcp_server_providers.dart';
import 'ai_advanced_settings_page.dart';
import 'ai_chat_history_page.dart';
import 'ai_model_config_page.dart';
import 'ai_provider_list_page.dart';
import 'mcp_servers_page.dart';
import 'prompt_presets_page.dart';

/// AI 模型服务入口页（0.4.0 v2，Figma 51:162）：
/// 单行导航 + 一组分组行（图标 20、标题 17、右侧当前值 + chevron 16）+ 组页脚。
class AiProvidersPage extends ConsumerWidget {
  final OpenSessionCallback? onOpenSession;

  const AiProvidersPage({super.key, this.onOpenSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerCount = ref.watch(aiProviderListProvider).length;
    final hasModels = ref.watch(hasAvailableAiModelProvider);
    final mcpCount = ref.watch(mcpServerListProvider).length;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final l10n = AiL10n.current;

    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    final rows = <Widget>[
      _EntryRow(
        icon: AppIcons.server,
        title: l10n.providersTitle,
        value:
            providerCount > 0 ? l10n.providerCountLabel(providerCount) : null,
        subtitle: providerCount > 0 ? null : l10n.noProviderConfigured,
        onTap: () => open(const AiProviderListPage()),
      ),
      if (hasModels)
        _EntryRow(
          icon: AppIcons.tune,
          title: l10n.modelConfig,
          onTap: () => open(const AiModelConfigPage()),
        ),
      _EntryRow(
        icon: AppIcons.wrench,
        title: 'MCP 服务',
        subtitle: '连接外部工具，让 AI 对话和问论坛可以调用',
        value: mcpCount > 0 ? '$mcpCount 个' : null,
        onTap: () => open(const McpServersPage()),
      ),
      _EntryRow(
        icon: AppIcons.history,
        title: l10n.chatHistory,
        onTap: () => open(AiChatHistoryPage(onOpenSession: onOpenSession)),
      ),
      _EntryRow(
        icon: AppIcons.zap,
        title: l10n.quickPromptsManageTitle,
        subtitle: l10n.quickPromptsManageHint,
        onTap: () => open(const PromptPresetsPage()),
      ),
      _EntryRow(
        icon: AppIcons.settings,
        title: l10n.advancedSettings,
        onTap: () => open(const AiAdvancedSettingsPage()),
      ),
    ];

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(title: l10n.aiModelService, slotWidth: 70),
      body: ReadableBody(
          child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ReadableColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                AppSpace.s,
                AppSpace.pageMargin,
                0,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceGrouped,
                  borderRadius: BorderRadius.circular(tokens.radius.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radius.card),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.only(left: 44),
                            child: AppHairline(),
                          ),
                        rows[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          ReadableColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.pageMargin + AppSpace.m,
                AppSpace.s,
                AppSpace.pageMargin + AppSpace.m,
                AppSpace.xl,
              ),
              child: Text(
                l10n.aiRequestFooter,
                style: base
                    .merge(tokens.text.meta)
                    .copyWith(color: colors.textMeta),
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return AppPressable(
      highlight: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.row48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m,
            vertical: AppSpace.xs,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppSize.iconM, color: colors.brandPrimary),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: base
                          .merge(tokens.text.control)
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: base
                            .merge(tokens.text.meta)
                            .copyWith(color: colors.textMeta),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: AppSpace.s),
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base
                        .merge(tokens.text.control)
                        .copyWith(color: colors.textMeta),
                  ),
                ),
              ],
              const SizedBox(width: AppSpace.s),
              Icon(
                AppIcons.chevronRight,
                size: AppSize.iconS,
                color: colors.textMeta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
