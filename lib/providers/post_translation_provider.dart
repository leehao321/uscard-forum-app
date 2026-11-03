import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/quick_translation_service.dart';
import '../services/translation_engine.dart';
import 'ai_translation_provider.dart';
import 'theme_provider.dart';

enum PostTranslationStatus { hidden, loading, ready, failed }

/// 一个楼层的翻译状态。
@immutable
class PostTranslationState {
  const PostTranslationState({
    this.status = PostTranslationStatus.hidden,
    this.result,
    this.cooked,
    this.targetLanguage,
  });

  final PostTranslationStatus status;
  final QuickTranslation? result;

  /// 翻译的是哪个版本的正文；帖子被编辑后旧译文不能再显示。
  final String? cooked;
  final String? targetLanguage;

  bool get isVisible => status != PostTranslationStatus.hidden;

  bool isFor(String cooked) => this.cooked == cooked;
}

final quickTranslationServiceProvider = Provider<QuickTranslationService>(
  (ref) => QuickTranslationService(),
);

const _translationSourceKey = 'pref_translation_source';

class TranslationSourceNotifier extends Notifier<TranslationSource> {
  @override
  TranslationSource build() {
    final saved = ref
        .watch(sharedPreferencesProvider)
        .getString(_translationSourceKey);
    return TranslationSource.values.firstWhere(
      (s) => s.name == saved && s.available,
      orElse: () => TranslationSource.google,
    );
  }

  Future<void> select(TranslationSource source) async {
    if (!source.available) return;
    state = source;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_translationSourceKey, source.name);
  }
}

final translationSourceProvider =
    NotifierProvider<TranslationSourceNotifier, TranslationSource>(
      TranslationSourceNotifier.new,
    );

/// 当前用的翻译通道。
final translationEngineProvider = Provider<TranslationEngine>((ref) {
  switch (ref.watch(translationSourceProvider)) {
    case TranslationSource.ai:
      final selected = ref.watch(aiTranslationSelectedModelProvider);
      if (selected == null) return const UnavailableTranslationEngine();
      return AiTranslationEngine(
        service: ref.watch(aiTranslationServiceProvider),
        provider: selected.provider,
        model: selected.model,
      );
    case TranslationSource.google:
    case TranslationSource.bilibiliIndex:
      return ref.watch(quickTranslationServiceProvider);
  }
});

/// 楼层翻译。楼层滚出屏幕会被回收，点过翻译后才保活，所以滚回来译文还在；
/// 没点过的楼层不留状态。
class PostTranslationNotifier extends Notifier<PostTranslationState> {
  PostTranslationNotifier(this.postId);

  final int postId;

  QuickTranslation? _cached;
  String? _cachedCooked;
  String? _cachedTarget;
  TranslationEngine? _cachedEngine;
  CancelToken? _cancelToken;

  /// 用户亲手收起过：全帖翻译不要再把它翻出来。
  bool dismissedByUser = false;

  @override
  PostTranslationState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    return const PostTranslationState();
  }

  /// 没显示就翻译，已显示就收起。收起后再展开直接用缓存，不重新请求。
  Future<void> toggle(String cooked) async {
    if (state.isVisible && state.isFor(cooked)) {
      hide();
      dismissedByUser = true;
      return;
    }
    dismissedByUser = false;
    if (_showCached(cooked)) return;
    await _fetch(cooked);
  }

  /// 失败后重试。
  Future<void> retry(String cooked) => _fetch(cooked);

  /// 全帖翻译的队列调用。返回是否成功，队列靠它决定要不要退避。
  Future<bool> translateQueued(String cooked) async {
    if (state.status == PostTranslationStatus.ready && state.isFor(cooked)) {
      return true;
    }
    if (_showCached(cooked)) return true;
    await _fetch(cooked);
    return state.status == PostTranslationStatus.ready;
  }

  /// 收起，缓存留着。
  void hide() {
    _cancelToken?.cancel();
    _cancelToken = null;
    state = const PostTranslationState();
  }

  bool _showCached(String cooked) {
    final target = ref.read(aiTranslationTargetLanguageProvider);
    final engine = ref.read(translationEngineProvider);
    if (_cached == null ||
        _cachedCooked != cooked ||
        _cachedTarget != target ||
        !identical(_cachedEngine, engine)) {
      return false;
    }
    state = PostTranslationState(
      status: PostTranslationStatus.ready,
      result: _cached,
      cooked: cooked,
      targetLanguage: target,
    );
    return true;
  }

  Future<void> _fetch(String cooked) async {
    ref.keepAlive();
    final target = ref.read(aiTranslationTargetLanguageProvider);
    final engine = ref.read(translationEngineProvider);
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
    state = PostTranslationState(
      status: PostTranslationStatus.loading,
      cooked: cooked,
      targetLanguage: target,
    );
    try {
      final result = await engine.translatePost(
        cookedHtml: cooked,
        targetLanguage: target,
        cancelToken: token,
      );
      if (!ref.mounted || !identical(token, _cancelToken)) return;
      _cached = result;
      _cachedCooked = cooked;
      _cachedTarget = target;
      _cachedEngine = engine;
      state = PostTranslationState(
        status: PostTranslationStatus.ready,
        result: result,
        cooked: cooked,
        targetLanguage: target,
      );
    } catch (e) {
      if (!ref.mounted || !identical(token, _cancelToken)) return;
      debugPrint('[PostTranslation] #$postId 翻译失败: ${e.runtimeType}');
      state = PostTranslationState(
        status: PostTranslationStatus.failed,
        cooked: cooked,
        targetLanguage: target,
      );
    }
  }
}

