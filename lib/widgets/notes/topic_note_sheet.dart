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

  int? get _floor => widget.postNumber;

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
              if (others.isNotEmpty) ...[
                const SizedBox(height: AppSpace.l),
                Text(
                  '其他楼层的笔记',
                  style: base
                      .merge(tokens.text.metaStrong)
                      .copyWith(color: colors.textPrimary),
                ),
                for (final f in others)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.s),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '#$f  ', style: meta),
                          TextSpan(
                            text: _floorNotes[f]!.replaceAll('\n', ' '),
                            style: body.copyWith(color: colors.textMeta),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
