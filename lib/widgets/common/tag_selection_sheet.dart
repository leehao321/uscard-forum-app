import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:m3e_ui/m3e_ui.dart';

import 'dart:async';

import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/tag_search_result.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/toast_service.dart';
import 'package:fluxdo/widgets/common/topic_badges.dart';

/// 搜索框高度（Figma「首页 · 添加标签」：40 高填充框）
const double _fieldHeight = 40;

class TagSelectionSheet extends StatefulWidget {
  /// 分类 ID（用于联动过滤标签）
  final int? categoryId;

  /// 初始可用标签（降级使用）
  final List<String> availableTags;

  /// 已选中的标签
  final List<String> selectedTags;

  /// 最大可选标签数
  final int maxTags;

  /// 最小必选标签数（仅 filterForInput=true 时有效）
  final int minTags;

  /// 是否为创建话题模式（true=创建话题，false=筛选/浏览）
  ///
  /// 创建话题时：发送 filterForInput 给 API，显示必选标签组提示和最小标签数约束
  /// 筛选浏览时：不发送 filterForInput，不显示必选标签组和最小标签数约束
  final bool filterForInput;

  const TagSelectionSheet({
    super.key,
    this.categoryId,
    required this.availableTags,
    required this.selectedTags,
    this.maxTags = 5,
    this.minTags = 0,
    this.filterForInput = false,
  });

  @override
  State<TagSelectionSheet> createState() => _TagSelectionSheetState();
}

