import '../../utils/copy_source_tracker.dart';
import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/toast_service.dart';
import '../../storage/topic_note_store.dart';
import '../../utils/time_utils.dart';
import '../common/app_bottom_sheet.dart';

/// 打开某个话题的笔记，只存在本机。
///
/// 0.4.0（计划 P9）：笔记可以挂在某一楼上。传 [postNumber] 时是「添加笔记」：
/// 顶部是这一楼的引用块（[quote]，可空），下面的输入框写的是这一楼的笔记；
/// 不传时写的是话题级笔记。输入停笔 1 秒、关闭半屏、切到后台都会自动保存，
/// 没有保存按钮。
Future<void> showTopicNoteSheet(
  BuildContext context, {
  required int topicId,
  required String title,
  int? postNumber,
  String? quote,
}) {
  return AppBottomSheet.show<void>(
    context: context,
    style: AppSheetStyle.card,
    title: postNumber == null ? '笔记' : '添加笔记',
    maxHeightFactor: 0.95,
    builder: (_) => TopicNoteSheetBody(
      topicId: topicId,
      title: title,
      postNumber: postNumber,
      quote: quote,
    ),
  );
}

@visibleForTesting
class TopicNoteSheetBody extends StatefulWidget {
  const TopicNoteSheetBody({
    super.key,
    required this.topicId,
    required this.title,
    this.postNumber,
    this.quote,
  });

  final int topicId;
  final String title;
  final int? postNumber;
  final String? quote;

  @override
  State<TopicNoteSheetBody> createState() => _TopicNoteSheetBodyState();
}

