import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/site_profile.dart';
import '../../pages/add_site_page.dart';
import '../../services/site_context.dart';
import '../../services/site_registry_service.dart';
import '../../services/site_switch_service.dart';
import '../common/app_bottom_sheet.dart';

/// 快捷切站：已保存的论坛，当前站打勾，底部可以添加新论坛。
Future<void> showSiteSwitcherSheet(
  BuildContext context, {
  SiteRegistryService? registry,
  SiteSwitchController? controller,
}) {
  final background = Theme.of(context).scaffoldBackgroundColor;
  final sites = registry ?? SiteRegistryService.instance;
  final switcher = controller ?? SiteSwitchController.instance;
  // 透明主题下 scaffold 背景是透明的，占位页要用不透明的颜色。
  final placeholder = background.a < 1
      ? Theme.of(context).colorScheme.surface
      : background;

  return AppBottomSheet.show<void>(
    context: context,
    title: context.l10n.site_switcherTitle,
    contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
    builder: (sheetContext) => SiteSwitcherList(
      sites: sites.sites,
      currentId: SiteContext.current.id,
      onSelect: (site) {
        Navigator.of(sheetContext).pop();
        switcher.switchTo(site, placeholderColor: placeholder);
      },
      onAdd: () {
        final navigator = Navigator.of(sheetContext);
        navigator.pop();
        navigator.push<void>(
          MaterialPageRoute(
            builder: (routeContext) => AddSitePage(
              onConfirmed: (site) async {
                await sites.addOrUpdate(site);
                final switched = await switcher.switchTo(
                  site,
                  placeholderColor: placeholder,
                );
                // 切成功时这个页面已随旧界面树卸载；加的就是当前站时才走到这里
                if (!switched && routeContext.mounted) {
                  Navigator.of(routeContext).pop();
                }
              },
            ),
          ),
        );
      },
    ),
  );
}

class SiteSwitcherList extends StatelessWidget {
  const SiteSwitcherList({
    super.key,
    required this.sites,
    required this.currentId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<SiteProfile> sites;
  final String currentId;
  final ValueChanged<SiteProfile> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final site in sites)
                ListTile(
                  title: Text(
                    site.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    site.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: site.id == currentId
                      ? Icon(
                          Symbols.check_rounded,
                          color: scheme.primary,
                          semanticLabel: l10n.site_currentLabel,
                        )
                      : null,
                  // 当前站点了也只是关掉面板，不用再切
                  onTap: site.id == currentId
                      ? () => Navigator.of(context).pop()
                      : () => onSelect(site),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Symbols.add_rounded, color: scheme.primary),
          title: Text(
            l10n.site_switcherAdd,
            style: TextStyle(color: scheme.primary),
          ),
          onTap: onAdd,
        ),
      ],
    );
  }
}

/// 「我的」页顶部的当前论坛胶囊，点开快捷切站。
class CurrentSiteChip extends StatelessWidget {
  const CurrentSiteChip({super.key, this.registry, this.controller});

  final SiteRegistryService? registry;
  final SiteSwitchController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: context.l10n.site_switcherTitle,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showSiteSwitcherSheet(
            context,
            registry: registry,
            controller: controller,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.language_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    SiteContext.current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Symbols.arrow_drop_down_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
