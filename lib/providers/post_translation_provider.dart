import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/quick_translation_service.dart';
import 'ai_translation_provider.dart';

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

/// 楼层翻译。楼层滚出屏幕会被回收，点过翻译后才保活，所以滚回来译文还在；
/// 没点过的楼层不留状态。
class PostTranslationNotifier extends Notifier<PostTranslationState> {
  PostTranslationNotifier(this.postId);

  final int postId;

  QuickTranslation? _cached;
  String? _cachedCooked;
  String? _cachedTarget;
  CancelToken? _cancelToken;

  @override
  PostTranslationState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    return const PostTranslationState();
  }

  /// 没显示就翻译，已显示就收起。收起后再展开直接用缓存，不重新请求。
  Future<void> toggle(String cooked) async {
    if (state.isVisible && state.isFor(cooked)) {
      _cancelToken?.cancel();
      _cancelToken = null;
      state = const PostTranslationState();
      return;
    }
    final target = ref.read(aiTranslationTargetLanguageProvider);
    if (_cached != null && _cachedCooked == cooked && _cachedTarget == target) {
      state = PostTranslationState(
        status: PostTranslationStatus.ready,
        result: _cached,
        cooked: cooked,
        targetLanguage: target,
      );
      return;
    }
    await _fetch(cooked, target);
  }

  /// 失败后重试。
  Future<void> retry(String cooked) =>
      _fetch(cooked, ref.read(aiTranslationTargetLanguageProvider));

  Future<void> _fetch(String cooked, String target) async {
    ref.keepAlive();
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
    state = PostTranslationState(
      status: PostTranslationStatus.loading,
      cooked: cooked,
      targetLanguage: target,
    );
    try {
      final result = await ref
          .read(quickTranslationServiceProvider)
          .translatePost(
            cookedHtml: cooked,
            targetLanguage: target,
            cancelToken: token,
          );
      if (!ref.mounted || !identical(token, _cancelToken)) return;
      _cached = result;
      _cachedCooked = cooked;
      _cachedTarget = target;
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
