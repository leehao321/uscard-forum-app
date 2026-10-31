import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/ai_topic_summary_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/ai_topic_summary_service.dart';
import '../../services/toast_service.dart';

/// 模型没配好（没有服务商、没有 API Key）
class AiSummaryNotConfigured implements Exception {
  const AiSummaryNotConfigured();
}

/// 把送给模型的输入变成流式文本。返回 null = 没配模型（卡片显示「未配置」）。
///
/// 做成 provider 是为了测试时换成假数据，不去调真实接口。
typedef AiSegmentSummaryRunner = Stream<String> Function(String input);

final aiSegmentSummaryRunnerProvider = Provider<AiSegmentSummaryRunner?>((ref) {
  final selected = ref.watch(aiTopicSummaryModelProvider);
  if (selected == null) return null;
  return (input) async* {
    final apiKey = await AiProviderListNotifier.getApiKey(selected.provider.id);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AiSummaryNotConfigured();
    }
    final service = AiTopicSummaryService(
      chatService: ref.read(aiChatServiceProvider),
    );
    yield* service.summarizeStream(
      provider: selected.provider,
      model: selected.model,
      apiKey: apiKey.trim(),
      input: input,
      segment: true,
    );
  };
});

/// 用户点了「不再显示」后记在这里
const aiSegmentCardHiddenKey = 'ai_segment_card_hidden';

/// AI 局部总结卡片（0.4.0，计划 P6）。
///
/// 默认不自动请求：没配模型显示「未配置」态（可点「不再显示」）；配好后显示
/// 收起态 +「总结这一段」，点了才请求；请求中、出错、出结果各有一态。
/// 总结的是 App 已经加载出来的楼层，结果按「要点 + 楼层号」显示，楼层号可点。
class AiSegmentSummaryCard extends ConsumerStatefulWidget {
  const AiSegmentSummaryCard({
    super.key,
    required this.title,
    required this.posts,
    this.from,
    this.to,
    this.onJumpToPost,
    this.onOpenSettings,
  });

  final String title;
  final List<Post> posts;

  /// 只总结这个楼层范围（含）；空 = 全部已加载的楼层
  final int? from;
  final int? to;
  final void Function(int postNumber)? onJumpToPost;

  /// 「去设置」；空时不显示这个按钮
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<AiSegmentSummaryCard> createState() =>
      _AiSegmentSummaryCardState();
}

enum _Phase { idle, loading, done, error }

class _AiSegmentSummaryCardState extends ConsumerState<AiSegmentSummaryCard> {
  _Phase _phase = _Phase.idle;
  final StringBuffer _result = StringBuffer();
  StreamSubscription<String>? _sub;
  String? _error;
  bool _truncated = false;
  int _count = 0;
  bool _hidden = false;
  bool _needsSetup = false;

  @override
  void initState() {
    super.initState();
    try {
      _hidden =
          ref.read(sharedPreferencesProvider).getBool(aiSegmentCardHiddenKey) ??
          false;
    } catch (_) {
      // 没有注入偏好存储（例如单独预览）：当作没隐藏
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  ({String text, bool truncated, int postCount}) _input() =>
      AiTopicSummaryService.buildSegmentInput(
        title: widget.title,
        posts: widget.posts,
        from: widget.from,
        to: widget.to,
      );

  void _start() {
    final runner = ref.read(aiSegmentSummaryRunnerProvider);
    if (runner == null) return;
    final input = _input();
    if (input.postCount == 0) {
      setState(() {
        _phase = _Phase.error;
        _error = '这一段没有可总结的内容。';
      });
      return;
    }
    // 不等旧订阅取消完：重试要立刻发出去
    unawaited(_sub?.cancel());
    _sub = null;
    setState(() {
      _result.clear();
      _error = null;
      _truncated = input.truncated;
      _count = input.postCount;
      _phase = _Phase.loading;
    });
    _sub = runner(input.text).listen(
      (delta) {
        if (mounted) setState(() => _result.write(delta));
      },
      onError: (Object e) {
        if (!mounted) return;
        debugPrint('[AiSegmentSummary] 总结失败: $e');
        setState(() {
          if (e is AiSummaryNotConfigured) {
            _needsSetup = true;
            _phase = _Phase.idle;
          } else {
            _phase = _Phase.error;
            _error = '总结失败，请检查网络和 API 配置后重试。';
          }
        });
      },
      onDone: () {
        if (!mounted || _phase != _Phase.loading) return;
        setState(() {
          if (_result.toString().trim().isEmpty) {
            _phase = _Phase.error;
            _error = '模型没有返回内容，请重试。';
          } else {
            _phase = _Phase.done;
          }
        });
      },
      cancelOnError: true,
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() => _phase = _result.isEmpty ? _Phase.idle : _Phase.done);
  }

  Future<void> _hide() async {
    setState(() => _hidden = true);
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setBool(aiSegmentCardHiddenKey, true);
    } catch (_) {}
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _result.toString()));
    if (mounted) ToastService.showSuccess('已复制');
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final body = base
        .merge(tokens.text.body)
        .copyWith(color: colors.textPrimary);
    final control = base.merge(tokens.text.control);

