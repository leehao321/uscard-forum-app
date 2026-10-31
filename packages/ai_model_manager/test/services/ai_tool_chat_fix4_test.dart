import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/models/ai_provider.dart';
import 'package:ai_model_manager/services/ai_tool_chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 上线前审查第 4 / 5 批：工具调用协议与降级。每条都要在旧代码上失败。

String sse(List<Object> events) =>
    events.map((e) => e is String ? 'data: $e\n\n' : 'data: ${jsonEncode(e)}\n\n').join();

AiProvider provider(AiProviderType t, [String base = 'https://api.example.com']) =>
    AiProvider(id: 'p', name: 'p', type: t, baseUrl: base);

const search = AiToolSpec(
  name: 'search_docs',
  description: '搜索',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
    },
  },
);

class Sent {
  final requests = <http.Request>[];
  Map<String, dynamic> get body => jsonDecode(requests.last.body) as Map<String, dynamic>;
}

http.Client replay(String body, Sent sent, {int status = 200, String type = 'text/event-stream'}) =>
    MockClient.streaming((req, _) async {
      sent.requests.add(req as http.Request);
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        headers: {'content-type': type},
      );
    });

Future<List<AiToolEvent>> run(
  http.Client client,
  AiProviderType type, {
  List<AiToolTurn> turns = const [AiUserTurn('q')],
  List<AiToolSpec> tools = const [search],
  AiToolChoice choice = AiToolChoice.auto,
  String base = 'https://api.example.com',
}) =>
    AiToolChatService(bridgedClient: client)
        .stream(
          provider: provider(type, base),
          model: 'gpt-4o',
          apiKey: 'k',
          turns: turns,
          tools: tools,
          toolChoice: choice,
        )
        .toList();

