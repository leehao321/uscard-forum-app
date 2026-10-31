import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/category.dart';
import '../models/search_filter.dart';
import '../providers/discourse_providers.dart';
import '../providers/pinned_categories_provider.dart';
import '../providers/shortcut_provider.dart';
import '../models/shortcut_binding.dart';
import '../services/toast_service.dart';
import '../utils/dialog_utils.dart';
import '../utils/platform_utils.dart';
import '../widgets/common/tag_selection_sheet.dart';
import 'home/all_categories_sheet.dart';
import 'home/category_bar.dart';
import 'home/home_signals.dart';
import 'home/home_topic_list.dart';
import 'home/title_menu.dart';

export 'home/home_signals.dart';

/// 首页（0.4.0 v2，计划 §5 M3，对照 Figma「首页 · 带发帖入口」）。
///
/// 上到下：导航栏（标题菜单「最新 ▾」+ 右槽发帖）→ 分类条（全部 + 置顶
/// 分类 +「全部分类」）→ 话题列表。分类切换只靠点选，不再左右横滑，列表
/// 区也不再随滚动收放头部。
class TopicsPage extends ConsumerStatefulWidget {
  const TopicsPage({
    super.key,
    this.onSearchRequested,
    this.externalCategoryId,
    this.externalTag,
    this.isActive = true,
    this.onCreateTopic,
  });

  final ValueChanged<SearchFilter?>? onSearchRequested;
  final int? externalCategoryId;
  final String? externalTag;

  /// 宿主底栏 tab 是否活跃(IndexedStack 常驻:不活跃时本页的 master
  /// 快捷键注册须失效,否则截胡其他 tab 的按键)。
  final bool isActive;

  /// 导航栏右槽「发帖」；null 或未登录时不显示
  final VoidCallback? onCreateTopic;

  @override
  ConsumerState<TopicsPage> createState() => _TopicsPageState();
}

class _TopicsPageState extends ConsumerState<TopicsPage> {
  /// 0 = 全部，i = 第 i 个置顶分类
  int _index = 0;
  List<int> _visiblePinnedIds = const [];
  (int?, String?)? _lastExternalSelection;
  bool _invalidateScheduled = false;
  late final ShortcutScopeBinding _tabShortcutBinding = ShortcutScopeBinding(
    ref: ref,
    scope: ShortcutScope.master,
    enabled: () => widget.isActive,
  );

  int? _categoryIdAt(int index, List<int> pinnedIds) =>
      index <= 0 || index - 1 >= pinnedIds.length ? null : pinnedIds[index - 1];

