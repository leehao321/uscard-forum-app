import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../providers/category_provider.dart';
import '../../providers/topic_list/tab_state_provider.dart'
    show currentTabCategoryIdProvider;
import '../../providers/leaderboard_provider.dart';
import 'leaderboard_topic_list.dart' show leaderboardLabel;
import '../../utils/dialog_utils.dart';
import '../../widgets/topic/category_tab_manager_sheet.dart'
    show PinnedCategoryEditPage;
import '../category_topics_page.dart';
import '../tag_topics_page.dart';

/// 「全部分类」半屏（计划 §5 M3）：顶部「分类 / 标签」两项页内筛选，
/// 分类页按父 / 子分类缩进列出，点一项进入该分类的话题页；底部「编辑
/// 分类条」进入拖动排序页。
Future<void> showAllCategoriesSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AllCategoriesSheet(),
  );
}

class _AllCategoriesSheet extends ConsumerStatefulWidget {
  const _AllCategoriesSheet();

  @override
  ConsumerState<_AllCategoriesSheet> createState() =>
      _AllCategoriesSheetState();
}

class _AllCategoriesSheetState extends ConsumerState<_AllCategoriesSheet> {
  int _page = 0;

  void _open(Widget page) {
    // 先关半屏，再在首页所在的导航器里压入新页
    final navigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppSheetScaffold(
      title: l10n.category_allCategories,
      contentPadding: EdgeInsets.zero,
      maxHeightFactor: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterTabs(
            labels: [l10n.category_categories, l10n.tag_tabTags],
            selectedIndex: _page,
            onSelected: (i) => setState(() => _page = i),
          ),
          if (_page == 0)
            _BrowseModeGroup(onDone: () => Navigator.of(context).pop()),
          Flexible(
            child: _page == 0
                ? _CategoryList(
                    onOpen: _open,
                    onEditBar: () => _open(const PinnedCategoryEditPage()),
                  )
                : _TagList(onOpen: _open),
          ),
        ],
      ),
    );
  }
}

