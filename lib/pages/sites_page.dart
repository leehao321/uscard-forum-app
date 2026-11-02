import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../models/site_profile.dart';
import '../services/site_context.dart';
import '../services/site_registry_service.dart';
import '../services/site_switch_service.dart';
import 'add_site_page.dart';

/// 论坛管理：列表、添加、移除、切换。切换要重启 App 才生效。
class SitesPage extends StatefulWidget {
  const SitesPage({super.key, this.registry, this.exitApp});

  final SiteRegistryService? registry;

  /// 切换后退出 App，测试时替换。
  final void Function()? exitApp;

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  SiteRegistryService get _registry =>
      widget.registry ?? SiteRegistryService.instance;

  Future<void> _addSite() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => AddSitePage(
          onConfirmed: (site) async {
            await _registry.addOrUpdate(site);
            if (routeContext.mounted) Navigator.of(routeContext).pop();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmSwitch(SiteProfile site) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.site_switchTitle(site.title)),
        content: Text(l10n.site_switchBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.site_switchConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SiteSwitchService(registry: _registry).switchSite(site);
    (widget.exitApp ?? () => exit(0))();
  }

  Future<void> _confirmRemove(SiteProfile site) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.site_removeTitle(site.title)),
        content: Text(l10n.site_removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.site_removeConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _registry.remove(site.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sites = _registry.sites;
    final currentId = SiteContext.current.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.site_manageTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSite,
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.site_addButton),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final site in sites)
            ListTile(
              title: Text(site.title),
              subtitle: Text(site.id),
              trailing: site.id == currentId
                  ? Icon(
                      Symbols.check_circle_rounded,
                      color: theme.colorScheme.primary,
                      semanticLabel: l10n.site_currentLabel,
                    )
                  : IconButton(
                      icon: const Icon(Symbols.delete_outline_rounded),
                      tooltip: l10n.site_removeConfirm,
                      onPressed: () => _confirmRemove(site),
                    ),
              onTap: site.id == currentId ? null : () => _confirmSwitch(site),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.site_platformNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
