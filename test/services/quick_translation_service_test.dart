import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/ai_translation_service.dart';
import 'package:fluxdo/services/quick_translation_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.reply);

  final String Function(RequestOptions options) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      reply(options),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

QuickTranslationService _service(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(responseType: ResponseType.plain));
  dio.httpClientAdapter = adapter;
  return QuickTranslationService(dio: dio);
}

void main() {
  group('响应解析', () {
    test('真实响应：多段拼接，保留换行，取原文语言', () {
      // 2026-11-03 从接口抓的响应，内容是测试句
      const body =
          r'[[["你好世界。\n\n","Hello world.\n\n",null,null,10,null,null,null,[[null,true]]],'
          r'["这是第二段。","This is a second paragraph.",null,null,3,null,null,[[]],[[["6ffa","en_zh_2023q1.md"]]]]],'
          r'null,"en",null,null,null,1,[],[["en"],null,[1],["en"]]]';
      final parsed = QuickTranslationService.parseResponse(body);
      expect(parsed.text, '你好世界。\n\n这是第二段。');
      expect(parsed.source, 'en');
    });

    test('接口格式变了算失败，不能当译文显示', () {
      for (final body in ['{"error":"x"}', '[]', '[null]', '[[]]']) {
        expect(
          () => QuickTranslationService.parseResponse(body),
          throwsFormatException,
          reason: body,
        );
      }
      expect(
        () => QuickTranslationService.parseResponse('<html>blocked</html>'),
        throwsFormatException,
      );
    });
  });

  group('要翻译的文字', () {
    test('去掉代码块、链接预览和图片信息，留下正文', () {
      final text = QuickTranslationService.translatableText('''
<p>Keep this.</p>
<pre><code>rm -rf /</code></pre>
<aside class="onebox"><p>preview text</p></aside>
<div class="lightbox-wrapper"><a class="lightbox"><img alt="pic"><div class="meta">1024x768</div></a></div>
<p>And this.</p>
''');
      expect(text, contains('Keep this.'));
      expect(text, contains('And this.'));
      expect(text, isNot(contains('rm -rf')));
      expect(text, isNot(contains('preview text')));
      expect(text, isNot(contains('1024x768')));
    });
  });

  group('长文拆分', () {
    const max = QuickTranslationService.maxChunkChars;

    test('短文不拆', () {
      expect(QuickTranslationService.splitChunks('短文'), ['短文']);
    });

    test('按段落拆，拼回去和原文完全一样', () {
      final text = List.generate(40, (i) => '${'字' * 300}$i').join('\n');
      final chunks = QuickTranslationService.splitChunks(text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.length <= max + 1), isTrue);
      expect(chunks.join(), text);
    });

    test('没有换行的超长段落硬切，不会死循环', () {
      final text = '字' * (max * 2 + 5);
      final chunks = QuickTranslationService.splitChunks(text);
      expect(chunks.length, 3);
      expect(chunks.join(), text);
    });

    test('开头就是换行也能拆完', () {
      final text = '\n${'字' * (max + 10)}';
      expect(QuickTranslationService.splitChunks(text).join(), text);
    });
  });

  group('请求', () {
    String reply(String text, {String source = 'en'}) => jsonEncode([
      [
        [text, 'x'],
      ],
      null,
      source,
    ]);

    test('表单发正文，目标语言在参数里，不带论坛的 Cookie', () async {
      final adapter = _FakeAdapter((_) => reply('你好'));
      final result = await _service(adapter).translatePost(
        cookedHtml: '<p>Hello</p>',
        targetLanguage: 'zh-CN',
      );
      expect(result.text, '你好');
      expect(result.sourceLanguage, 'en');
      expect(result.truncated, isFalse);
      final request = adapter.requests.single;
      expect(request.uri.host, 'translate.googleapis.com');
      expect(request.uri.queryParameters['tl'], 'zh-CN');
      expect(request.uri.queryParameters['q'], isNull, reason: '正文不能放进 URL');
      expect(request.headers['cookie'], isNull);
    });

    test('长文分几次请求，译文按原顺序拼接', () async {
      var n = 0;
      final adapter = _FakeAdapter((_) => reply('第${++n}段'));
      final cooked = List.generate(
        30,
        (i) => '<p>${'a' * 300}</p>',
      ).join('\n');
      final result = await _service(adapter).translatePost(
        cookedHtml: cooked,
        targetLanguage: 'zh-CN',
      );
      expect(adapter.requests.length, greaterThan(1));
      expect(result.text, startsWith('第1段第2段'));
    });

    test('超长帖截断并标记', () async {
      final adapter = _FakeAdapter((_) => reply('译文'));
      final cooked =
          '<p>${'a' * (AiTranslationService.maxTranslateChars + 10)}</p>';
      final result = await _service(adapter).translatePost(
        cookedHtml: cooked,
        targetLanguage: 'zh-CN',
      );
      expect(result.truncated, isTrue);
    });

    test('全是代码的帖子不发请求', () async {
      final adapter = _FakeAdapter((_) => reply('x'));
      final result = await _service(adapter).translatePost(
        cookedHtml: '<pre><code>x = 1</code></pre>',
        targetLanguage: 'zh-CN',
      );
      expect(result.text, isEmpty);
      expect(adapter.requests, isEmpty);
    });
  });

  group('原文语言判断', () {
    QuickTranslation of(String? source) => QuickTranslation(
      text: 'x',
      sourceLanguage: source,
      truncated: false,
    );

    test('相同语言才算', () {
      expect(of('zh-CN').isSameLanguageAs('zh-CN'), isTrue);
      expect(of('zh-cn').isSameLanguageAs('zh-CN'), isTrue);
      expect(of('en').isSameLanguageAs('zh-CN'), isFalse);
      expect(of('zh-TW').isSameLanguageAs('zh-CN'), isFalse);
      expect(of(null).isSameLanguageAs('zh-CN'), isFalse);
    });
  });
}