    final runner = ref.watch(aiSegmentSummaryRunnerProvider);
    final configured = runner != null && !_needsSetup;
    final selected = ref.watch(aiTopicSummaryModelProvider);

    Widget link(String label, VoidCallback onTap, {bool brand = true}) =>
        AppPressable(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSize.hit),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: control.copyWith(
                  color: brand ? colors.brandPrimary : colors.textMeta,
                ),
              ),
            ),
          ),
        );

    Widget header(String label, {Widget? trailing}) => Row(
      children: [
        Icon(AppIcons.autoAwesome, size: 16, color: colors.brandPrimary),
        const SizedBox(width: AppSpace.s),
        Expanded(
          child: Text(
            label,
            style: base
                .merge(tokens.text.metaStrong)
                .copyWith(color: colors.textPrimary),
          ),
        ),
        ?trailing,
      ],
    );

    final Widget content;
    if (!configured) {
      content = Column(
        key: const ValueKey('ai-card-unconfigured'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('AI 总结'),
          const SizedBox(height: AppSpace.xs),
          Text(
            _needsSetup ? '所选服务商还没有配置 API Key。' : '还没有配置 AI 模型，配置后可以总结这一段讨论。',
            style: meta,
          ),
          Row(
            children: [
              if (widget.onOpenSettings != null) ...[
                link('去设置', widget.onOpenSettings!),
                const SizedBox(width: AppSpace.l),
              ],
              link('不再显示', _hide, brand: false),
            ],
          ),
        ],
      );
    } else if (_phase == _Phase.idle) {
      final n = _input().postCount;
      content = Row(
        key: const ValueKey('ai-card-idle'),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header('AI 总结'),
                const SizedBox(height: AppSpace.xs),
                Text(
                  [
                    '已加载 $n 层',
                    if (selected != null)
                      selected.model.name ?? selected.model.id,
                  ].join(' · '),
                  style: meta,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.m),
          FilledButton(
            style: AppButtonStyles.secondary(context),
            onPressed: n == 0 ? null : _start,
            child: const Text('总结这一段'),
          ),
        ],
      );
    } else if (_phase == _Phase.loading) {
      final points = AiTopicSummaryService.parseSegmentSummary(
        _result.toString(),
      );
      content = Column(
        key: const ValueKey('ai-card-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(
            '正在总结 $_count 层…',
            trailing: Semantics(
              label: '正在生成',
              child: const CupertinoActivityIndicator(radius: 8),
            ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s),
            _Points(points: points, body: body, meta: meta, onJump: null),
          ],
          link('停止', _stop, brand: false),
        ],
      );
    } else if (_phase == _Phase.error) {
      content = Column(
        key: const ValueKey('ai-card-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('AI 总结'),
          const SizedBox(height: AppSpace.xs),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, size: 16, color: colors.textDestructive),
                const SizedBox(width: AppSpace.s),
                Expanded(
                  child: Text(
                    _error ?? '总结失败。',
                    style: meta.copyWith(color: colors.textDestructive),
                  ),
                ),
              ],
            ),
          ),
          link('重试', _start),
        ],
      );
    } else {
      final points = AiTopicSummaryService.parseSegmentSummary(
        _result.toString(),
      );
      content = Column(
        key: const ValueKey('ai-card-done'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('AI 总结 · $_count 层'),
          const SizedBox(height: AppSpace.s),
          _Points(
            points: points,
            body: body,
            meta: meta,
            onJump: widget.onJumpToPost,
          ),
          if (_truncated)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text('内容较长，只总结了前面的部分楼层。', style: meta),
            ),
          Row(
            children: [
              link('重新总结', _start),
              const SizedBox(width: AppSpace.l),
              link('复制', _copy, brand: false),
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.m,
          AppSpace.m,
          AppSpace.m,
          AppSpace.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceGrouped,
          borderRadius: BorderRadius.circular(tokens.radius.card),
        ),
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: content,
        ),
      ),
    );
  }
}

class _Points extends StatelessWidget {
  const _Points({
    required this.points,
    required this.body,
    required this.meta,
    required this.onJump,
  });

  final List<SegmentPoint> points;
  final TextStyle body;
  final TextStyle meta;
  final void Function(int postNumber)? onJump;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9, right: AppSpace.s),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMeta,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.s,
                    children: [
                      Text(p.text, style: body),
                      for (final f in p.floors)
                        Semantics(
                          button: onJump != null,
                          label: '跳到第 $f 楼',
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onJump == null ? null : () => onJump!(f),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '#$f',
                                style: meta.copyWith(
                                  color: onJump == null
                                      ? colors.textMeta
                                      : colors.brandPrimary,
                                ),
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
      ],
    );
  }
}