void main() {
  group('3 「不支持工具」只认明确的说法', () {
    test('误判的报错都按普通错误处理', () {
      const cases = <(int, String)>[
        // OpenAI 上下文超长，信息里有 "functions"
        (400, '{"error":{"message":"This model\'s maximum context length is 8192 tokens. However, your messages resulted in 9000 tokens (including functions)."}}'),
        // 文档链接里的 #tool-calls
        (400, '{"error":{"message":"Invalid request. See https://docs.example.com/api#tool-calls for details."}}'),
        // FastAPI 422，loc 里有 tool_call_id
        (422, '{"detail":[{"loc":["body","messages",3,"tool_call_id"],"msg":"field required","type":"value_error.missing"}]}'),
        // 参数写错
        (400, '{"error":{"message":"Invalid schema for function \'search_docs\': \'x\' is not valid"}}'),
      ];
      for (final (status, body) in cases) {
        expect(
          AiToolChatService.classifyHttpError(status, body),
          isA<AiToolChatHttpException>(),
          reason: body,
        );
      }
    });

    test('明确的「不支持」说法都认得，包括 llama.cpp 的 500', () {
      const cases = <(int, String)>[
        (400, '{"error":{"message":"registry.ollama.ai/library/gemma:2b does not support tools"}}'),
        (400, '{"error":{"message":"tools are not supported for this model"}}'),
        (400, '{"error":{"message":"Tool use is not supported with this model"}}'),
        (400, '{"error":{"message":"Function calling is not supported by this model"}}'),
        (400, '{"error":{"message":"Unrecognized request argument supplied: tools"}}'),
        (404, '{"error":{"message":"No endpoints found that support tool use."}}'),
        (500, '{"error":{"message":"tools param requires --jinja flag"}}'),
      ];
      for (final (status, body) in cases) {
        expect(
          AiToolChatService.classifyHttpError(status, body),
          isA<AiToolsUnsupportedException>(),
          reason: body,
        );
      }
    });

    test('Gemini 的 API_KEY_INVALID（400）按鉴权失败处理', () {
      final e = AiToolChatService.classifyHttpError(
        400,
        '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}',
      );
      expect(e, isA<AiToolChatHttpException>());
      expect((e as AiToolChatHttpException).statusCode, 401);
    });
  });

  group('2 最后一轮：tool_choice 为 none 要真正发出去（带着 tools）', () {
    final turns = <AiToolTurn>[
      const AiUserTurn('q'),
      const AiAssistantTurn(toolCalls: [AiToolCall(id: 'a', name: 'search_docs', argumentsJson: '{"query":"x"}')]),
      const AiToolResultTurn(callId: 'a', name: 'search_docs', content: '{"ok":true}'),
    ];

    test('OpenAI / Responses / Anthropic / Gemini 各自的写法', () async {
      final s1 = Sent();
      await run(replay(sse(['[DONE]']), s1), AiProviderType.openai, turns: turns, choice: AiToolChoice.none);
      expect(s1.body['tool_choice'], 'none');
      expect(s1.body['tools'], isNotEmpty);

      final s2 = Sent();
      await run(
        replay(sse([{'type': 'response.completed', 'response': {}}]), s2),
        AiProviderType.openaiResponse,
        turns: turns,
        choice: AiToolChoice.none,
      );
      expect(s2.body['tool_choice'], 'none');
      expect(s2.body['tools'], isNotEmpty);

      final s3 = Sent();
      await run(replay(sse([{'type': 'message_stop'}]), s3), AiProviderType.anthropic, turns: turns, choice: AiToolChoice.none);
      expect(s3.body['tool_choice'], {'type': 'none'});
      expect(s3.body['tools'], isNotEmpty);

      final s4 = Sent();
      await run(
        replay(sse([{'candidates': [{'finishReason': 'STOP'}]}]), s4),
        AiProviderType.gemini,
        turns: turns,
        choice: AiToolChoice.none,
      );
      expect((s4.body['toolConfig'] as Map)['functionCallingConfig'], {'mode': 'NONE'});
      expect(s4.body['tools'], isNotEmpty);
    });
  });

  group('4 收到任何数据都发一个进度事件', () {
    test('OpenAI reasoning_content、工具参数分片', () async {
      final s = Sent();
      final events = await run(
        replay(
          sse([
            {'choices': [{'delta': {'reasoning_content': '想'}}]},
            {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'a', 'function': {'name': 'search_docs', 'arguments': '{"q'}}]}}]},
            {'choices': [{'delta': {}, 'finish_reason': 'tool_calls'}]},
            '[DONE]',
          ]),
          s,
        ),
        AiProviderType.openai,
      );
      // 没有正文增量，但每个分片都有一个进度事件
      expect(events.whereType<AiToolTextDelta>(), isEmpty);
      expect(events.whereType<AiToolActivity>().length, greaterThanOrEqualTo(3));
    });

    test('Anthropic 的 thinking_delta / input_json_delta，Gemini 的 thought', () async {
      final a = await run(
        replay(
          sse([
            {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'thinking'}},
            {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': '想'}},
            {'type': 'message_stop'},
          ]),
          Sent(),
        ),
        AiProviderType.anthropic,
      );
      expect(a.whereType<AiToolActivity>().length, 3);
      final g = await run(
        replay(
          sse([
            {'candidates': [{'content': {'parts': [{'text': '想', 'thought': true}]}}]},
            {'candidates': [{'finishReason': 'STOP'}]},
          ]),
          Sent(),
        ),
        AiProviderType.gemini,
      );
      expect(g.whereType<AiToolActivity>().length, 2);
    });

    test('每 10 秒只来一条只有 reasoning 的分片，共 8 条：上层能看到 8 次进度', () async {
      // 用真实的流（带延时）确认进度事件是边收边发的，不是最后一起发
      final controller = StreamController<List<int>>();
      final client = MockClient.streaming((req, _) async => http.StreamedResponse(
            controller.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          ));
      final seen = <AiToolEvent>[];
      final sub = AiToolChatService(bridgedClient: client)
          .stream(
            provider: provider(AiProviderType.openai),
            model: 'm',
            apiKey: 'k',
            turns: const [AiUserTurn('q')],
            tools: const [],
          )
          .listen(seen.add);
      for (var i = 0; i < 8; i++) {
        controller.add(utf8.encode(
          sse([{'choices': [{'delta': {'reasoning_content': '想$i'}}]}]),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(seen.whereType<AiToolActivity>().length, i + 1);
      }
      await sub.cancel();
    });
  });

  group('5 流中途报错、没有结束标记就断开：已中断，保留已有的部分', () {
    test('OpenRouter 的 error 分片 + finish_reason:error', () async {
      final f = run(
        replay(
          sse([
            {'choices': [{'delta': {'content': '半截'}}]},
            {'error': {'message': 'Provider returned error', 'code': 502}, 'choices': [{'finish_reason': 'error', 'delta': {'content': ''}}]},
          ]),
          Sent(),
        ),
        AiProviderType.openai,
      );
      await expectLater(
        f,
        throwsA(isA<AiToolInterruptedException>().having((e) => e.partialText, 'partial', '半截')),
      );
    });

    test('Gemini 流里的 {"error":…}', () async {
      final f = run(
        replay(
          sse([
            {'candidates': [{'content': {'parts': [{'text': '半截'}]}}]},
            {'error': {'code': 503, 'message': 'The model is overloaded'}},
          ]),
          Sent(),
        ),
        AiProviderType.gemini,
      );
      await expectLater(f, throwsA(isA<AiToolInterruptedException>()));
    });

    test('四种协议：没有结束标记就结束', () async {
      final cases = <(AiProviderType, List<Object>)>[
        (AiProviderType.openai, [{'choices': [{'delta': {'content': '半截'}}]}]),
        (AiProviderType.openaiResponse, [{'type': 'response.output_text.delta', 'delta': '半截'}]),
        (AiProviderType.anthropic, [
          {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}},
          {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': '半截'}},
        ]),
        (AiProviderType.gemini, [{'candidates': [{'content': {'parts': [{'text': '半截'}]}}]}]),
      ];
      for (final (type, events) in cases) {
        await expectLater(
          run(replay(sse(events), Sent()), type),
          throwsA(isA<AiToolInterruptedException>().having((e) => e.partialText, 'partial', '半截')),
          reason: '$type',
        );
      }
    });
  });

  group('8 请求地址', () {
    test('不以 # 结尾又带查询串：版本段补在路径上，查询串留在最后', () {
      expect(
        AiToolChatService.urlFor(AiProviderType.openai, 'https://r.openai.azure.com/openai/deployments/gpt4o?api-version=2024-10-21', 'm'),
        'https://r.openai.azure.com/openai/deployments/gpt4o/v1/chat/completions?api-version=2024-10-21',
      );
    });
    test('Gemini 带查询串：版本前缀不重复', () {
      expect(
        AiToolChatService.urlFor(AiProviderType.gemini, 'https://p/v1beta?key=1', 'gemini-2.5-pro'),
        'https://p/v1beta/models/gemini-2.5-pro:streamGenerateContent?key=1&alt=sse',
      );
      expect(
        AiToolChatService.urlFor(AiProviderType.gemini, 'https://p?key=1', 'm'),
        'https://p/v1beta/models/m:streamGenerateContent?key=1&alt=sse',
      );
    });
    test('…/custom/# 不拼出双斜杠', () {
      expect(
        AiToolChatService.urlFor(AiProviderType.openai, 'https://p/custom/#', 'm'),
        'https://p/custom/chat/completions',
      );
    });
    test('以 # 结尾、查询串在前：严格使用', () {
      expect(
        AiToolChatService.urlFor(AiProviderType.openai, 'https://r/openai/deployments/d?api-version=2024#', 'm'),
        'https://r/openai/deployments/d/chat/completions?api-version=2024',
      );
    });
    test('鉴权头：每种服务商的写法（OpenAI / Azure 都是 Bearer，Anthropic x-api-key，Gemini x-goog-api-key）', () async {
      final expected = {
        AiProviderType.openai: ('authorization', 'Bearer k'),
        AiProviderType.openaiResponse: ('authorization', 'Bearer k'),
        AiProviderType.anthropic: ('x-api-key', 'k'),
        AiProviderType.gemini: ('x-goog-api-key', 'k'),
      };
      for (final e in expected.entries) {
        final s = Sent();
        try {
          await run(replay('', s), e.key, base: 'https://r.openai.azure.com/openai/deployments/d?api-version=1#');
        } catch (_) {}
        final h = {for (final x in s.requests.single.headers.entries) x.key.toLowerCase(): x.value};
        expect(h[e.value.$1], e.value.$2, reason: '${e.key}');
      }
    });
  });

  group('9 错误不被吞', () {
    test('200 但不是 SSE（代理返回 JSON 错误体）：带原文报错', () async {
      final f = run(
        replay('{"error":{"message":"quota exceeded"}}', Sent(), type: 'application/json'),
        AiProviderType.openai,
      );
      await expectLater(
        f,
        throwsA(isA<AiToolChatHttpException>().having((e) => e.message, 'message', contains('quota exceeded'))),
      );
    });

    test('Responses 只在 response.completed 里给完整输出：从里面取出正文和工具调用', () async {
      final events = await run(
        replay(
          sse([
            {
              'type': 'response.completed',
              'response': {
                'status': 'completed',
                'output': [
                  {'type': 'message', 'content': [{'type': 'output_text', 'text': '正文'}]},
                  {'type': 'function_call', 'call_id': 'c1', 'name': 'search_docs', 'arguments': '{"query":"x"}'},
                ],
              },
            },
          ]),
          Sent(),
        ),
        AiProviderType.openaiResponse,
      );
      final done = events.whereType<AiToolTurnDone>().single;
      expect(done.turn.text, '正文');
      expect(done.turn.toolCalls.single.name, 'search_docs');
    });
  });

  group('11 停止原因', () {
    test('Responses 的 response.incomplete：原因和用量都取出来', () async {
      final events = await run(
        replay(
          sse([
            {'type': 'response.output_text.delta', 'delta': '半'},
            {
              'type': 'response.incomplete',
              'response': {
                'status': 'incomplete',
                'incomplete_details': {'reason': 'max_output_tokens'},
                'usage': {'input_tokens': 10, 'output_tokens': 20},
              },
            },
          ]),
          Sent(),
        ),
        AiProviderType.openaiResponse,
      );
      expect(events.whereType<AiToolTurnDone>().single.stopReason, 'length');
      expect(events.whereType<AiToolUsage>().single.responseTokens, 20);
    });
  });

  group('12 OpenAI 兼容服务的分片', () {
    test('缺 index 时按 id 区分；同一个 index 出现新的 id 是另一个调用', () async {
      final events = await run(
        replay(
          sse([
            {'choices': [{'delta': {'tool_calls': [{'id': 'a', 'function': {'name': 'search_docs', 'arguments': '{"query":'}}]}}]},
            {'choices': [{'delta': {'tool_calls': [{'id': 'a', 'function': {'arguments': '"x"}'}}]}}]},
            {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'b', 'function': {'name': 'search_docs', 'arguments': '{"query":"y"}'}}]}}]},
            {'choices': [{'delta': {}, 'finish_reason': 'tool_calls'}]},
            '[DONE]',
          ]),
          Sent(),
        ),
        AiProviderType.openai,
      );
      final calls = events.whereType<AiToolTurnDone>().single.turn.toolCalls;
      expect(calls.map((c) => c.id), ['a', 'b']);
      expect(calls.first.argumentsJson, '{"query":"x"}');
    });

    test('参数为空串或不合法时，回传给服务商的是 {}', () async {
      final s = Sent();
      await run(
        replay(sse(['[DONE]']), s),
        AiProviderType.openai,
        turns: const [
          AiUserTurn('q'),
          AiAssistantTurn(toolCalls: [
            AiToolCall(id: 'a', name: 'search_docs', argumentsJson: ''),
            AiToolCall(id: 'b', name: 'search_docs', argumentsJson: '{bad'),
          ]),
          AiToolResultTurn(callId: 'a', name: 'search_docs', content: 'x'),
          AiToolResultTurn(callId: 'b', name: 'search_docs', content: 'x', isError: true),
        ],
      );
      final msgs = s.body['messages'] as List;
      final calls = (msgs[1] as Map)['tool_calls'] as List;
      expect([for (final c in calls) (c as Map)['function']['arguments']], ['{}', '{}']);
    });
  });

  group('13 / 14 回传时的过滤', () {
    test('Responses：没有 encrypted_content 的推理项不放回', () async {
      final s = Sent();
      await run(
        replay(sse([{'type': 'response.completed', 'response': {}}]), s),
        AiProviderType.openaiResponse,
        turns: const [
          AiUserTurn('q'),
          AiAssistantTurn(
            toolCalls: [AiToolCall(id: 'c', name: 'search_docs', argumentsJson: '{}')],
            providerState: {
              'protocol': 'responses',
              'output': [
                {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
                {'type': 'function_call', 'call_id': 'c', 'name': 'search_docs', 'arguments': '{}'},
              ],
            },
          ),
          AiToolResultTurn(callId: 'c', name: 'search_docs', content: '{}'),
        ],
      );
      final input = s.body['input'] as List;
      expect(input.any((i) => i is Map && i['type'] == 'reasoning'), isFalse);
      expect(input.any((i) => i is Map && i['type'] == 'function_call'), isTrue);
    });

    test('Gemini：没有内容也没有签名的空 text 部件不放回', () async {
      final s = Sent();
      await run(
        replay(sse([{'candidates': [{'finishReason': 'STOP'}]}]), s),
        AiProviderType.gemini,
        turns: const [
          AiUserTurn('q'),
          AiAssistantTurn(
            text: 'x',
            providerState: {
              'protocol': 'gemini',
              'parts': [
                {'text': ''},
                {'text': '好', 'thoughtSignature': 'sig'},
                {'text': ''},
              ],
            },
          ),
          AiUserTurn('再问'),
        ],
      );
      final parts = ((s.body['contents'] as List)[1] as Map)['parts'] as List;
      expect(parts, [
        {'text': '好', 'thoughtSignature': 'sig'},
      ]);
    });
  });

  group('5-6 取消订阅时主动打断这一次请求', () {
    test('取消后 abortTrigger 被触发（不用等下一个事件）', () async {
      final controller = StreamController<List<int>>();
      var aborted = false;
      final client = MockClient.streaming((req, _) async {
        (req as http.Abortable).abortTrigger!.then((_) => aborted = true);
        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final sub = AiToolChatService(bridgedClient: client)
          .stream(
            provider: provider(AiProviderType.openai),
            model: 'm',
            apiKey: 'k',
            turns: const [AiUserTurn('q')],
            tools: const [],
          )
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(aborted, isTrue);
      await controller.close();
    });
  });
}
