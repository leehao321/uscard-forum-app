import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/ai_topic_summary_provider.dart';
import '../../services/ai_topic_summary_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../common/app_bottom_sheet.dart';

/// 打开话题 AI 总结弹层。只总结已加载的楼层，点开才会调用用户自己的 AI 接口。
void showAiTopicSummarySheet(
  BuildContext context, {
  required String title,
  required List<Post> posts,
}) {
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AppSheetScaffold(
      maxHeightFactor: 0.85,
      child: _AiTopicSummaryBody(title: title, posts: posts),
    ),
  );
}

class _AiTopicSummaryBody extends ConsumerStatefulWidget {
  const _AiTopicSummaryBody({required this.title, required this.posts});

  final String title;
  final List<Post> posts;

  @override
  ConsumerState<_AiTopicSummaryBody> createState() =>
      _AiTopicSummaryBodyState();
}

class _AiTopicSummaryBodyState extends ConsumerState<_AiTopicSummaryBody> {
  final StringBuffer _result = StringBuffer();
  StreamSubscription<String>? _subscription;
  bool _streaming = false;
  bool _truncated = false;
  int _postCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 当前选中的文本模型；没有任何可用模型时返回 null。
  ({AiProvider provider, AiModel model})? _resolveModel() {
    return ref.read(aiTopicSummaryModelProvider);
  }

  Future<void> _start() async {
    if (!mounted) return;
    await _subscription?.cancel();
    setState(() {
      _result.clear();
      _error = null;
      _truncated = false;
      _streaming = true;
    });

    final selected = _resolveModel();
    if (selected == null) {
      setState(() {
        _streaming = false;
        _error = '还没有可用的 AI 模型，请先在「设置 → AI」里添加服务商和 API Key。';
      });
      return;
    }
    final apiKey = await AiProviderListNotifier.getApiKey(selected.provider.id);
    if (!mounted) return;
    if (apiKey == null || apiKey.trim().isEmpty) {
      setState(() {
        _streaming = false;
        _error = '所选服务商没有配置 API Key。';
      });
      return;
    }

    final input = AiTopicSummaryService.buildInput(
      title: widget.title,
      posts: widget.posts,
    );
    if (input.postCount == 0) {
      setState(() {
        _streaming = false;
        _error = '当前没有可总结的楼层内容。';
      });
      return;
    }
    setState(() {
      _truncated = input.truncated;
      _postCount = input.postCount;
    });

    final service = AiTopicSummaryService(
      chatService: ref.read(aiChatServiceProvider),
    );
    _subscription = service
        .summarizeStream(
          provider: selected.provider,
          model: selected.model,
          apiKey: apiKey.trim(),
          input: input.text,
        )
        .listen(
          (delta) {
            if (!mounted) return;
            setState(() => _result.write(delta));
          },
          onError: (Object error) {
            if (!mounted) return;
            debugPrint('[AiTopicSummary] 总结失败: $error');
            setState(() {
              _streaming = false;
              _error = '总结失败，请检查网络和 API 配置后重试。';
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _streaming = false;
              // 出错时流也会走到这里，不要用「没有返回内容」盖掉真正的失败原因
              if (_result.isEmpty && _error == null) {
                _error = '模型没有返回内容，请重试。';
              }
            });
          },
        );
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _streaming = false;
      if (_result.isEmpty) _error = '已停止。';
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _result.toString()));
    if (mounted) ToastService.showSuccess('已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = ref.watch(aiTopicSummaryModelProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Symbols.auto_awesome_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'AI 总结',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${selected.provider.name} / ${selected.model.name ?? selected.model.id}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_postCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _truncated
                  ? '仅总结已加载楼层的前 $_postCount 层（内容过长已截断）'
                  : '基于已加载的 $_postCount 个楼层',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _truncated
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _start,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : _result.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                : SelectableText(
                    _result.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_streaming)
              TextButton.icon(
                onPressed: _stop,
                icon: const Icon(Symbols.stop_rounded, size: 18),
                label: const Text('停止'),
              ),
            TextButton.icon(
              onPressed: _result.isEmpty ? null : _copy,
              icon: const Icon(Symbols.content_copy_rounded, size: 18),
              label: const Text('复制'),
            ),
          ],
        ),
      ],
    );
  }
}
