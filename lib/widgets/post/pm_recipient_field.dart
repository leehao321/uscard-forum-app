import 'dart:async';

import 'package:flutter/material.dart';
import 'package:common_ui/common_ui.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../../l10n/s.dart';
import '../../models/mention_user.dart';
import '../../services/discourse/discourse_service.dart';
import '../common/smart_avatar.dart';

/// 私信收件人选择器：已选项显示为可删除的 chip，下方输入即搜。
///
/// 用户与**可发私信的群组**都能作为收件人 —— Discourse 的
/// `target_recipients` 同时接受用户名和群组名（逗号分隔），所以两类共用
/// 一个字符串列表即可，不必分开建模。
///
/// 候选列表走 **Overlay 浮层**（LayerLink 跟随输入框），与编辑器里的 @
/// 补全同一套做法：直接放进 Column 会把标题/正文往下挤，很难看。
class PmRecipientField extends StatefulWidget {
  const PmRecipientField({
    super.key,
    required this.recipients,
    required this.onChanged,
    this.autofocus = false,
    this.groupNames = const {},
    this.onGroupNamesChanged,
    this.inline = false,
  });

  /// 当前已选收件人（用户名 / 群组名）。
  final List<String> recipients;

  final ValueChanged<List<String>> onChanged;

  final bool autofocus;

  /// [recipients] 里哪些是群组。新建私信的 `target_recipients` 用户与群组
  /// 混着收，不需要区分；私信邀请分 invite / invite-group 两个端点，才要
  /// 这份标记。不传即不追踪。
  final Set<String> groupNames;

  final ValueChanged<Set<String>>? onGroupNamesChanged;

  /// 内联形态（新建私信半屏，设计说明 §5.2）：「收件人」标签 + 胶囊 +
  /// 无边框输入同在一行，底部发丝线；false 是对话框里的填充输入框形态。
  final bool inline;

  @override
  State<PmRecipientField> createState() => _PmRecipientFieldState();
}

class _PmRecipientFieldState extends State<PmRecipientField> {
  final _controller = TextEditingController();
  late final _focusNode = FocusNode(onKeyEvent: _handleKey);
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  Timer? _debounce;
  OverlayEntry? _overlay;

  List<MentionUser> _users = const [];
  List<MentionGroup> _groups = const [];
  bool _loading = false;
  String _lastTerm = '';

  /// 当前高亮候选(键盘上下切换,回车确认);新结果回到第一条
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    // 注意:**不要**在失焦时收浮层。点候选项时 ListTile 的 InkWell 会先
    // 抢走焦点,失焦回调会把浮层当场移除,点击就落空了(实测复现)。
    // 浮层的收起时机改为:选中候选 / 无结果 / Esc / dispose。
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 候选总数(用户 + 群组,浮层里按这个顺序排)
  int get _itemCount => _users.length + _groups.length;

