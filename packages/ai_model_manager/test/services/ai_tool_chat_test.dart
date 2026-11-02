import 'dart:convert';

import 'package:ai_model_manager/services/ai_tool_chat.dart';
import 'package:ai_model_manager/models/ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 回放手写的 SSE 夹具，并记下发出的请求。不联网。
class _Replay {
  _Replay(String sse, {this.status = 200, bool raw = false})
      : sse = (raw || status != 200) ? sse : _terminated(sse);

  /// 夹具没写结束标记时补上各家的（现在没有结束标记会当作「已中断」）
  static String _terminated(String s) {
    if (s.contains('[DONE]') ||
        s.contains('message_stop') ||
        s.contains('response.completed') ||
        s.contains('response.incomplete') ||
        s.contains('finishReason') ||
        s.contains('finish_reason')) {
      return s;
    }
    const tail = [
      'data: [DONE]',
      'data: {"type":"message_stop"}',
      'data: {"type":"response.completed","response":{}}',
      'data: {"candidates":[{"finishReason":"STOP"}]}',
    ];
    return '$s${tail.map((e) => '$e\n\n').join()}';
  }

  final String sse;
  final int status;
  final requests = <http.Request>[];

  Map<String, dynamic> get body =>
      jsonDecode(requests.single.body) as Map<String, dynamic>;

  http.Client get client => MockClient.streaming((req, _) async {
        requests.add(req as http.Request);
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          status,
          headers: {'content-type': 'text/event-stream'},
        );
      });
}

String _sse(List<Object> events) => events
    .map((e) => e is String ? 'data: $e\n\n' : 'data: ${jsonEncode(e)}\n\n')
    .join();

AiProvider _provider(AiProviderType type, String baseUrl) => AiProvider(
      id: 'p',
      name: 'p',
      type: type,
      baseUrl: baseUrl,
    );

const _search = AiToolSpec(
  name: 'search_docs',
  description: '搜索',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20},
    },
    'required': ['query'],
  },
);

const _noArgs = AiToolSpec(
  name: 'list_all',
  description: '无参数',
  parameters: {'type': 'object', 'properties': {}},
);

Future<List<AiToolEvent>> _run(
  _Replay replay,
  AiProvider provider, {
  List<AiToolTurn> turns = const [AiUserTurn('问题')],
  AiToolChoice choice = AiToolChoice.auto,
  String model = 'm-1',
  List<AiToolSpec> tools = const [_search, _noArgs],
}) {
  return AiToolChatService()
      .stream(
        provider: provider,
        model: model,
        apiKey: 'sk-test',
        turns: turns,
        tools: tools,
        systemPrompt: '系统提示',
        toolChoice: choice,
        requestClient: replay.client,
      )
      .toList();
}

AiToolTurnDone _done(List<AiToolEvent> events) =>
    events.whereType<AiToolTurnDone>().single;