class _TopicNoteSheetBodyState extends State<TopicNoteSheetBody>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  List<NoteExcerpt> _excerpts = [];
  Map<int, String> _floorNotes = {};

  /// 话题级文字（不是当前楼层时原样带回去保存）
  String _topicText = '';
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  /// 上次读入或保存的输入框文字
  String _savedText = '';

  /// 概览里点了别的楼层 / 话题笔记后，编辑目标换成它（M-1）
  bool _retargeted = false;
  int? _retargetFloor;

  int? get _floor => _retargeted ? _retargetFloor : widget.postNumber;

  /// 换一个编辑目标：先把当前这一条存掉，再把输入框换成新目标的文字
  void _retarget(int? floor) {
    _saveNow();
    _text.removeListener(_onTextChanged);
    setState(() {
      _retargeted = true;
      _retargetFloor = floor;
      _text.text = floor == null ? _topicText : (_floorNotes[floor] ?? '');
      _savedText = _text.text;
    });
    _text.addListener(_onTextChanged);
  }

  /// 删掉某一楼的笔记（不是当前正在编辑的那一楼）
  void _deleteFloorNote(int floor) {
    setState(() => _floorNotes = {..._floorNotes}..remove(floor));
    _dirty = true;
    _saveNow();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TopicNoteStore.get(widget.topicId).then((note) {
      if (!mounted) return;
      _topicText = note?.text ?? '';
      _floorNotes = {...?note?.floorNotes};
      _text.text = _floor == null ? _topicText : (_floorNotes[_floor!] ?? '');
      _savedText = _text.text;
      // 读完再挂监听，填入旧内容不算改动
      _text.addListener(_onTextChanged);
      setState(() {
        _excerpts = [...?note?.excerpts];
        _loaded = true;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台可能被系统回收，不会走 dispose：离开前台就先存
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _saveNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 关闭时自动保存，不需要单独的保存按钮
    _saveNow();
    _text.dispose();
    super.dispose();
  }

  /// 控制器在光标、选区变化时也会通知：只有文字真的变了才算改动，
  /// 否则点一下输入框也会刷新修改时间，「我的笔记」的排序就乱了
  void _onTextChanged() {
    if (_text.text == _savedText) return;
    _scheduleSave();
  }

  /// 停笔 1 秒后自动保存
  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded || !_dirty) return;
    _dirty = false;
    _savedText = _text.text;
    final floor = _floor;
    final floors = {..._floorNotes};
    var topicText = _topicText;
    if (floor == null) {
      topicText = _text.text;
      _topicText = topicText;
    } else if (_text.text.trim().isEmpty) {
      floors.remove(floor);
    } else {
      floors[floor] = _text.text;
    }
    _floorNotes = floors;
    unawaited(
      TopicNoteStore.save(
        TopicNote(
          topicId: widget.topicId,
          title: widget.title,
          text: topicText,
          excerpts: List.of(_excerpts),
          floorNotes: floors,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _pasteExcerpt() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ToastService.showError('剪贴板里没有文字，先在帖子里选中文字并复制');
      return;
    }
    if (_excerpts.any((e) => e.text == text)) {
      ToastService.showError('这段已经摘录过了');
      return;
    }
    setState(() {
      _excerpts.insert(
        0,
        NoteExcerpt(
          text: text,
          createdAt: DateTime.now(),
          // 来源楼层：优先用最近一次从某一楼复制时记下的，对不上再用当前这一楼
          postNumber: CopySourceTracker.sourceFor(text) ?? _floor,
        ),
      );
    });
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final body = base
        .merge(tokens.text.body)
        .copyWith(color: colors.textPrimary);
    final quote = widget.quote?.trim() ?? '';

    final others = [
      for (final f in (_floorNotes.keys.toList()..sort()))
        if (f != _floor && (_floorNotes[f] ?? '').trim().isNotEmpty) f,
    ];
    // 正在编辑某一楼、话题级笔记也有内容时，给一个回到话题笔记的入口
    final showTopicRow = _floor != null && _topicText.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: meta,
            ),
            const SizedBox(height: AppSpace.m),
            if (_floor != null && quote.isNotEmpty) ...[
              // 引用块：左侧 3px 竖线 + 楼层号 + 摘要
              Semantics(
                container: true,
                label: '引用 第 $_floor 楼',
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 3, color: colors.quoteRule),
                      const SizedBox(width: AppSpace.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('#$_floor', style: meta),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              quote,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: body.copyWith(color: colors.textMeta),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.m),
            ] else if (_floor != null) ...[
              Text('第 $_floor 楼', style: meta),
              const SizedBox(height: AppSpace.s),
            ],
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else ...[
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 12,
                autofocus: _floor != null,
                cursorColor: colors.brandPrimary,
                style: body,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.surfaceElevated,
                  hintText: '写点什么，只保存在这台设备上',
                  hintStyle: body.copyWith(color: colors.textMeta),
                  contentPadding: const EdgeInsets.all(AppSpace.m),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius.field),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.l),
              Row(
                children: [
                  Text(
                    '摘录',
                    style: base
                        .merge(tokens.text.metaStrong)
                        .copyWith(color: colors.textPrimary),
                  ),
                  const Spacer(),
                  AppPressable(
                    onTap: _pasteExcerpt,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppSize.hit),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.paste,
                            size: AppSize.iconS,
                            color: colors.brandPrimary,
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Text(
                            '粘贴为摘录',
                            style: base
                                .merge(tokens.text.control)
                                .copyWith(color: colors.brandPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_excerpts.isEmpty)
                Text('在帖子里长按选中文字，点「复制」，再回到这里点「粘贴为摘录」。', style: meta),
              for (final e in _excerpts)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radius.card),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpace.m,
                        top: AppSpace.s,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(e.text, style: body),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  [
                                    if (e.postNumber != null)
                                      '#${e.postNumber}',
                                    TimeUtils.formatShortDate(e.createdAt),
                                  ].join(' · '),
                                  style: meta,
                                ),
                                const SizedBox(height: AppSpace.s),
                              ],
                            ),
                          ),
                          AppIconButton(
                            icon: AppIcons.delete,
                            semanticLabel: '删除摘录',
                            onPressed: () {
                              setState(() => _excerpts.remove(e));
                              _scheduleSave();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (others.isNotEmpty || showTopicRow) ...[
                const SizedBox(height: AppSpace.l),
                Text(
                  '其他笔记',
                  style: base
                      .merge(tokens.text.metaStrong)
                      .copyWith(color: colors.textPrimary),
                ),
                if (showTopicRow)
                  _OtherNoteRow(
                    key: const ValueKey('note-row-topic'),
                    label: '话题',
                    text: _topicText,
                    meta: meta,
                    body: body,
                    onTap: () => _retarget(null),
                  ),
                for (final f in others)
                  _OtherNoteRow(
                    key: ValueKey('note-row-$f'),
                    label: '#$f',
                    text: _floorNotes[f]!,
                    meta: meta,
                    body: body,
                    onTap: () => _retarget(f),
                    onDelete: () => _deleteFloorNote(f),
                  ),
              ],
            ],
            const SizedBox(height: AppSpace.l),
          ],
        ),
      ),
    );
  }
}

/// 「其他笔记」里的一行：点开改成编辑这一条，右侧可以删
class _OtherNoteRow extends StatelessWidget {
  const _OtherNoteRow({
    super.key,
    required this.label,
    required this.text,
    required this.meta,
    required this.body,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final String text;
  final TextStyle meta;
  final TextStyle body;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '编辑$label的笔记',
              excludeSemantics: true,
              onTap: onTap,
              child: AppPressable(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSize.hit),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$label  ', style: meta),
                          TextSpan(
                            text: text.replaceAll('\n', ' '),
                            style: body.copyWith(color: colors.textMeta),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onDelete != null)
            AppIconButton(
              icon: AppIcons.delete,
              semanticLabel: '删除$label的笔记',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