  /// 键盘导航:上下切换高亮、回车确认、Esc 关闭。
  ///
  /// 挂在输入框自己的 FocusNode 上,先于 TextField 内部处理拿到按键。
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_itemCount == 0) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlighted = (_highlighted + 1) % _itemCount);
        _overlay?.markNeedsBuild();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _highlighted = (_highlighted - 1 + _itemCount) % _itemCount,
        );
        _overlay?.markNeedsBuild();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _addAt(_highlighted);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _removeOverlay();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 按浮层里的顺序取第 [index] 个候选加入。
  void _addAt(int index) {
    if (index < 0 || index >= _itemCount) return;
    final isGroup = index >= _users.length;
    _add(
      isGroup ? _groups[index - _users.length].name : _users[index].username,
      isGroup: isGroup,
    );
  }

  void _onTermChanged(String term) {
    _debounce?.cancel();
    // 逐字请求会被 CF 盯上（searchUsers 内部已标 isSilent），这里再加一层
    // 防抖，与编辑器 @ 补全同口径。
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(term));
  }

  Future<void> _search(String term) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastTerm = term;
    });
    final result = await DiscourseService().searchUsers(
      term: term,
      // 只要「可发私信的群组」：include_groups 会把发不了私信的群组也列出来
      includeGroups: false,
      includeMessageableGroups: true,
      limit: 6,
    );
    if (!mounted || _lastTerm != term) return;
    setState(() {
      _users = result.users;
      _groups = result.groups;
      _loading = false;
      _highlighted = 0; // 新结果默认选第一条
    });
    _syncOverlay();
  }

  void _syncOverlay() {
    if (_users.isEmpty && _groups.isEmpty) {
      _removeOverlay();
      return;
    }
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  double get _fieldWidth {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  double get _fieldHeight {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? 48;
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    return Positioned(
      width: _fieldWidth,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: Offset(0, _fieldHeight + 4),
        // descendantsAreFocusable:false —— 候选项不抢输入框的焦点,
        // 否则点击瞬间输入框失焦,连打字位置都丢了。
        child: Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          child: Material(
          // v2 候选卡：elevated 底、r12、菜单阴影
          elevation: 8,
          borderRadius: BorderRadius.circular(tokens.radius.card),
          clipBehavior: Clip.antiAlias,
          color: colors.surfaceElevated,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final (i, u) in _users.indexed)
                  ListTile(
                    minTileHeight: AppSize.row48,
                    selected: i == _highlighted,
                    selectedTileColor:
                        colors.brandPrimary.withValues(alpha: 0.12),
                    leading: SmartAvatar(
                      // avatar_template 是**相对路径**(`/user_avatar/…`),
                      // 直接用会加载不出来只剩首字母兜底。走模型自带的
                      // getAvatarUrl:补站点前缀并解析 CDN。
                      imageUrl: u.getAvatarUrl(AppConstants.baseUrl, size: 48),
                      radius: 14,
                      fallbackText: u.username,
                    ),
                    title: Text(
                      u.username,
                      style: theme.textTheme.bodyMedium
                          ?.merge(tokens.text.control)
                          .copyWith(color: colors.textPrimary),
                    ),
                    subtitle: (u.name == null || u.name!.isEmpty)
                        ? null
                        : Text(u.name!, overflow: TextOverflow.ellipsis),
                    onTap: () => _add(u.username, isGroup: false),
                  ),
                for (final (gi, g) in _groups.indexed)
                  ListTile(
                    minTileHeight: AppSize.row48,
                    selected: _users.length + gi == _highlighted,
                    selectedTileColor:
                        colors.brandPrimary.withValues(alpha: 0.12),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.avatarFill,
                      child: Icon(
                        AppIcons.people,
                        size: 16,
                        color: colors.textMeta,
                      ),
                    ),
                    title: Text(
                      g.name,
                      style: theme.textTheme.bodyMedium
                          ?.merge(tokens.text.control)
                          .copyWith(color: colors.textPrimary),
                    ),
                    subtitle: (g.fullName == null || g.fullName!.isEmpty)
                        ? null
                        : Text(g.fullName!, overflow: TextOverflow.ellipsis),
                    onTap: () => _add(g.name, isGroup: true),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _add(String name, {required bool isGroup}) {
    if (name.isEmpty) return;
    // 大小写不敏感去重：Discourse 用户名不区分大小写
    final exists = widget.recipients
        .any((r) => r.toLowerCase() == name.toLowerCase());
    if (!exists) {
      widget.onChanged([...widget.recipients, name]);
      if (isGroup) {
        widget.onGroupNamesChanged?.call({...widget.groupNames, name});
      }
    }
    _controller.clear();
    setState(() {
      _users = const [];
      _groups = const [];
      _lastTerm = '';
    });
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _remove(String name) {
    widget.onChanged(
      widget.recipients.where((r) => r != name).toList(),
    );
    if (widget.groupNames.contains(name)) {
      widget.onGroupNamesChanged?.call(
        widget.groupNames.where((g) => g != name).toSet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final chipStyle = theme.textTheme.bodySmall
        ?.merge(tokens.text.metaStrong)
        .copyWith(color: colors.textPrimary);
    if (widget.inline) return _buildInline(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 收件人行：已选收件人是 44 高的 pill，尾部 x 移除
        if (widget.recipients.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s),
            child: Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.xs,
              children: [
                for (final r in widget.recipients)
                  Container(
                    constraints: const BoxConstraints(minHeight: AppSize.hit),
                    padding: const EdgeInsets.only(left: AppSpace.m),
                    decoration: ShapeDecoration(
                      color: colors.avatarFill,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r, style: chipStyle),
                        AppIconButton(
                          icon: AppIcons.close,
                          size: AppSize.iconS,
                          semanticLabel: S.current.common_remove,
                          color: colors.textMeta,
                          onPressed: () => _remove(r),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        CompositedTransformTarget(
          link: _link,
          child: TextField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            cursorColor: colors.brandPrimary,
            style: theme.textTheme.bodyLarge
                ?.merge(tokens.text.control)
                .copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surfaceElevated,
              hintText: S.current.pm_recipientHint,
              hintStyle: theme.textTheme.bodyLarge
                  ?.merge(tokens.text.control)
                  .copyWith(color: colors.textMeta),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpace.m,
                vertical: AppSpace.m,
              ),
              prefixIcon: Icon(
                AppIcons.follow,
                size: AppSize.iconM,
                color: colors.textMeta,
              ),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radius.field),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onTermChanged,
            // 回车 = 确认当前高亮候选(见 _handleKey)。**不再**把输入原样
            // 当用户名加入 —— 那样能加进不存在的用户,发送时才报错。
            textInputAction: TextInputAction.done,
          ),
        ),
      ],
    );
  }

  Widget _buildInline(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final metaStyle = theme.textTheme.bodySmall
        ?.merge(tokens.text.meta)
        .copyWith(color: colors.textMeta);
    final controlStyle = theme.textTheme.bodyLarge
        ?.merge(tokens.text.control)
        .copyWith(color: colors.textPrimary);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.separator,
            width: AppSpace.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(S.current.pm_recipientLabel, style: metaStyle),
            const SizedBox(width: AppSpace.m),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpace.s,
                runSpacing: AppSpace.xs,
                children: [
                  for (final r in widget.recipients)
                    Container(
                      height: 36,
                      padding: const EdgeInsets.only(left: AppSpace.m),
                      decoration: ShapeDecoration(
                        color: colors.avatarFill,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('@$r', style: controlStyle),
                          // 36 高的胶囊里放 44 热区的 x，向外溢出不撑高
                          SizedBox(
                            width: AppSize.hit,
                            height: 36,
                            child: OverflowBox(
                              maxHeight: AppSize.hit,
                              child: AppIconButton(
                                icon: AppIcons.close,
                                size: AppSize.iconS,
                                semanticLabel: S.current.common_remove,
                                color: colors.textMeta,
                                onPressed: () => _remove(r),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  CompositedTransformTarget(
                    link: _link,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 240,
                      ),
                      child: SizedBox(
                        height: AppSize.hit,
                        child: TextField(
                          key: _fieldKey,
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: widget.autofocus,
                          cursorColor: colors.brandPrimary,
                          style: controlStyle,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: AppSpace.m,
                            ),
                            border: InputBorder.none,
                            hintText: S.current.pm_recipientHint,
                            hintStyle: controlStyle?.copyWith(
                              color: colors.textMeta,
                            ),
                            suffixIcon: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          onChanged: _onTermChanged,
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