void main() {
  group('OpenAI Chat Completions', () {
    final provider = _provider(AiProviderType.openai, 'https://api.example.com');

    test('请求体：工具定义、tool_choice、系统提示、鉴权头', () async {
      final r = _Replay(_sse(['[DONE]']));
      await _run(r, provider, choice: AiToolChoice.required);
      expect(r.requests.single.url.toString(),
          'https://api.example.com/v1/chat/completions');
      expect(r.requests.single.headers['Authorization'], 'Bearer sk-test');
      final b = r.body;
      expect(b['stream'], true);
      expect(b['tool_choice'], 'required');
      expect(b['max_tokens'], 2000);
      expect(b.containsKey('max_completion_tokens'), false);
      expect((b['messages'] as List).first,
          {'role': 'system', 'content': '系统提示'});
      final fn = ((b['tools'] as List).first as Map)['function'] as Map;
      expect(fn['name'], 'search_docs');
      expect((fn['parameters'] as Map)['required'], ['query']);
    });

    test('官方地址用 max_completion_tokens', () async {
      final r = _Replay(_sse(['[DONE]']));
      await _run(r, _provider(AiProviderType.openai, 'https://api.openai.com/v1'));
      expect(r.body['max_completion_tokens'], 2000);
      expect(r.body.containsKey('max_tokens'), false);
    });

    test('分片的两个并行工具调用被拼完整，用量每轮一次', () async {
      final r = _Replay(_sse([
        {
          'choices': [
            {
              'delta': {
                'content': '我先',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_a',
                    'function': {'name': 'search_docs', 'arguments': '{"que'},
                  },
                ],
              },
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': 'ry":"csr"}'},
                  },
                  {
                    'index': 1,
                    'id': 'call_b',
                    'function': {'name': 'list_all', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        },
        {
          'choices': [
            {'delta': {}, 'finish_reason': 'tool_calls'},
          ],
        },
        {
          'choices': [],
          'usage': {
            'prompt_tokens': 120,
            'completion_tokens': 30,
            'prompt_tokens_details': {'cached_tokens': 100},
          },
        },
        '[DONE]',
      ]));
      final events = await _run(r, provider);
      expect(events.whereType<AiToolTextDelta>().map((e) => e.text), ['我先']);
      final usage = events.whereType<AiToolUsage>().single;
      expect(usage.promptTokens, 120);
      expect(usage.responseTokens, 30);
      expect(usage.cachedTokens, 100);
      final done = _done(events);
      expect(done.stopReason, 'tool_calls');
      expect(done.turn.text, '我先');
      expect(done.turn.toolCalls.map((c) => c.id), ['call_a', 'call_b']);
      expect(done.turn.toolCalls[0].arguments, {'query': 'csr'});
      expect(done.turn.toolCalls[1].name, 'list_all');
    });

    test('reasoning_content 保存进 providerState 并原样放回', () async {
      final r = _Replay(_sse([
        {
          'choices': [
            {
              'delta': {'reasoning_content': '想一想'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'c1',
                    'function': {'name': 'list_all', 'arguments': '{}'},
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        },
        '[DONE]',
      ]));
      final assistant = _done(await _run(r, provider)).turn;
      expect(assistant.providerState, isNotNull);

      final r2 = _Replay(_sse(['[DONE]']));
      await _run(r2, provider, turns: [
        const AiUserTurn('问题'),
        assistant,
        const AiToolResultTurn(callId: 'c1', name: 'list_all', content: '{"ok":true}'),
      ]);
      final msgs = r2.body['messages'] as List;
      final a = msgs[2] as Map;
      expect(a['role'], 'assistant');
      expect(a['reasoning_content'], '想一想');
      expect((a['tool_calls'] as List).single['id'], 'c1');
      expect(msgs[3], {'role': 'tool', 'tool_call_id': 'c1', 'content': '{"ok":true}'});
    });
  });

  group('OpenAI Responses', () {
    final provider =
        _provider(AiProviderType.openaiResponse, 'https://api.example.com/v1');

    test('请求体与函数调用事件、输出项原样放回', () async {
      final r = _Replay(_sse([
        {'type': 'response.output_text.delta', 'delta': '好的'},
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'reasoning',
            'id': 'rs_1',
            'encrypted_content': 'abc',
            'summary': [],
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'call_id': 'call_9',
            'name': 'search_docs',
            'arguments': '{"query":"x"}',
          },
        },
        {
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'usage': {
              'input_tokens': 50,
              'output_tokens': 9,
              'input_tokens_details': {'cached_tokens': 40},
            },
          },
        },
      ]));
      final events = await _run(r, provider, model: 'gpt-5-mini');
      final b = r.body;
      expect(r.requests.single.url.path, '/v1/responses');
      expect(b['store'], false);
      expect(b['include'], ['reasoning.encrypted_content']);
      expect(b['instructions'], '系统提示');
      expect(b['tool_choice'], 'auto');
      final tool = (b['tools'] as List).first as Map;
      expect(tool['type'], 'function');
      expect(tool['name'], 'search_docs');

      final done = _done(events);
      expect(done.stopReason, 'tool_calls');
      expect(done.turn.toolCalls.single.id, 'call_9');
      expect(events.whereType<AiToolUsage>().single.cachedTokens, 40);

      final r2 = _Replay(_sse([]));
      await _run(r2, provider, model: 'gpt-5-mini', turns: [
        const AiUserTurn('问题'),
        done.turn,
        const AiToolResultTurn(callId: 'call_9', name: 'search_docs', content: 'R'),
      ]);
      final input = r2.body['input'] as List;
      expect((input[1] as Map)['type'], 'reasoning');
      expect((input[1] as Map)['encrypted_content'], 'abc');
      expect((input[2] as Map)['type'], 'function_call');
      expect(input[3],
          {'type': 'function_call_output', 'call_id': 'call_9', 'output': 'R'});
    });

    test('非推理模型不带 include', () async {
      final r = _Replay(_sse([]));
      await _run(r, provider, model: 'gpt-4.1');
      expect(r.body.containsKey('include'), false);
    });

    test('response.failed 抛出错误', () async {
      final r = _Replay(_sse([
        {
          'type': 'response.failed',
          'response': {
            'error': {'message': 'boom'},
          },
        },
      ]));
      expect(_run(r, provider), throwsA(isA<AiToolInterruptedException>()));
    });
  });

  group('Anthropic', () {
    final provider = _provider(AiProviderType.anthropic, 'https://api.anthropic.com');

    test('请求体：input_schema、tool_choice any、鉴权头、max_tokens', () async {
      final r = _Replay(_sse([]));
      await _run(r, provider, choice: AiToolChoice.required);
      final req = r.requests.single;
      expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'sk-test');
      expect(req.headers['anthropic-version'], '2023-06-01');
      final b = r.body;
      expect(b['max_tokens'], 2000);
      expect(b['system'], '系统提示');
      expect(b['tool_choice'], {'type': 'any'});
      final t = (b['tools'] as List).first as Map;
      expect(t['name'], 'search_docs');
      expect((t['input_schema'] as Map)['type'], 'object');
    });

    test('tool_use 的 input_json_delta 拼接，thinking 块连同签名原样放回，结果合并成一条 user', () async {
      final r = _Replay(_sse([
        {
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 200, 'output_tokens': 1, 'cache_read_input_tokens': 150},
          },
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': '嗯'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig=='},
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {'type': 'text', 'text': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'text_delta', 'text': '查一下'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'content_block_start',
          'index': 2,
          'content_block': {'type': 'tool_use', 'id': 'tu_1', 'name': 'search_docs', 'input': {}},
        },
        {
          'type': 'content_block_delta',
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"query":'},
        },
        {
          'type': 'content_block_delta',
          'index': 2,
          'delta': {'type': 'input_json_delta', 'partial_json': '"csr"}'},
        },
        {'type': 'content_block_stop', 'index': 2},
        {
          'type': 'content_block_start',
          'index': 3,
          'content_block': {'type': 'tool_use', 'id': 'tu_2', 'name': 'list_all', 'input': {}},
        },
        {'type': 'content_block_stop', 'index': 3},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 33},
        },
      ]));
      final events = await _run(r, provider);
      final done = _done(events);
      expect(done.stopReason, 'tool_use');
      expect(done.turn.text, '查一下');
      expect(done.turn.toolCalls.map((c) => c.id), ['tu_1', 'tu_2']);
      expect(done.turn.toolCalls[0].arguments, {'query': 'csr'});
      expect(done.turn.toolCalls[1].arguments, <String, dynamic>{});
      final usage = events.whereType<AiToolUsage>().single;
      expect(usage.promptTokens, 200);
      expect(usage.responseTokens, 33);
      expect(usage.cachedTokens, 150);

      final r2 = _Replay(_sse([]));
      await _run(r2, provider, turns: [
        const AiUserTurn('问题'),
        done.turn,
        const AiToolResultTurn(callId: 'tu_1', name: 'search_docs', content: 'A'),
        const AiToolResultTurn(callId: 'tu_2', name: 'list_all', content: 'B', isError: true),
      ]);
      final msgs = r2.body['messages'] as List;
      expect(msgs.length, 3);
      final blocks = (msgs[1] as Map)['content'] as List;
      expect((blocks[0] as Map)['type'], 'thinking');
      expect((blocks[0] as Map)['signature'], 'sig==');
      expect((blocks[2] as Map)['input'], {'query': 'csr'});
      final results = (msgs[2] as Map)['content'] as List;
      expect(results.length, 2);
      expect((results[0] as Map)['tool_use_id'], 'tu_1');
      expect((results[1] as Map)['is_error'], true);
    });
  });

  group('Gemini', () {
    final provider =
        _provider(AiProviderType.gemini, 'https://generativelanguage.googleapis.com/v1beta');

    test('请求体：大写类型、无参数工具不带 parameters、ANY、鉴权头', () async {
      final r = _Replay(_sse([]));
      await _run(r, provider, choice: AiToolChoice.required, model: 'gemini-2.5-flash');
      final req = r.requests.single;
      expect(req.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse');
      expect(req.headers['x-goog-api-key'], 'sk-test');
      final b = r.body;
      expect(b['toolConfig'], {
        'functionCallingConfig': {'mode': 'ANY'},
      });
      expect(b['systemInstruction'], {
        'parts': [
          {'text': '系统提示'},
        ],
      });
      final decls = ((b['tools'] as List).single as Map)['functionDeclarations'] as List;
      final search = decls[0] as Map;
      expect((search['parameters'] as Map)['type'], 'OBJECT');
      expect(
        (((search['parameters'] as Map)['properties'] as Map)['limit'] as Map)['type'],
        'INTEGER',
      );
      expect((decls[1] as Map).containsKey('parameters'), false);
    });

    test('functionCall 与 thoughtSignature 原样放回，结果合并成一条 user', () async {
      final r = _Replay(_sse([
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '先查'},
                  {
                    'functionCall': {'name': 'search_docs', 'args': {'query': 'csr'}},
                    'thoughtSignature': 'SIG',
                  },
                  {
                    'functionCall': {'name': 'list_all', 'args': {}},
                  },
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': {
            'promptTokenCount': 70,
            'candidatesTokenCount': 12,
            'cachedContentTokenCount': 60,
          },
        },
      ]));
      final events = await _run(r, provider);
      final done = _done(events);
      expect(done.turn.text, '先查');
      expect(done.turn.toolCalls.length, 2);
      expect(done.turn.toolCalls[0].arguments, {'query': 'csr'});
      expect(done.stopReason, 'tool_calls');
      expect(events.whereType<AiToolUsage>().single.cachedTokens, 60);

      final r2 = _Replay(_sse([]));
      await _run(r2, provider, turns: [
        const AiUserTurn('问题'),
        done.turn,
        const AiToolResultTurn(callId: 'gemini_call_0', name: 'search_docs', content: '{"ok":true}'),
        const AiToolResultTurn(callId: 'gemini_call_1', name: 'list_all', content: '纯文本'),
      ]);
      final contents = r2.body['contents'] as List;
      expect(contents.length, 3);
      final modelParts = (contents[1] as Map)['parts'] as List;
      expect((modelParts[1] as Map)['thoughtSignature'], 'SIG');
      final back = (contents[2] as Map)['parts'] as List;
      expect(back.length, 2);
      expect(((back[0] as Map)['functionResponse'] as Map)['response'], {'ok': true});
      expect(((back[1] as Map)['functionResponse'] as Map)['response'], {'result': '纯文本'});
    });

    test('thought 文本不显示给用户', () async {
      final r = _Replay(_sse([
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '内部思考', 'thought': true},
                  {'text': '答案'},
                ],
              },
            },
          ],
        },
      ]));
      final events = await _run(r, provider);
      expect(events.whereType<AiToolTextDelta>().map((e) => e.text), ['答案']);
    });
  });

  group('错误分类', () {
    final provider = _provider(AiProviderType.openai, 'https://api.example.com');

    Future<Object> failWith(int status, String body) async {
      final r = _Replay(body, status: status);
      try {
        await _run(r, provider);
      } catch (e) {
        return e;
      }
      fail('应该抛错');
    }

    test('Ollama / OpenRouter / 通用 400 都是不支持工具', () async {
      expect(
        await failWith(400,
            '{"error":{"message":"registry.ollama.ai/library/x does not support tools"}}'),
        isA<AiToolsUnsupportedException>(),
      );
      expect(
        await failWith(404,
            '{"error":{"message":"No endpoints found that support tool use"}}'),
        isA<AiToolsUnsupportedException>(),
      );
      expect(await failWith(400, '{"error":"tools is not supported"}'),
          isA<AiToolsUnsupportedException>());
    });

    test('tool_choice 被拒单独识别', () async {
      expect(
        await failWith(400,
            '{"error":{"message":"Invalid value for tool_choice: required is not supported"}}'),
        isA<AiToolChoiceUnsupportedException>(),
      );
    });

    test('其他错误带状态码和原文', () async {
      final e = await failWith(401, '{"error":{"message":"Incorrect API key"}}');
      expect(e, isA<AiToolChatHttpException>());
      expect((e as AiToolChatHttpException).statusCode, 401);
      expect(e.message, 'Incorrect API key');
      final e2 = await failWith(429, 'slow down');
      expect((e2 as AiToolChatHttpException).statusCode, 429);
      final e3 = await failWith(400, '{"error":{"message":"max_tokens too large"}}');
      expect(e3, isA<AiToolChatHttpException>());
    });
  });

  group('请求发到用户配置的地址（和现有对话共用 ApiHostFormatter 的规则）', () {
    Future<Uri> urlFor(AiProviderType type, String base, {String model = 'm-1'}) async {
      final r = _Replay(_sse([]));
      await _run(r, _provider(type, base), model: model);
      return r.requests.single.url;
    }

    test('OpenRouter：地址里已有版本段，不重复补', () async {
      final u = await urlFor(AiProviderType.openai, 'https://openrouter.ai/api/v1');
      expect(u.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    });

    test('Ollama：局域网地址没写版本时补 /v1，保留端口和 http', () async {
      final u = await urlFor(AiProviderType.openai, 'http://192.168.1.5:11434');
      expect(u.toString(), 'http://192.168.1.5:11434/v1/chat/completions');
    });

    test('DeepSeek：官方地址补 /v1', () async {
      final u = await urlFor(AiProviderType.openai, 'https://api.deepseek.com/');
      expect(u.toString(), 'https://api.deepseek.com/v1/chat/completions');
    });

    test('Azure：以 # 结尾的严格地址原样使用，api-version 查询串留在末尾', () async {
      final u = await urlFor(
        AiProviderType.openai,
        'https://res.openai.azure.com/openai/deployments/gpt4o?api-version=2024-10-21#',
      );
      expect(u.path, '/openai/deployments/gpt4o/chat/completions');
      expect(u.queryParameters, {'api-version': '2024-10-21'});
    });

    test('自定义网关路径：带 # 不补版本；Responses 和 Anthropic 同样接在配置地址后面', () async {
      var u = await urlFor(AiProviderType.openai, 'https://gw.example.com/custom#');
      expect(u.toString(), 'https://gw.example.com/custom/chat/completions');
      u = await urlFor(AiProviderType.openaiResponse, 'https://gw.example.com/openai/v1');
      expect(u.toString(), 'https://gw.example.com/openai/v1/responses');
      u = await urlFor(AiProviderType.anthropic, 'https://proxy.example.com');
      expect(u.toString(), 'https://proxy.example.com/v1/messages');
    });

    test('Gemini：自定义地址，用户写的 /v1beta 不重复；alt=sse 与已有查询串合并', () async {
      var u = await urlFor(AiProviderType.gemini, 'https://gemini-proxy.example.com/v1beta', model: 'gemini-2.5-pro');
      expect(u.toString(), 'https://gemini-proxy.example.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse');
      u = await urlFor(AiProviderType.gemini, 'https://gemini-proxy.example.com/x?key=1#', model: 'g');
      expect(u.queryParameters, {'key': '1', 'alt': 'sse'});
    });

    test('鉴权头和密钥：每家用自己的头，不混用', () async {
      for (final (type, header, value) in [
        (AiProviderType.openai, 'Authorization', 'Bearer sk-test'),
        (AiProviderType.openaiResponse, 'Authorization', 'Bearer sk-test'),
        (AiProviderType.anthropic, 'x-api-key', 'sk-test'),
        (AiProviderType.gemini, 'x-goog-api-key', 'sk-test'),
      ]) {
        final r = _Replay(_sse([]));
        await _run(r, _provider(type, 'https://api.example.com'));
        expect(r.requests.single.headers[header], value, reason: '$type');
      }
    });

    test('走调用方给的 http client（应用网络栈、代理、取消都由它负责），自己不另建连接', () async {
      var used = 0;
      final client = MockClient.streaming((req, _) async {
        used++;
        return http.StreamedResponse(Stream.value(utf8.encode(_sse(['[DONE]']))), 200);
      });
      await AiToolChatService(bridgedClient: client)
          .stream(
            provider: _provider(AiProviderType.openai, 'https://api.example.com'),
            model: 'm',
            apiKey: 'k',
            turns: const [AiUserTurn('q')],
            tools: const [],
          )
          .toList();
      expect(used, 1);
    });
  });

  test('AiToolCall.arguments：不合法的 JSON 返回 null，空串返回空对象', () {
    expect(const AiToolCall(id: 'a', name: 'n', argumentsJson: '{bad').arguments, isNull);
    expect(const AiToolCall(id: 'a', name: 'n', argumentsJson: '').arguments, isEmpty);
    expect(const AiToolCall(id: 'a', name: 'n', argumentsJson: '[1]').arguments, isNull);
  });
}
