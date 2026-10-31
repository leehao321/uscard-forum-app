import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../navigation/nav_action_bus.dart';
import '../navigation/nav_entry.dart';
import '../navigation/nav_entry_registry.dart';
import '../providers/discourse_providers.dart';
import '../providers/preferences_provider.dart';
import '../services/toast_service.dart';
import '../settings/definitions/bottom_nav_defs.dart';
import '../settings/settings_model.dart';
import '../settings/settings_renderer.dart';
import '../utils/dialog_utils.dart';

import 'package:m3e_ui/m3e_ui.dart';

/// 底栏设置页
///
/// 布局：
/// - 顶部：真实底栏样式的预览，支持水平拖动排序（首页锁定第 0 位）
/// - 中部：可添加的候选池（点 + 加入）
/// - 底部：手势分组（复用 [SettingsRenderer] 渲染 bottom_nav_defs 的 ActionModel）
///
/// 约束：2 ≤ 已启用数量 ≤ 上限；locked entry（home、profile）不可移除。
///
/// 上限按屏幕宽度自适应,不再是写死的 5——手机底栏是横向 `NavigationBar`,
/// 塞太多图标会被越挤越窄;平板/桌面走的是竖排 `NavigationRail`,横向
/// 空间宽裕,没必要卡在手机的上限,直接放开到全部已注册入口数。
class BottomNavSettingsPage extends ConsumerStatefulWidget {
  final String? highlightId;

  const BottomNavSettingsPage({super.key, this.highlightId});

  @override
  ConsumerState<BottomNavSettingsPage> createState() =>
      _BottomNavSettingsPageState();
}

class _BottomNavSettingsPageState extends ConsumerState<BottomNavSettingsPage> {
  static const int _minCount = 2;

  /// 搜索跳转定位:手势分组条目的锚点与高亮(与 SettingsGroupPage 同机制;
  /// 本页布局手写,不走 SettingsGroupPage,只能自备一份)
  final Map<String, GlobalKey> _itemKeys = {};
  String? _highlightedId;

  /// 底栏最多 4 项（首页在首、我的在尾固定），见 kMaxBottomNavItems
  int get _maxCount => kMaxBottomNavItems;

  late List<String> _enabledIds;

