import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/category.dart';
import '../../providers/category_provider.dart';
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
    final tokens = context.tokens;
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
          Flexible(
            child: _page == 0
                ? _CategoryList(onOpen: _open)
                : _TagList(onOpen: _open),
          ),
          AppPressable(
            highlight: true,
            onTap: () => _open(const PinnedCategoryEditPage()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSize.row48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.pageMargin,
                ),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.edit,
                      size: AppSize.iconM,
                      color: tokens.colors.brandPrimary,
                    ),
                    const SizedBox(width: AppSpace.m),
                    Text(
                      l10n.topic_editCategoryBar,
                      style: Theme.of(context).textTheme.bodyLarge!
                          .merge(tokens.text.control)
                          .copyWith(color: tokens.colors.brandPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.onOpen});

  final void Function(Widget page) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final top = shown.where((c) => c.parentCategoryId == null);
        final rows = <(Category, int)>[];
        for (final parent in top) {
          rows.add((parent, 0));
          for (final child in shown) {
            if (child.parentCategoryId == parent.id) rows.add((child, 1));
          }
        }
        final style = Theme.of(context).textTheme.bodyLarge!
            .merge(tokens.text.control)
            .copyWith(color: tokens.colors.textPrimary);
        return ListView.separated(
          shrinkWrap: true,
          itemCount: rows.length,
          separatorBuilder: (_, _) => const AppHairline(
            indent: AppSpace.pageMargin,
            endIndent: AppSpace.pageMargin,
          ),
          itemBuilder: (context, i) {
            final (category, depth) = rows[i];
            return AppPressable(
              highlight: true,
              onTap: () => onOpen(CategoryTopicsPage(category: category)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSize.row48),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: AppSpace.pageMargin + depth * AppSpace.xl,
                    right: AppSpace.pageMargin,
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
                      Icon(
                        AppIcons.chevronRight,
                        size: AppSize.iconS,
                        color: tokens.colors.textMeta,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
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
