import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../models/ai_provider.dart';
import '../providers/ai_provider_providers.dart';
import '../utils/dialog_utils.dart';
import '../widgets/model_icon.dart';
import '../widgets/swipe_action_cell.dart';
import 'ai_provider_edit_page.dart';

class AiProviderListPage extends ConsumerStatefulWidget {
  const AiProviderListPage({super.key});

  @override
  ConsumerState<AiProviderListPage> createState() => _AiProviderListPageState();
}

class _AiProviderListPageState extends ConsumerState<AiProviderListPage> {
  bool _manageMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(aiProviderListProvider);
    final pinned = providers.where((provider) => provider.pinned).toList();
    final others = providers.where((provider) => !provider.pinned).toList();

    return Scaffold(
      appBar: ReadableAppBar(child: AppBar(
        leading: _manageMode
            ? IconButton(
                icon: const Icon(AppIcons.close),
                tooltip: AiL10n.current.cancel,
                onPressed: _exitManageMode,
              )
            : null,
        title: Text(
          _manageMode
              ? AiL10n.current.selectedProviderCount(_selectedIds.length)
              : AiL10n.current.providersTitle,
        ),
        actions: _buildAppBarActions(context, providers),
      )),
      body: ReadableBody(child: providers.isEmpty
          ? _buildEmpty(context)
          : _manageMode
              ? _ManageProviderList(
                  pinned: pinned,
                  others: others,
                  selectedIds: _selectedIds,
                  onToggleSelection: _toggleSelection,
                )
              : SwipeActionScope(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _SectionLabel(
                            text: AiL10n.current.pinnedProvidersSection),
                        _ProviderReorderSection(
                          providers: pinned,
                          pinned: true,
                          onReorder: _reorderProviders,
                          onEdit: (provider) =>
                              _navigateToEdit(context, provider),
                          onDelete: (provider) =>
                              _confirmDelete(context, provider),
                          onTogglePin: _togglePin,
                        ),
                        if (others.isNotEmpty) const SizedBox(height: 16),
                      ],
                      if (others.isNotEmpty) ...[
                        _SectionLabel(
                            text: AiL10n.current.otherProvidersSection),
                        _ProviderReorderSection(
                          providers: others,
                          pinned: false,
                          onReorder: _reorderProviders,
                          onEdit: (provider) =>
                              _navigateToEdit(context, provider),
                          onDelete: (provider) =>
                              _confirmDelete(context, provider),
                          onTogglePin: _togglePin,
                        ),
                      ],
                    ],
                  ),
                )),
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    List<AiProvider> providers,
  ) {
    if (_manageMode) {
      return [
        IconButton(
          icon: const Icon(AppIcons.delete),
          tooltip: AiL10n.current.deleteSelectedProviders,
          onPressed:
              _selectedIds.isEmpty ? null : () => _confirmBatchDelete(context),
        ),
      ];
    }

    return [
      if (providers.isNotEmpty)
        AppIconButton(
          key: const ValueKey('provider_manage_button'),
          icon: AppIcons.listChecks,
          semanticLabel: AiL10n.current.manage,
          onPressed: _enterManageMode,
        ),
      AppIconButton(
        icon: AppIcons.add,
        semanticLabel: AiL10n.current.addProvider,
        onPressed: () => _navigateToEdit(context),
      ),
    ];
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.server,
              size: 48, color: context.tokens.colors.textMeta),
          const SizedBox(height: 16),
          Text(
            AiL10n.current.noProviderConfigured,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AiL10n.current.addProviderHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _navigateToEdit(context),
            icon: const Icon(AppIcons.add),
            label: Text(AiL10n.current.addProvider),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(BuildContext context, [AiProvider? provider]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiProviderEditPage(provider: provider),
      ),
    );
  }

  void _enterManageMode() {
    setState(() {
      _manageMode = true;
      _selectedIds.clear();
    });
  }

  void _exitManageMode() {
    setState(() {
      _manageMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _togglePin(AiProvider provider) async {
    await ref.read(aiProviderListProvider.notifier).togglePin(provider.id);
  }

  Future<void> _reorderProviders(
    bool pinned,
    int oldIndex,
    int newIndex,
  ) async {
    final notifier = ref.read(aiProviderListProvider.notifier);
    if (pinned) {
      await notifier.reorderPinned(oldIndex, newIndex);
    } else {
      await notifier.reorderUnpinned(oldIndex, newIndex);
    }
  }

  Future<void> _confirmDelete(BuildContext context, AiProvider provider) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(AiL10n.current.confirmDelete),
        content: Text(AiL10n.current.confirmDeleteProvider(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AiL10n.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(AiL10n.current.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(aiProviderListProvider.notifier)
          .removeProvider(provider.id);
    }
  }

  Future<void> _confirmBatchDelete(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(AiL10n.current.confirmDelete),
        content: Text(
          AiL10n.current.confirmDeleteSelectedProviders(_selectedIds.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AiL10n.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(AiL10n.current.deleteSelectedProviders),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(aiProviderListProvider.notifier)
          .removeProviders(_selectedIds);
      if (mounted) {
        _exitManageMode();
      }
    }
  }
}

class _ProviderReorderSection extends StatelessWidget {
  const _ProviderReorderSection({
    required this.providers,
    required this.pinned,
    required this.onReorder,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  final List<AiProvider> providers;
  final bool pinned;
  final Future<void> Function(bool pinned, int oldIndex, int newIndex)
      onReorder;
  final ValueChanged<AiProvider> onEdit;
  final ValueChanged<AiProvider> onDelete;
  final ValueChanged<AiProvider> onTogglePin;

  @override
  Widget build(BuildContext context) {
    return _GroupBox(
        child: ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: providers.length,
      onReorderItem: (oldIndex, newIndex) async {
        await onReorder(pinned, oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final provider = providers[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(provider.id),
          index: index,
          child: Padding(
            padding: EdgeInsets.zero,
            child: SwipeActionCell(
              key: ValueKey('swipe_${provider.id}'),
              enableLongPressMenu: false,
              trailingActions: [
                SwipeAction(
                  icon: AppIcons.edit,
                  color: context.tokens.colors.brandButton,
                  label: AiL10n.current.edit,
                  onPressed: () => onEdit(provider),
                ),
                SwipeAction(
                  icon: AppIcons.delete,
                  color: context.tokens.colors.textDestructive,
                  label: AiL10n.current.delete,
                  onPressed: () => onDelete(provider),
                ),
              ],
              child: _ProviderCard(
                provider: provider,
                showSelection: false,
                showSeparator: index < providers.length - 1,
                onTap: () => onEdit(provider),
                onTogglePin: () => onTogglePin(provider),
              ),
            ),
          ),
        );
      },
    ));
  }
}

class _ManageProviderList extends StatelessWidget {
  const _ManageProviderList({
    required this.pinned,
    required this.others,
    required this.selectedIds,
    required this.onToggleSelection,
  });

  final List<AiProvider> pinned;
  final List<AiProvider> others;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (pinned.isNotEmpty) ...[
          _SectionLabel(text: AiL10n.current.pinnedProvidersSection),
          ..._buildSectionItems(pinned),
          if (others.isNotEmpty) const SizedBox(height: 16),
        ],
        if (others.isNotEmpty) ...[
          _SectionLabel(text: AiL10n.current.otherProvidersSection),
          ..._buildSectionItems(others),
        ],
      ],
    );
  }

  List<Widget> _buildSectionItems(List<AiProvider> providers) {
    return [
      _GroupBox(
        child: Column(
          children: [
            for (var index = 0; index < providers.length; index++)
              _ProviderCard(
                provider: providers[index],
                selected: selectedIds.contains(providers[index].id),
                showSelection: true,
                showSeparator: index < providers.length - 1,
                onTap: () => onToggleSelection(providers[index].id),
              ),
          ],
        ),
      ),
    ];
  }
}

/// v2 分组容器：surface/grouped、r12、裁切；行之间的分隔线由行自己画
class _GroupBox extends StatelessWidget {
  const _GroupBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.s),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.merge(context.tokens.text.meta)
            .copyWith(color: context.tokens.colors.textMeta),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.onTap,
    this.selected = false,
    this.showSelection = false,
    this.onTogglePin,
    this.showSeparator = true,
  });

  final AiProvider provider;
  final VoidCallback onTap;
  final bool selected;
  final bool showSelection;
  final VoidCallback? onTogglePin;

  /// 行下方的发丝分隔线（分组里最后一行不画）
  final bool showSeparator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final enabledCount = provider.models.where((model) => model.enabled).length;
    final totalCount = provider.models.length;
    final meta = theme.textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    return Material(
      color: selected
          ? colors.brandPrimary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.l,
                vertical: AppSpace.s,
              ),
              child: Row(
                children: [
                  ModelIcon(
                    providerName: provider.name,
                    modelName: provider.name,
                  ),
                  const SizedBox(width: AppSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          provider.name,
                          style: theme.textTheme.bodyLarge
                              ?.merge(tokens.text.control)
                              .copyWith(color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${provider.type.label} · '
                          '${AiL10n.current.modelCount(enabledCount, totalCount)}',
                          style: meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (showSelection)
                    Icon(
                      selected ? AppIcons.checkCircle : AppIcons.radioButtonOff,
                      size: AppSize.iconM,
                      color: selected ? colors.brandPrimary : colors.textMeta,
                    )
                  else ...[
                    AppIconButton(
                      key: ValueKey('pin_${provider.id}'),
                      icon: AppIcons.pushPin,
                      semanticLabel: provider.pinned
                          ? AiL10n.current.unpinProvider
                          : AiL10n.current.pinProvider,
                      selected: provider.pinned,
                      color: provider.pinned ? colors.brandPrimary : null,
                      onPressed: onTogglePin,
                    ),
                    Icon(
                      AppIcons.chevronRight,
                      color: colors.textMeta,
                      size: AppSize.iconM,
                    ),
                  ],
                ],
              ),
            ),
            if (showSeparator) const AppHairline(indent: 62),
          ],
        ),
      ),
    );
  }
}