  @override
  void initState() {
    super.initState();
    _enabledIds = List<String>.from(ref.read(preferencesProvider).bottomNavIds);
    _sanitize();
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
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  /// 校验 + 首页锁 0 位
  void _sanitize() {
    final all = NavEntryRegistry.buildAll();
    final byId = {for (final e in all) e.id: e};
    final locked = NavEntryRegistry.lockedIds();

    final cleaned = <String>[];
    final seen = <String>{};

    // 首页永远第一位
    const homeId = NavEntryIds.home;
    if (byId.containsKey(homeId)) {
      cleaned.add(homeId);
      seen.add(homeId);
    }

    for (final id in _enabledIds) {
      if (id == homeId) continue;
      if (!byId.containsKey(id)) continue;
      if (seen.contains(id)) continue;
      cleaned.add(id);
      seen.add(id);
    }

    // 补 locked（profile 等）
    for (final id in locked) {
      if (seen.contains(id)) continue;
      cleaned.add(id);
      seen.add(id);
    }

    _enabledIds = cleaned;
  }

  Future<void> _persist() async {
    await ref
        .read(preferencesProvider.notifier)
        .setBottomNavIds(List<String>.from(_enabledIds));
  }

  void _onReorder(int oldIndex, int newIndex) {
    // 首页锁在第一位，locked 的入口（我的）锁在最后一位
    final locked = NavEntryRegistry.lockedIds();
    if (_enabledIds[oldIndex] == NavEntryIds.home ||
        locked.contains(_enabledIds[oldIndex])) {
      return;
    }
    if (newIndex < 1) newIndex = 1;
    final lastFree =
        _enabledIds.length -
        1 -
        _enabledIds.where((id) => locked.contains(id)).length;
    if (newIndex > lastFree) newIndex = lastFree;
    if (newIndex == oldIndex) return;
    setState(() {
      final item = _enabledIds.removeAt(oldIndex);
      _enabledIds.insert(newIndex, item);
    });
    _persist();
  }

  Future<void> _addEntry(NavEntry entry) async {
    if (_enabledIds.length >= _maxCount) {
      ToastService.showInfo(S.current.bottomNav_editorMaxReached(_maxCount));
      return;
    }
    setState(() => _enabledIds.add(entry.id));
    await _persist();
  }

  Future<void> _removeEntry(NavEntry entry) async {
    if (entry.locked) return;
    if (_enabledIds.length <= _minCount) {
      ToastService.showInfo(S.current.bottomNav_editorMinReached(_minCount));
      return;
    }
    setState(() => _enabledIds.remove(entry.id));
    await _persist();
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(ctx.l10n.bottomNav_editorRestoreDefault),
        content: Text(ctx.l10n.bottomNav_editorRestoreDefaultConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.common_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _enabledIds = NavEntryRegistry.defaultBottomNavIds();
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    final colors = tokens.colors;
    final user = ref.watch(currentUserProvider).value;

    final all = NavEntryRegistry.buildAll();
    final byId = {for (final e in all) e.id: e};
    final enabled = _enabledIds
        .map((id) => byId[id])
        .whereType<NavEntry>()
        .toList();
    final available = all.where((e) => !_enabledIds.contains(e.id)).toList();

    final meta = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.m,
        AppSpace.s,
        AppSpace.m,
        AppSpace.s,
      ),
      child: Semantics(header: true, child: Text(text, style: meta)),
    );

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(
        title: l10n.bottomNav_title,
        slotWidth: 100,
        trailing: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(AppSize.hit, AppSize.hit),
              padding: EdgeInsets.zero,
              textStyle: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta),
            ),
            onPressed: _restoreDefault,
            child: Text(l10n.bottomNav_editorRestoreDefault),
          ),
        ],
      ),
      body: ReadableBody(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                AppSpace.s,
                AppSpace.pageMargin,
                MediaQuery.paddingOf(context).bottom + AppSpace.x32,
              ),
              // 搜索定位目标(手势分组)在页尾,懒加载不挂载会导致 ensureVisible
              // 拿不到 context;带 highlightId 时强制全量布局(与 SettingsGroupPage 同策)
              scrollCacheExtent: widget.highlightId != null
                  ? const ScrollCacheExtent.pixels(double.maxFinite)
                  : null,
              children: [
                // 顶部浮动胶囊实时预览（卡片内）
                _PreviewCard(entries: enabled),
                const SizedBox(height: AppSpace.xl),
                header(l10n.bottomNav_shownHeader),
                SegmentedCardGroup(
                  children: [
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: _onReorder,
                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                      onReorderEnd: (_) => HapticFeedback.selectionClick(),
                      itemCount: enabled.length,
                      itemBuilder: (ctx, i) {
                        final e = enabled[i];
                        final pinned = e.locked || e.id == NavEntryIds.home;
                        return _EnabledTile(
                          key: ValueKey('enabled-${e.id}'),
                          entry: e,
                          index: i,
                          pinned: pinned,
                          canRemove: !pinned && enabled.length > _minCount,
                          onRemove: () => _removeEntry(e),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                header(l10n.bottomNav_editorAvailable),
                if (available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                    child: Text(
                      l10n.bottomNav_editorEmptyAvailable,
                      style: meta,
                    ),
                  )
                else
                  SegmentedCardGroup(
                    children: [
                      for (final entry in available)
                        _AvailableTile(
                          entry: entry,
                          canAdd:
                              NavEntryRegistry.isAvailable(entry, user) &&
                              enabled.length < _maxCount,
                          needsLogin: entry.requiresLogin && user == null,
                          onAdd: () => _addEntry(entry),
                        ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.m,
                    AppSpace.s,
                    AppSpace.m,
                    0,
                  ),
                  child: Text(l10n.bottomNav_footerMax(_maxCount), style: meta),
                ),
                const SizedBox(height: AppSpace.xl),
                for (final group in buildBottomNavGroups(context))
                  _GestureGroup(
                    group: group,
                    itemKeys: _itemKeys,
                    highlightedId: _highlightedId,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 预览卡：surface/elevated 卡片里放一条和真实底栏同款的浮动胶囊
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.entries});

  final List<NavEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: FloatingTabBar(
            items: [
              for (final e in entries.take(kMaxBottomNavItems))
                FloatingTabItem(
                  icon: e.selectedIconData,
                  label: e.label(context),
                ),
            ],
            currentIndex: 0,
            onTap: (_) {},
          ),
        ),
      ),
    );
  }
}

