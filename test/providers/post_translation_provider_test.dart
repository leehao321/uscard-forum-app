import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/ai_translation_provider.dart';
import 'package:fluxdo/providers/post_translation_provider.dart';
import 'package:fluxdo/services/quick_translation_service.dart';

class _FakeService extends QuickTranslationService {
  _FakeService() : super(dio: Dio());

  final calls = <String>[];
  final tokens = <CancelToken?>[];
  Completer<QuickTranslation>? gate;
  Object? error;

  @override
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) async {
    calls.add('$cookedHtml>$targetLanguage');
    tokens.add(cancelToken);
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return QuickTranslation(
      text: '译:$cookedHtml',
      sourceLanguage: 'en',
      truncated: false,
    );
  }
}

void main() {
  late _FakeService service;
  late ProviderContainer container;

  setUp(() {
    service = _FakeService();
    container = ProviderContainer(
      overrides: [
        translationEngineProvider.overrideWithValue(service),
        aiTranslationTargetLanguageProvider.overrideWithValue('zh-CN'),
      ],
    );
    addTearDown(container.dispose);
  });

  PostTranslationNotifier notifier() =>
      container.read(postTranslationProvider(1).notifier);
  PostTranslationState state() => container.read(postTranslationProvider(1));

  // autoDispose：没有监听者时状态会被回收，和楼层在屏幕上时一样挂着
  void keepWatching() {
    final sub = container.listen(postTranslationProvider(1), (_, _) {});
    addTearDown(sub.close);
  }

  test('第一次点：翻译并显示', () async {
    keepWatching();
    expect(state().isVisible, isFalse);
    await notifier().toggle('a');
    expect(state().status, PostTranslationStatus.ready);
    expect(state().result!.text, '译:a');
    expect(state().isFor('a'), isTrue);
  });

  test('再点一次收起，第三次展开不重新请求', () async {
    keepWatching();
    await notifier().toggle('a');
    await notifier().toggle('a');
    expect(state().isVisible, isFalse);
    await notifier().toggle('a');
    expect(state().status, PostTranslationStatus.ready);
    expect(service.calls, ['a>zh-CN']);
  });

  test('帖子被编辑后旧译文失效，重新翻译', () async {
    keepWatching();
    await notifier().toggle('a');
    expect(state().isFor('b'), isFalse);
    await notifier().toggle('b');
    expect(state().result!.text, '译:b');
    expect(service.calls, ['a>zh-CN', 'b>zh-CN']);
  });

  test('失败显示失败态，重试成功', () async {
    keepWatching();
    service.error = DioException(requestOptions: RequestOptions());
    await notifier().toggle('a');
    expect(state().status, PostTranslationStatus.failed);
    service.error = null;
    await notifier().retry('a');
    expect(state().status, PostTranslationStatus.ready);
  });

  test('失败态再点是收起，不是死循环重试', () async {
    keepWatching();
    service.error = DioException(requestOptions: RequestOptions());
    await notifier().toggle('a');
    await notifier().toggle('a');
    expect(state().isVisible, isFalse);
    expect(service.calls.length, 1);
  });

  test('翻译中点收起：取消请求，迟到的结果不会再弹出来', () async {
    keepWatching();
    final gate = service.gate = Completer<QuickTranslation>();
    final pending = notifier().toggle('a');
    expect(state().status, PostTranslationStatus.loading);
    await notifier().toggle('a');
    expect(state().isVisible, isFalse);
    expect(service.tokens.single!.isCancelled, isTrue);
    gate.complete(
      const QuickTranslation(text: '迟到', sourceLanguage: 'en', truncated: false),
    );
    await pending;
    expect(state().isVisible, isFalse);
  });

  test('滚出屏幕（没人监听）再滚回来，译文还在', () async {
    final sub = container.listen(postTranslationProvider(1), (_, _) {});
    await notifier().toggle('a');
    sub.close();
    await container.pump();
    final again = container.listen(postTranslationProvider(1), (_, _) {});
    addTearDown(again.close);
    expect(state().status, PostTranslationStatus.ready);
    expect(state().result!.text, '译:a');
  });

  test('没点过翻译的楼层滚出屏幕后状态被回收', () async {
    final sub = container.listen(postTranslationProvider(1), (_, _) {});
    final before = container.read(postTranslationProvider(1).notifier);
    sub.close();
    await container.pump();
    final after = container.read(postTranslationProvider(1).notifier);
    expect(identical(before, after), isFalse);
  });
}