class _TagSelectionSheetState extends State<TagSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late List<String> _currentSelectedTags;

  /// 动态标签搜索结果
  List<TagInfo> _searchResults = [];

  /// 必选标签组信息
  RequiredTagGroup? _requiredTagGroup;

  /// 是否正在加载
  bool _isLoading = false;

  /// 是否已初始化（首次加载完成）
  bool _initialized = false;

  /// 搜索防抖计时器
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentSelectedTags = List.from(widget.selectedTags);
    // 初始化加载标签
    _searchTags('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 搜索标签（带防抖）
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _searchTags(query);
    });
  }

  /// 调用 API 搜索标签
  Future<void> _searchTags(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await DiscourseService().searchTags(
        query: query,
        categoryId: widget.categoryId,
        selectedTags: _currentSelectedTags,
        limit: 8,
        filterForInput: widget.filterForInput,
      );

      if (!mounted) return;

      setState(() {
        _searchResults = result.results;
        // 仅创建话题模式下处理必选标签组
        _requiredTagGroup = widget.filterForInput
            ? result.requiredTagGroup
            : null;
        _isLoading = false;
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _initialized = true;
        // 降级使用传入的静态标签列表
        if (_searchResults.isEmpty) {
          _searchResults = widget.availableTags
              .where(
                (t) =>
                    query.isEmpty ||
                    t.toLowerCase().contains(query.toLowerCase()),
              )
              .map((t) => TagInfo(name: t, text: t, count: 0))
              .toList();
        }
      });
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_currentSelectedTags.contains(tag)) {
        _currentSelectedTags.remove(tag);
      } else {
        if (_currentSelectedTags.length >= widget.maxTags) {
          ToastService.showInfo(S.current.tag_maxTagsReached(widget.maxTags));
          return;
        }
        _currentSelectedTags.add(tag);
      }
    });

    // 选中后重新搜索以更新 required_tag_group 状态
    _searchTags(_searchController.text);
  }

  /// 选中的标签和打开时不一样（有变化才出「确定」）
  bool get _changed {
    final a = [...widget.selectedTags]..sort();
    final b = [..._currentSelectedTags]..sort();
    return !listEquals(a, b);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;

    // 构建提示文本
    final l10n = context.l10n;
    String hintText;
    if (widget.filterForInput && _requiredTagGroup != null) {
      // 创建话题模式：有必选标签组要求
      hintText = l10n.tag_requiredTagGroupHint(
        _requiredTagGroup!.name,
        _requiredTagGroup!.minCount,
      );
    } else if (widget.filterForInput && widget.minTags > 0) {
      if (_currentSelectedTags.length < widget.minTags) {
        hintText = l10n.tag_searchWithMin(
          _currentSelectedTags.length,
          widget.minTags,
        );
      } else {
        hintText = l10n.tag_searchWithMax(
          _currentSelectedTags.length,
          widget.maxTags,
        );
      }
    } else {
      // 筛选模式或无特殊约束
      hintText = _currentSelectedTags.isEmpty
          ? l10n.tag_searchHint
          : l10n.tag_searchWithCount(_currentSelectedTags.length);
    }

    // 过滤出未选中的标签
    final displayTags = _searchResults
        .where((t) => !_currentSelectedTags.contains(t.name))
        .toList();

    final hintColor = (widget.filterForInput && _requiredTagGroup != null)
        ? colors.brandPrimary
        : (widget.filterForInput &&
                  _currentSelectedTags.length < widget.minTags
              ? colors.textDestructive
              : colors.textMeta);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Figma「首页 · 添加标签」：头行「添加标签」+ 关闭；搜索框；内容区
        return AppSheetScaffold(
          expandToFill: true,
          title: l10n.topic_addTags,
          actions: [
            // 有改动才出现：确定后把选中的标签带回去；没改动时只能关闭
            if (_changed)
              TextButton(
                onPressed: () => Navigator.pop(context, _currentSelectedTags),
                child: Text(
                  l10n.common_confirm,
                  style: TextStyle(color: colors.brandPrimary),
                ),
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 必选标签组提示（仅创建话题模式）
              if (widget.filterForInput && _requiredTagGroup != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.m,
                    vertical: AppSpace.s,
                  ),
                  margin: const EdgeInsets.only(bottom: AppSpace.m),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radius.field),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.info,
                        size: AppSize.iconS,
                        color: colors.brandPrimary,
                      ),
                      const SizedBox(width: AppSpace.s),
                      Expanded(
                        child: Text(
                          l10n.tag_requiredGroupWarning(
                            _requiredTagGroup!.name,
                            _requiredTagGroup!.minCount,
                          ),
                          style: theme.textTheme.bodySmall
                              ?.merge(tokens.text.meta)
                              .copyWith(color: colors.brandPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              // 搜索框：40 高填充框，搜索图标 16 + 17 号输入
              Container(
                key: const ValueKey('tag-search-field'),
                height: _fieldHeight,
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radius.field),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: AppSpace.m),
                    _isLoading
                        ? const SizedBox(
                            width: AppSize.iconS,
                            height: AppSize.iconS,
                            child: CupertinoActivityIndicator(
                              radius: AppSize.iconS / 2,
                            ),
                          )
                        : Icon(
                            AppIcons.search,
                            size: AppSize.iconS,
                            color: colors.textMeta,
                          ),
                    const SizedBox(width: AppSpace.s),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        style: theme.textTheme.bodyLarge
                            ?.merge(tokens.text.control)
                            .copyWith(color: colors.textPrimary),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: theme.textTheme.bodyLarge
                              ?.merge(tokens.text.control)
                              .copyWith(color: hintColor),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          setState(() {});
                          _onSearchChanged(value);
                        },
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      AppIconButton(
                        icon: AppIcons.cancelCircle,
                        size: AppSize.iconS,
                        semanticLabel: l10n.common_clear,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _searchTags('');
                        },
                      )
                    else
                      const SizedBox(width: AppSpace.m),
                  ],
                ),
              ),

              // 已选标签展示区
              if (_currentSelectedTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.m),
                  child: Wrap(
                    spacing: AppSpace.s,
                    runSpacing: AppSpace.s,
                    children: _currentSelectedTags.map((tag) {
                      return RemovableTagBadge(
                        name: tag,
                        onDeleted: () => _toggleTag(tag),
                        size: const BadgeSize(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          radius: 8,
                          iconSize: 12,
                          fontSize: AppFontSize.meta,
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // 标签列表
              Expanded(
                child: !_initialized
                    ? const Center(child: LoadingSpinner())
                    : displayTags.isEmpty
                    ? _buildEmpty(context)
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: displayTags.length,
                        padding: EdgeInsets.only(
                          top: AppSpace.s,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        itemBuilder: (context, index) {
                          final tag = displayTags[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: TagBadge(
                              name: tag.text,
                              size: const BadgeSize(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                radius: 6,
                                iconSize: 12,
                                fontSize: AppFontSize.meta,
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                            subtitle: tag.count > 0
                                ? Text(l10n.tag_topicCount(tag.count))
                                : null,
                            trailing:
                                _currentSelectedTags.length >= widget.maxTags
                                ? Icon(AppIcons.block, color: colors.textMeta)
                                : Icon(
                                    AppIcons.addCircle,
                                    color: colors.brandPrimary,
                                  ),
                            onTap: () => _toggleTag(tag.name),
                            enabled:
                                _currentSelectedTags.length < widget.maxTags,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 空状态（Figma「添加标签 · 无可用标签」）：48 标签图标 + 标题 + 13 号说明，居中。
  /// 搜索没有结果时只显示标题「未找到相关标签」。
  Widget _buildEmpty(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final l10n = context.l10n;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final searching = _searchController.text.isNotEmpty;
    final title = searching ? l10n.tag_noTagsFound : l10n.tag_noTags;
    final message = searching
        ? null
        : (widget.categoryId != null
              ? l10n.tag_noTagsInCategoryDesc
              : l10n.tag_noTagsDesc);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x40),
        child: Column(
          key: const ValueKey('tag-empty-state'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(AppIcons.tags, size: 48, color: colors.textMeta),
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              title,
              textAlign: TextAlign.center,
              style: base
                  .merge(tokens.text.control)
                  .copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpace.s),
              Text(
                message,
                textAlign: TextAlign.center,
                style: base
                    .merge(tokens.text.meta)
                    .copyWith(color: colors.textMeta),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