/// 分组「浏览方式」：全部 / 精彩 / 难绷（当前项打勾），和分类条、标题菜单同一个状态；
/// 站点没有榜单徽章时整组不出现
class _BrowseModeGroup extends ConsumerWidget {
  const _BrowseModeGroup({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kinds = availableLeaderboards();
    if (kinds.isEmpty) return const SizedBox.shrink();
    final tokens = context.tokens;
    final mode = ref.watch(homeBrowseModeProvider);
    final categoryId = ref.watch(currentTabCategoryIdProvider);
    final style = Theme.of(context).textTheme.bodyLarge!
        .merge(tokens.text.control)
        .copyWith(color: tokens.colors.textPrimary);

    Widget row(String label, bool checked, VoidCallback onTap) => Semantics(
      selected: checked,
      child: AppPressable(
        highlight: true,
        onTap: () {
          onTap();
          onDone();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.row48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.pageMargin + AppSpace.m,
            ),
            child: Row(
              children: [
                Expanded(child: Text(label, style: style)),
                if (checked)
                  Icon(
                    AppIcons.check,
                    size: AppSize.iconM,
                    color: tokens.colors.brandPrimary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pageMargin + AppSpace.m,
            AppSpace.m,
            AppSpace.pageMargin + AppSpace.m,
            AppSpace.xs,
          ),
          child: Text(
            context.l10n.leaderboard_browseMode,
            style: Theme.of(context).textTheme.bodySmall!
                .merge(tokens.text.meta)
                .copyWith(color: tokens.colors.textMeta),
          ),
        ),
        row(
          context.l10n.common_all,
          mode == null && categoryId == null,
          () => ref.read(homeShowAllSignalProvider.notifier).state++,
        ),
        for (final kind in kinds) ...[
          const AppHairline(
            indent: AppSpace.pageMargin + AppSpace.m,
            endIndent: AppSpace.pageMargin,
          ),
          row(
            leaderboardLabel(context, kind),
            mode == kind,
            () => ref.read(homeBrowseModeProvider.notifier).state = kind,
          ),
        ],
        const AppHairline(),
      ],
    );
  }
}

/// 分类分组（补充页「全部分类」44:1951）：分组页眉「分类」+ 右侧「编辑分类条」；
/// 父分类行 = 名字 + 话题数（13 meta）+ 展开 chevron（展开 chevron-down、收起
/// chevron-right，没有子分类就没有 chevron），子分类缩进 32，行间发丝线按层级缩进
/// （父层 12、子层 32）。话题数取站点分类数据里的 `topic_count`，没有就不显示。
class _CategoryList extends ConsumerStatefulWidget {
  const _CategoryList({required this.onOpen, required this.onEditBar});

  final void Function(Widget page) onOpen;
  final VoidCallback onEditBar;

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final categories = ref.watch(categoriesProvider);
    final visible = ref.watch(visibleCategoryIdsProvider);
    return categories.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (all) {
        final shown = [
          for (final c in all)
            if (visible == null || visible.contains(c.id)) c,
        ];
        final top = shown.where((c) => c.parentCategoryId == null).toList();
        final children = <int, List<Category>>{
          for (final p in top)
            p.id: [
              for (final c in shown)
                if (c.parentCategoryId == p.id) c,
            ],
        };
        final meta = Theme.of(context).textTheme.bodySmall!
            .merge(tokens.text.meta)
            .copyWith(color: tokens.colors.textMeta);

        final rows = <Widget>[];
        void addRow(Category c, int depth, {bool? expanded}) {
          if (rows.isNotEmpty) {
            rows.add(
              AppHairline(
                indent:
                    AppSpace.pageMargin +
                    (depth == 0 ? AppSpace.m : AppSpace.x32),
                endIndent: 0,
              ),
            );
          }
          rows.add(
            _CategoryRow(
              category: c,
              depth: depth,
              expanded: expanded,
              meta: meta,
              onTap: () {
                if (expanded != null) {
                  setState(() {
                    if (!_expanded.remove(c.id)) _expanded.add(c.id);
                  });
                } else {
                  widget.onOpen(CategoryTopicsPage(category: c));
                }
              },
            ),
          );
        }

        for (final parent in top) {
          final kids = children[parent.id]!;
          final open = _expanded.contains(parent.id);
          addRow(parent, 0, expanded: kids.isEmpty ? null : open);
          if (open) {
            for (final kid in kids) {
              addRow(kid, 1);
            }
          }
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.pageMargin + AppSpace.m,
                  AppSpace.m,
                  AppSpace.pageMargin + AppSpace.m,
                  AppSpace.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.category_categories,
                        style: meta,
                      ),
                    ),
                    AppPressable(
                      onTap: widget.onEditBar,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSize.hit,
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            context.l10n.topic_editCategoryBar,
                            style: meta.copyWith(
                              color: tokens.colors.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...rows,
            ],
          ),
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.depth,
    required this.expanded,
    required this.meta,
    required this.onTap,
  });

  final Category category;
  final int depth;

  /// null = 没有子分类（行尾没有 chevron）；true / false = 已展开 / 已收起
  final bool? expanded;
  final TextStyle meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.bodyLarge!
        .merge(tokens.text.control)
        .copyWith(color: tokens.colors.textPrimary);
    final count = category.topicCount;
    return Semantics(
      expanded: expanded,
      child: AppPressable(
        highlight: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.row48),
          child: Padding(
            padding: EdgeInsets.only(
              left:
                  AppSpace.pageMargin +
                  (depth == 0 ? AppSpace.m : AppSpace.x32),
              right: AppSpace.pageMargin + AppSpace.m,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (count != null)
                  Text(_formatCount(context, count), style: meta),
                if (expanded != null) ...[
                  const SizedBox(width: AppSpace.s),
                  Icon(
                    expanded! ? AppIcons.chevronDown : AppIcons.chevronRight,
                    size: AppSize.iconS,
                    color: tokens.colors.textMeta,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 话题数：中文 ≥ 1 万写成「2.1 万」，其余加千分位（「3,120」）
String _formatCount(BuildContext context, int n) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  if (zh && n >= 10000) {
    final v = (n / 10000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v} 万';
  }
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

class _TagList extends ConsumerWidget {
  const _TagList({required this.onOpen});

  final void Function(Widget page) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    return tags.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (names) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.pageMargin),
        child: Wrap(
          spacing: AppSpace.s,
          children: [
            for (final name in names)
              FilterPill(
                label: '#$name',
                showChevron: false,
                onTap: () => onOpen(TagTopicsPage(tagName: name)),
              ),
          ],
        ),
      ),
    );
  }
}