/// 已显示的一行：首页 / 我的带 lock 固定首尾，其余 circle-minus 移除 + grip 拖动
class _EnabledTile extends StatelessWidget {
  const _EnabledTile({
    required super.key,
    required this.entry,
    required this.index,
    required this.pinned,
    required this.canRemove,
    required this.onRemove,
  });

  final NavEntry entry;
  final int index;
  final bool pinned;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final name = entry.label(context);
    return ListTile(
      leading: pinned
          ? SizedBox.square(
              dimension: AppSize.hit,
              child: Icon(
                AppIcons.lock,
                size: AppSize.iconM,
                color: colors.textMeta,
                semanticLabel: l10n.bottomNav_editorLockedHint,
              ),
            )
          : AppIconButton(
              icon: AppIcons.removeCircle,
              color: colors.textDestructive,
              semanticLabel: l10n.bottomNav_removeLabel(name),
              onPressed: canRemove ? onRemove : null,
            ),
      title: Row(
        children: [
          Icon(
            entry.selectedIconData,
            size: AppSize.iconM,
            color: colors.brandPrimary,
          ),
          const SizedBox(width: AppSpace.m),
          Expanded(child: Text(name)),
        ],
      ),
      trailing: pinned
          ? Padding(
              padding: const EdgeInsets.only(right: AppSpace.xs),
              child: Text(
                entry.id == NavEntryIds.home
                    ? l10n.bottomNav_pinnedFirst
                    : l10n.bottomNav_pinnedLast,
                style: Theme.of(context).textTheme.bodySmall!
                    .merge(tokens.text.meta)
                    .copyWith(color: colors.textMeta),
              ),
            )
          : ReorderableDragStartListener(
              index: index,
              child: SizedBox.square(
                dimension: AppSize.hit,
                child: Icon(
                  AppIcons.menu,
                  size: AppSize.iconM,
                  color: colors.textMeta,
                  semanticLabel: l10n.bottomNav_dragLabel(name),
                ),
              ),
            ),
    );
  }
}

/// 可添加的一行：circle-plus brand
class _AvailableTile extends StatelessWidget {
  const _AvailableTile({
    required this.entry,
    required this.canAdd,
    required this.needsLogin,
    required this.onAdd,
  });

  final NavEntry entry;
  final bool canAdd;
  final bool needsLogin;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final name = entry.label(context);
    return ListTile(
      leading: AppIconButton(
        icon: AppIcons.addCircle,
        color: canAdd ? colors.brandPrimary : colors.textMeta,
        semanticLabel: context.l10n.bottomNav_addLabel(name),
        onPressed: canAdd ? onAdd : null,
      ),
      title: Row(
        children: [
          Icon(entry.iconData, size: AppSize.iconM, color: colors.textPrimary),
          const SizedBox(width: AppSpace.m),
          Expanded(child: Text(name)),
        ],
      ),
      subtitle: needsLogin
          ? Text(
              context.l10n.bottomNav_editorRequiresLogin,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: colors.textMeta),
            )
          : null,
      onTap: canAdd ? onAdd : null,
    );
  }
}

/// 设置分组：读取 [buildBottomNavGroups] 的 SettingsGroup，
/// 用 SettingsRenderer 渲染 items（先按可见性过滤，避免隐藏项零高占位
/// 顶掉分段卡片组尾的大圆角）
class _GestureGroup extends ConsumerWidget {
  const _GestureGroup({
    required this.group,
    required this.itemKeys,
    required this.highlightedId,
  });
  final SettingsGroup group;
  final Map<String, GlobalKey> itemKeys;
  final String? highlightedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    // 隐藏项（如依赖前置开关的条目）不进卡片组，否则零高占位会顶掉
    // 组尾的大圆角（SegmentedCardGroup 按位置分配圆角）
    final visibleItems = group.items
        .where((item) => item.isVisible(ref))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.m,
            AppSpace.s,
            AppSpace.m,
            AppSpace.s,
          ),
          child: Semantics(
            header: true,
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.bodySmall!
                  .merge(tokens.text.meta)
                  .copyWith(color: tokens.colors.textMeta),
            ),
          ),
        ),
        SegmentedCardGroup(
          children: [
            for (final item in visibleItems)
              AnimatedContainer(
                key: itemKeys.putIfAbsent(item.id, () => GlobalKey()),
                duration: const Duration(milliseconds: 500),
                color: highlightedId == item.id
                    ? tokens.colors.brandPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
                child: SettingsRenderer(model: item),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}