  int? get _currentCategoryId => _categoryIdAt(_index, _visiblePinnedIds);

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) _tabShortcutBinding.disposeDeferred();
    super.dispose();
  }

  void _registerTabShortcuts() {
    if (!mounted) return;
    _tabShortcutBinding.register(context, {
      ShortcutAction.previousTab: () {
        if (_index > 0) _select(_index - 1);
      },
      ShortcutAction.nextTab: () {
        if (_index < _visiblePinnedIds.length) _select(_index + 1);
      },
    });
  }

  /// 切换分类：先处理 stale（全局筛选变化时留下的陈旧分类），再记下当前
  void _select(int index) {
    if (index == _index) return;
    final categoryId = _categoryIdAt(index, _visiblePinnedIds);
    final stale = ref.read(staleTabsProvider);
    if (stale.contains(categoryId)) {
      ref.read(topicListProvider(categoryId).notifier).refresh();
      ref.read(staleTabsProvider.notifier).state = stale.difference({
        categoryId,
      });
    }
    setState(() => _index = index);
    ref.read(currentTabCategoryIdProvider.notifier).state = categoryId;
    ref.read(activeSidebarCategoryIdProvider.notifier).state = categoryId;
  }

  /// 全局筛选 / 排序变化：刷新当前分类，其余标记为 stale，切过去时再刷新。
  /// 微任务去抖，多个参数连续变化只请求一次（如登出时重置筛选 + 排序）。
  void _invalidateTopicTabs(List<int> pinnedIds) {
    if (_invalidateScheduled) return;
    _invalidateScheduled = true;
    Future.microtask(() {
      _invalidateScheduled = false;
      if (!mounted) return;
      final current = _currentCategoryId;
      ref.read(topicListProvider(current).notifier).refresh();
      final stale = <int?>{
        for (final id in [null, ...pinnedIds])
          if (id != current) id,
      };
      final existing = ref.read(staleTabsProvider);
      ref.read(staleTabsProvider.notifier).state = {...existing, ...stale};
    });
  }

  Future<void> _openTagSelection() async {
    final categoryId = _currentCategoryId;
    final currentTags = ref.read(tabTagsProvider(categoryId));
    final availableTags = ref
        .read(tagsProvider)
        .when(
          data: (tags) => tags,
          loading: () => <String>[],
          error: (e, s) => <String>[],
        );
    final result = await showAppBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TagSelectionSheet(
        categoryId: categoryId,
        availableTags: availableTags,
        selectedTags: currentTags,
        maxTags: 99,
      ),
    );
    if (result != null && mounted) {
      ref.read(tabTagsProvider(categoryId).notifier).state = result;
    }
  }

  String _dismissLabel(TopicListFilter filter) {
    if (filter == TopicListFilter.newTopics) {
      return switch (ref.read(topicNewSubsetProvider)) {
        NewSubset.topics => context.l10n.topic_filterNewTopicsShort,
        NewSubset.replies => context.l10n.topic_filterNewRepliesShort,
        NewSubset.all => context.l10n.topic_filterNewAllShort,
      };
    }
    return context.l10n.topics_unreadTopics;
  }

  void _confirmDismiss(TopicListFilter filter) {
    final label = _dismissLabel(filter);
    showAppDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.topics_dismissConfirmTitle),
        content: Text(context.l10n.topics_dismissConfirmContent(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _doDismiss();
            },
            child: Text(context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _doDismiss() async {
    try {
      await ref
          .read(topicListProvider(_currentCategoryId).notifier)
          .dismissAll();
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.common_operationFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _registerTabShortcuts(),
      );
    }

    final isLoggedIn = ref.watch(currentUserProvider).value != null;
    final savedPinnedIds = ref.watch(pinnedCategoriesProvider);
    final allPinnedIds = <int>[
      ...savedPinnedIds,
      if (widget.externalCategoryId case final id?
          when !savedPinnedIds.contains(id))
        id,
    ];
    final categoryMap = ref.watch(categoryMapProvider).value;
    // 过滤掉当前用户无权限访问的分类
    final visibleIds = ref.watch(visibleCategoryIdsProvider);
    final pinnedIds = visibleIds != null
        ? allPinnedIds.where(visibleIds.contains).toList()
        : allPinnedIds;
    ref.watch(topicFilterProvider);

    _visiblePinnedIds = pinnedIds;
    if (_index > pinnedIds.length) _index = 0;

    // 外部指定的分类 / 标签（桌面侧栏进入分类等）
    final external = (widget.externalCategoryId, widget.externalTag);
    if (_lastExternalSelection != external) {
      _lastExternalSelection = external;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final id = widget.externalCategoryId;
        final index = id == null ? 0 : pinnedIds.indexOf(id) + 1;
        if (index >= 0 && index <= pinnedIds.length) _select(index);
        // 没变就不写：写同值的新列表会触发列表重刷（启动时白刷一次）
        final nextTags = widget.externalTag == null
            ? const <String>[]
            : [widget.externalTag!];
        if (!listEquals(ref.read(tabTagsProvider(id)), nextTags)) {
          ref.read(tabTagsProvider(id).notifier).state = nextTags;
        }
      });
    }

    // 桌面侧栏选分类：同步切换
    ref.listen(activeSidebarCategoryIdProvider, (prev, next) {
      if (next == null) {
        if (_index != 0) _select(0);
        return;
      }
      final target = _visiblePinnedIds.indexOf(next);
      if (target >= 0) _select(target + 1);
    });

    // 全局筛选 / 排序变化
    ref.listen(topicListGlobalParamsSignal, (_, _) {
      _invalidateTopicTabs(pinnedIds);
    });

    final currentId = _currentCategoryId;
    final labels = [
      context.l10n.common_all,
      for (final id in pinnedIds) categoryMap?[id]?.name ?? '',
    ];

    return ColoredBox(
      color: context.tokens.colors.surfacePage,
      child: Column(
        children: [
          AppNavBar(
            slotWidth: 90,
            automaticallyImplyLeading: false,
            titleWidget: HomeTitleMenu(
              isLoggedIn: isLoggedIn,
              categoryId: currentId,
              onSelectTags: _openTagSelection,
              onDismissAll: _confirmDismiss,
            ),
            trailing: [
              if (isLoggedIn && widget.onCreateTopic != null)
                AppIconButton(
                  icon: AppIcons.compose,
                  semanticLabel: context.l10n.topicsScreen_createTopic,
                  onPressed: widget.onCreateTopic,
                ),
            ],
          ),
          HomeCategoryBar(
            labels: labels,
            selectedIndex: _index.clamp(0, labels.length - 1),
            onSelected: _select,
            onReselect: () => ref.read(scrollToTopProvider.notifier).trigger(),
            onOpenAllCategories: () => showAllCategoriesSheet(context),
          ),
          const AppHairline(),
          Expanded(
            child: HomeTopicList(
              key: ValueKey('home-list-$currentId'),
              categoryId: currentId,
              categoryMap: categoryMap ?? const <int, Category>{},
              parentActive: widget.isActive,
            ),
          ),
        ],
      ),
    );
  }
}