final postTranslationProvider =
    NotifierProvider.autoDispose
        .family<PostTranslationNotifier, PostTranslationState, int>(
          PostTranslationNotifier.new,
        );

/// 全帖翻译：开着时，楼层一出现就排队翻译。值是开关，参数是话题 id。
///
/// 楼层列表是懒加载的，楼层真正建出来才会进队列，所以只翻屏幕上和快要滚到的楼层，
/// 往下滚时自动跟进。队列后进先出：快速滚动时，优先翻用户正在看的。
class ImmersiveTranslationNotifier extends Notifier<bool> {
  ImmersiveTranslationNotifier(this.topicId);

  final int topicId;

  /// 连续失败后等多久再试（乘以连续失败次数），避免限流时越打越糟。
  @visibleForTesting
  static Duration backoffUnit = const Duration(seconds: 2);
  static const _maxBackoffSteps = 15;

  // 网页接口不限 Key，但一次打太多会被限流；AI 按量计费，更保守
  static const _webConcurrency = 3;
  static const _aiConcurrency = 2;

  final _pending = LinkedHashMap<int, String>();
  final _touched = <int>{};
  int _running = 0;
  int _failureStreak = 0;
  Timer? _backoff;
  int _session = 0;

  @override
  bool build() {
    ref.onDispose(() {
      _backoff?.cancel();
      _pending.clear();
    });
    return false;
  }

  void toggle() {
    _session++;
    _backoff?.cancel();
    _backoff = null;
    _failureStreak = 0;
    _pending.clear();
    if (state) {
      for (final id in _touched) {
        ref.read(postTranslationProvider(id).notifier).hide();
      }
      _touched.clear();
    }
    state = !state;
  }

  /// 楼层出现时调用。已经翻过、用户收起过、原文就是目标语言的都不进队列。
  void request(int postId, String cooked) {
    if (!state) return;
    final post = ref.read(postTranslationProvider(postId).notifier);
    if (post.dismissedByUser) return;
    final current = ref.read(postTranslationProvider(postId));
    if (current.isVisible && current.isFor(cooked)) return;
    final target = ref.read(aiTranslationTargetLanguageProvider);
    if (likelyAlreadyInTarget(
      QuickTranslationService.translatableText(cooked),
      target,
    )) {
      return;
    }
    // 重新插入，排到最新
    _pending.remove(postId);
    _pending[postId] = cooked;
    _pump();
  }

  void _pump() {
    if (_backoff != null) return;
    final limit = ref.read(translationSourceProvider) == TranslationSource.ai
        ? _aiConcurrency
        : _webConcurrency;
    while (_running < limit && _pending.isNotEmpty) {
      final postId = _pending.keys.last;
      final cooked = _pending.remove(postId)!;
      _run(postId, cooked);
    }
  }

  Future<void> _run(int postId, String cooked) async {
    final session = _session;
    _running++;
    _touched.add(postId);
    var ok = false;
    try {
      ok = await ref
          .read(postTranslationProvider(postId).notifier)
          .translateQueued(cooked);
    } catch (e) {
      debugPrint('[ImmersiveTranslation] #$postId 失败: ${e.runtimeType}');
    }
    _running--;
    if (!ref.mounted || session != _session) return;
    if (ok) {
      _failureStreak = 0;
    } else {
      _failureStreak++;
      final steps = _failureStreak.clamp(1, _maxBackoffSteps);
      _backoff?.cancel();
      _backoff = Timer(backoffUnit * steps, () {
        _backoff = null;
        if (ref.mounted) _pump();
      });
    }
    _pump();
  }
}

final immersiveTranslationProvider =
    NotifierProvider.autoDispose.family<ImmersiveTranslationNotifier, bool, int>(
      ImmersiveTranslationNotifier.new,
    );
