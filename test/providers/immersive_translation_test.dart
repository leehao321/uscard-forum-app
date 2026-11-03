import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/ai_translation_provider.dart';
import 'package:fluxdo/providers/post_translation_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/ai_translation_service.dart';
import 'package:fluxdo/services/quick_translation_service.dart';
import 'package:fluxdo/services/translation_engine.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_translation_block.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';

/// 手动放行的引擎：记下并发数和请求顺序。
class _Engine implements TranslationEngine {
  final started = <String>[];
  final gates = <String, Completer<QuickTranslation>>{};
  int running = 0;
  int peak = 0;
  bool autoComplete = false;
  Object? error;

  @override
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) async {
    started.add(cookedHtml);
    running++;
    if (running > peak) peak = running;
    try {
      if (error != null) throw error!;
      if (autoComplete) return _ok(cookedHtml);
      final gate = gates[cookedHtml] = Completer();
      return await gate.future;
    } finally {
      running--;
    }
  }

  static QuickTranslation _ok(String cooked) =>
      QuickTranslation(text: '译:$cooked', sourceLanguage: 'en', truncated: false);

  void finish(String cooked) => gates[cooked]!.complete(_ok(cooked));
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _en(int id) => '<p>English post number $id</p>';

void main() {
  const topic = 7;
  late _Engine engine;
  late ProviderContainer container;

  setUp(() {
    engine = _Engine();
    container = ProviderContainer(
      overrides: [
        translationEngineProvider.overrideWithValue(engine),
        aiTranslationTargetLanguageProvider.overrideWithValue('zh-CN'),
        translationSourceProvider.overrideWithBuild((_, _) => TranslationSource.google),
      ],
    );
    addTearDown(container.dispose);
    container.listen(immersiveTranslationProvider(topic), (_, _) {});
  });

  ImmersiveTranslationNotifier immersive() =>
      container.read(immersiveTranslationProvider(topic).notifier);
  PostTranslationState post(int id) => container.read(postTranslationProvider(id));

  void watchPost(int id) {
    final sub = container.listen(postTranslationProvider(id), (_, _) {});
    addTearDown(sub.close);
  }

  group('队列', () {
    test('关着时不翻译', () async {
      immersive().request(1, _en(1));
      await _flush();
      expect(engine.started, isEmpty);
    });

    test('开着时：最多 3 个并发，防限流', () async {
      immersive().toggle();
      for (var id = 1; id <= 8; id++) {
        watchPost(id);
        immersive().request(id, _en(id));
      }
      await _flush();
      expect(engine.running, 3);

      engine.finish(engine.started.first);
      await _flush();
      expect(engine.running, 3, reason: '完成一个，补上一个');
      expect(engine.peak, 3);
      expect(engine.started.length, 4);
      for (final g in engine.gates.values) {
        if (!g.isCompleted) g.complete(_Engine._ok('x'));
      }
    });

    test('后进先出：快速滚动时优先翻正在看的楼层', () async {
      immersive().toggle();
      for (var id = 1; id <= 5; id++) {
        watchPost(id);
        immersive().request(id, _en(id));
      }
      await _flush();
      // 前 3 个立刻开始，4、5 在排队
      engine.finish(_en(1));
      await _flush();
      expect(engine.started.last, _en(5), reason: '后来的 5 先于 4');
      for (final g in engine.gates.values) {
        if (!g.isCompleted) g.complete(_Engine._ok('x'));
      }
    });

    test('已经翻过的楼层不重复翻译', () async {
      engine.autoComplete = true;
      watchPost(1);
      immersive().toggle();
      immersive().request(1, _en(1));
      await _flush();
      immersive().request(1, _en(1));
      await _flush();
      expect(engine.started.length, 1);
      expect(post(1).status, PostTranslationStatus.ready);
    });

    test('用户亲手收起的楼层不再翻出来', () async {
      engine.autoComplete = true;
      watchPost(1);
      immersive().toggle();
      immersive().request(1, _en(1));
      await _flush();
      await container.read(postTranslationProvider(1).notifier).toggle(_en(1));
      expect(post(1).isVisible, isFalse);

      immersive().request(1, _en(1));
      await _flush();
      expect(post(1).isVisible, isFalse);
      expect(engine.started.length, 1);
    });

    test('中文帖不发出去', () async {
      immersive().toggle();
      immersive().request(1, '<p>这是一篇中文帖子，内容都是中文，提到了 CSR 这张卡。</p>');
      await _flush();
      expect(engine.started, isEmpty);
    });
  });

  group('关闭', () {
    test('排队的取消，译文收起；再开时直接用缓存', () async {
      engine.autoComplete = true;
      watchPost(1);
      immersive().toggle();
      immersive().request(1, _en(1));
      await _flush();
      expect(post(1).status, PostTranslationStatus.ready);

      immersive().toggle();
      expect(post(1).isVisible, isFalse);

      immersive().toggle();
      immersive().request(1, _en(1));
      await _flush();
      expect(post(1).status, PostTranslationStatus.ready);
      expect(engine.started.length, 1, reason: '没有重新请求');
    });

    test('关闭后迟到的结果不会弹出来', () async {
      watchPost(1);
      immersive().toggle();
      immersive().request(1, _en(1));
      await _flush();
      immersive().toggle();
      engine.finish(_en(1));
      await _flush();
      expect(post(1).isVisible, isFalse);
    });
  });

  group('退避', () {
    test('失败后暂停一下，不会继续打；时间到再试', () async {
      ImmersiveTranslationNotifier.backoffUnit = const Duration(milliseconds: 60);
      addTearDown(() => ImmersiveTranslationNotifier.backoffUnit = const Duration(seconds: 2));
      engine.error = DioException(requestOptions: RequestOptions());
      immersive().toggle();
      watchPost(1);
      immersive().request(1, _en(1));
      await _flush();
      expect(post(1).status, PostTranslationStatus.failed);

      engine.error = null;
      engine.autoComplete = true;
      watchPost(2);
      immersive().request(2, _en(2));
      await _flush();
      expect(engine.started.length, 1, reason: '退避中，新楼层先排队');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _flush();
      expect(post(2).status, PostTranslationStatus.ready);
    });
  });

  group('是否已是目标语言', () {
    test('简体中文目标：中文帖跳过，夹几个英文词也算', () {
      expect(likelyAlreadyInTarget('今天申请了这张卡，感觉还不错', 'zh-CN'), isTrue);
      expect(likelyAlreadyInTarget('CSR 的开卡奖励是 60k，我觉得值得申请', 'zh-CN'), isTrue);
    });

    test('英文帖、日文、韩文要翻', () {
      expect(likelyAlreadyInTarget('Just got approved for this card today', 'zh-CN'), isFalse);
      expect(likelyAlreadyInTarget('今日は天気がいいですね', 'zh-CN'), isFalse);
      expect(likelyAlreadyInTarget('오늘 날씨가 좋아요', 'zh-CN'), isFalse);
    });

    test('其他目标语言判断不了，照常翻', () {
      expect(likelyAlreadyInTarget('今天天气不错', 'en'), isFalse);
      expect(likelyAlreadyInTarget('今天天气不错', 'zh-TW'), isFalse);
    });

    test('没有文字（全是图）：不发', () {
      expect(likelyAlreadyInTarget('', 'zh-CN'), isTrue);
      expect(likelyAlreadyInTarget('123 !!!', 'zh-CN'), isTrue);
    });
  });

  group('翻译来源', () {
    late SharedPreferences prefs;

    ProviderContainer real() {
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('默认 Google', () {
      expect(real().read(translationSourceProvider), TranslationSource.google);
    });

    test('选 AI 能保存，重开还是 AI', () async {
      final c = real();
      await c.read(translationSourceProvider.notifier).select(TranslationSource.ai);
      expect(real().read(translationSourceProvider), TranslationSource.ai);
    });

    test('预留的 B 站通道选不了，存了也回到 Google', () async {
      final c = real();
      await c.read(translationSourceProvider.notifier).select(TranslationSource.bilibiliIndex);
      expect(c.read(translationSourceProvider), TranslationSource.google);
      await prefs.setString('pref_translation_source', 'bilibiliIndex');
      expect(real().read(translationSourceProvider), TranslationSource.google);
    });

    test('选了 AI 但没有模型：翻译失败，不会偷偷走 Google', () async {
      expect(
        const UnavailableTranslationEngine().translatePost(
          cookedHtml: '<p>x</p>',
          targetLanguage: 'zh-CN',
        ),
        throwsA(isA<TranslationUnavailableException>()),
      );
    });
  });

  group('AI 通道', () {
    const provider = AiProvider(
      id: 'p',
      name: 'P',
      type: AiProviderType.openai,
      baseUrl: 'https://x',
    );
    const model = AiModel(id: 'm');

    test('没有 API Key：不发请求，报不可用', () async {
      final engine = AiTranslationEngine(
        service: _NeverAi(),
        provider: provider,
        model: model,
        readApiKey: (_) async => null,
      );
      await expectLater(
        engine.translatePost(cookedHtml: '<p>hello</p>', targetLanguage: 'zh-CN'),
        throwsA(isA<TranslationUnavailableException>()),
      );
    });
  });

  group('界面', () {
    Post makePost(String cooked) => Post.fromJson({
      'id': 1,
      'name': 'a',
      'username': 'a',
      'avatar_template': '/a.png',
      'cooked': cooked,
      'post_number': 1,
      'post_type': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'reply_count': 0,
      'like_count': 0,
    });

    List<dynamic> overridesFor(_Engine e, SharedPreferences prefs) => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      translationEngineProvider.overrideWithValue(e),
      aiTranslationTargetLanguageProvider.overrideWithValue('zh-CN'),
    ];

    testWidgets('开全帖开关后，楼层自动出译文，左边有细竖线', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final e = _Engine()..autoComplete = true;
      final post = makePost(_en(1));

      await pumpApp(
        tester,
        Scaffold(
          appBar: AppBar(actions: const [ImmersiveTranslateButton(topicId: topic)]),
          body: PostTranslationBlock(post: post, topicId: topic),
        ),
        overrides: overridesFor(e, prefs),
      );
      expect(find.byKey(const ValueKey('post-translation')), findsNothing);
      expect(e.started, isEmpty, reason: '没开开关不发请求');

      await tester.tap(find.byKey(const ValueKey('immersive-translate')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('译:${_en(1)}'), findsOneWidget);
      final box = tester.widget<Container>(find.byKey(const ValueKey('post-translation')));
      final border = (box.decoration! as BoxDecoration).border! as Border;
      expect(border.left.width, 1.5);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('再点开关：译文收起', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final e = _Engine()..autoComplete = true;
      await pumpApp(
        tester,
        Scaffold(
          appBar: AppBar(actions: const [ImmersiveTranslateButton(topicId: topic)]),
          body: PostTranslationBlock(post: makePost(_en(1)), topicId: topic),
        ),
        overrides: overridesFor(e, prefs),
      );
      await tester.tap(find.byKey(const ValueKey('immersive-translate')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('immersive-translate')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('post-translation')), findsNothing);
    });
  });
}

class _NeverAi implements AiTranslationService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不该发请求：${invocation.memberName}');
}
