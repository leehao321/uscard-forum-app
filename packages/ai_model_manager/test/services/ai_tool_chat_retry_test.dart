import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/models/ai_provider.dart';
import 'package:ai_model_manager/services/ai_tool_chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 服务端临时故障（500 / 502 / 503 / 529）：还没发出任何事件时，等一小会儿重试 1 次。
// 默认等 1.5 秒；测试里把等待改短（真实时钟）。

String _sse(List<Object> events) =>
    events.map((e) => e is String ? 'data: $e\n\n' : 'data: ${jsonEncode(e)}\n\n').join();

final _ok = _sse([
  {
    'choices': [
      {
        'delta': {'content': '你好'},
        'finish_reason': 'stop',
      },
    ],
  },
  '[DONE]',
]);

AiProvider _provider(AiProviderType t) =>
    AiProvider(id: 'p', name: 'p', type: t, baseUrl: 'https://api.example.com');

/// 按顺序回放响应的假客户端；记下收到的请求数
class _Replay {
  _Replay(this.replies);

  /// (状态码, 正文, content-type)；超出的部分重复最后一个
  final List<(int, String, String)> replies;
  int sent = 0;

  http.Client get client => MockClient.streaming((req, _) async {
    final r = replies[sent < replies.length ? sent : replies.length - 1];
    sent++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.$2)),
      r.$1,
      headers: {'content-type': r.$3},
    );
  });
}

(int, String, String) _err(int status, [String msg = 'boom']) =>
    (status, jsonEncode({'error': {'message': msg}}), 'application/json');

(int, String, String) get _success => (200, _ok, 'text/event-stream');

Stream<AiToolEvent> _stream(http.Client c, {AiProviderType type = AiProviderType.openai}) =>
    AiToolChatService(bridgedClient: c).stream(
      provider: _provider(type),
      model: 'm',
      apiKey: 'k',
      turns: const [AiUserTurn('q')],
      tools: const [],
    );

/// 跑完整个流，返回 (事件, 错误)
Future<(List<AiToolEvent>, Object?)> _drain(Stream<AiToolEvent> s) async {
  final events = <AiToolEvent>[];
  Object? error;
  try {
    await for (final e in s) {
      events.add(e);
    }
  } catch (e) {
    error = e;
  }
  return (events, error);
}

void main() {
  const wait = Duration(milliseconds: 300);

  setUp(() => AiToolChatService.retryDelay = wait);
  tearDown(() => AiToolChatService.retryDelay = AiToolChatService.defaultRetryDelay);

  test('默认等待 1.5 秒；重试的状态码是 500 / 502 / 503 / 529', () {
    expect(AiToolChatService.defaultRetryDelay, const Duration(milliseconds: 1500));
    expect(AiToolChatService.retryableStatuses, {500, 502, 503, 529});
  });

  group('5xx 自动重试一次', () {
    for (final status in [500, 502, 503, 529]) {
      test('$status → 200：等待之后重试，成功，共 2 次请求', () async {
        final r = _Replay([_err(status), _success]);
        final sw = Stopwatch()..start();
        final result = _drain(_stream(r.client));
        await Future<void>.delayed(wait ~/ 3);
        expect(r.sent, 1, reason: '等待期间不重发');
        final (events, error) = await result;
        expect(sw.elapsed, greaterThanOrEqualTo(wait - const Duration(milliseconds: 30)));
        expect(error, isNull);
        expect(r.sent, 2);
        expect(events.whereType<AiToolTextDelta>().map((e) => e.text).join(), '你好');
      });
    }

    test('503 → 503：第二次还失败，按第二次的错误报，共 2 次请求', () async {
      final r = _Replay([_err(503, '第一次'), _err(503, '第二次')]);
      final (_, error) = await _drain(_stream(r.client));
      expect(r.sent, 2);
      expect(error, isA<AiToolChatHttpException>());
      expect((error! as AiToolChatHttpException).statusCode, 503);
      expect((error as AiToolChatHttpException).message, '第二次');
    });

    for (final type in [AiProviderType.openaiResponse, AiProviderType.anthropic, AiProviderType.gemini]) {
      test('${type.name}：同样重试 1 次（两次都 503 → 2 次请求后报错）', () async {
        final r = _Replay([_err(503)]);
        final (_, error) = await _drain(_stream(r.client, type: type));
        expect(r.sent, 2);
        expect(error, isA<AiToolChatHttpException>());
      });
    }

    test('「不支持工具」的 500（llama.cpp --jinja）不重试', () async {
      final r = _Replay([_err(500, 'tools param requires --jinja flag')]);
      final (_, error) = await _drain(_stream(r.client));
      expect(r.sent, 1);
      expect(error, isA<AiToolsUnsupportedException>());
    });

    for (final (status, msg) in [
      (400, 'bad request'),
      (400, 'Unsupported parameter: tool_choice'),
      (401, 'invalid key'),
      (403, 'forbidden'),
      (404, 'not found'),
      (429, 'rate limited'),
    ]) {
      test('$status（$msg）不重试，只 1 次请求', () async {
        final r = _Replay([_err(status, msg)]);
        final (_, error) = await _drain(_stream(r.client));
        expect(r.sent, 1);
        expect(error, isNotNull);
      });
    }

    test('等待期间取消订阅：立即结束，不发第二次请求', () async {
      final r = _Replay([_err(503), _success]);
      final events = <AiToolEvent>[];
      final sub = _stream(r.client).listen(events.add, onError: (Object _) {});
      await Future<void>.delayed(wait ~/ 3);
      expect(r.sent, 1);
      await sub.cancel();
      await Future<void>.delayed(wait * 2);
      expect(r.sent, 1);
      expect(events, isEmpty);
    });

    test('流已经有数据之后出错：不重试', () async {
      final partial = _sse([
        {
          'choices': [
            {
              'delta': {'content': '半句'},
            },
          ],
        },
        {
          'error': {'message': 'upstream died'},
        },
      ]);
      final r = _Replay([(200, partial, 'text/event-stream'), _success]);
      final (events, error) = await _drain(_stream(r.client));
      expect(r.sent, 1);
      expect(error, isNotNull);
      expect(events.whereType<AiToolTextDelta>().map((e) => e.text).join(), contains('半句'));
    });
  });
}
