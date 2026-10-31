import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_provider.dart';
import '../utils/api_host_formatter.dart';

/// 带工具调用的对话（function calling）。
///
/// 这一层只负责把「工具定义 + 对话历史」按各家协议发出去，把流式响应还原成
/// 统一的事件；不内置任何工具，也不执行工具——执行和循环由调用方负责。
///
/// 直接走 HTTP + SSE（不经过各家 SDK 的类型），四种协议的请求体和事件都能在
/// 单元测试里用 `MockClient` 逐字核对。
///
/// 工具参数的 schema 只使用通用子集（object / string / integer / boolean /
/// array / enum，加 description、required、minimum、maximum、maxItems），
/// 四种协议都能原样使用。

/// 工具定义：名字（`^[a-zA-Z0-9_-]{1,64}$`）、说明、JSON schema。
class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

/// 模型要求调用的一个工具。
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;

  /// 模型给出的参数原文（JSON 字符串，可能不合法）
  final String argumentsJson;

  /// 解析后的参数；不是 JSON 对象时返回 null
  Map<String, dynamic>? get arguments {
    if (argumentsJson.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(argumentsJson);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// 对话里的一项。
sealed class AiToolTurn {
  const AiToolTurn();
}

class AiUserTurn extends AiToolTurn {
  const AiUserTurn(this.text);
  final String text;
}

class AiAssistantTurn extends AiToolTurn {
  const AiAssistantTurn({
    this.text = '',
    this.toolCalls = const [],
    this.providerState,
  });

  final String text;
  final List<AiToolCall> toolCalls;

  /// 各家要求原样放回的内容（thinking 块、reasoning 输出项、thoughtSignature、
  /// reasoning_content）。上层不要解读，只管随这一项一起保存、回传。
  final Object? providerState;
}

class AiToolResultTurn extends AiToolTurn {
  const AiToolResultTurn({
    required this.callId,
    required this.name,
    required this.content,
    this.isError = false,
  });

  final String callId;
  final String name;
  final String content;
  final bool isError;
}

/// [unspecified]：请求里不带 tool_choice（有的服务商连 auto 也不认）
enum AiToolChoice { auto, required, none, unspecified }

/// 工具对话的流事件。
sealed class AiToolEvent {
  const AiToolEvent();
}

/// 正文增量
class AiToolTextDelta extends AiToolEvent {
  const AiToolTextDelta(this.text);
  final String text;
}

/// 这一轮的用量（每轮最多一次）
class AiToolUsage extends AiToolEvent {
  const AiToolUsage({this.promptTokens, this.responseTokens, this.cachedTokens});
  final int? promptTokens;
  final int? responseTokens;
  final int? cachedTokens;
}

/// 这一轮结束：完整的 assistant 一项（含工具调用和 providerState）
class AiToolTurnDone extends AiToolEvent {
  const AiToolTurnDone(this.turn, {this.stopReason});
  final AiAssistantTurn turn;
  final String? stopReason;
}

/// 流里收到了数据（推理分片、工具参数分片、心跳等，没有别的事件可发时用它）。
/// 上层的空闲超时按「收到任何数据」重新计时，不会把长时间思考误判成卡死。
class AiToolActivity extends AiToolEvent {
  const AiToolActivity();
}

/// 流中途出错，或者没有结束标记就断开：已经生成的部分在 [partialText] 里，
/// 不能当成完整回答。
class AiToolInterruptedException implements Exception {
  const AiToolInterruptedException(this.message, {this.partialText = ''});
  final String message;
  final String partialText;
  @override
  String toString() => message;
}

/// 服务商 / 模型不支持工具调用
class AiToolsUnsupportedException implements Exception {
  const AiToolsUnsupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 服务商不接受 `tool_choice`（比如只认 auto）；上层改用 auto 重发
class AiToolChoiceUnsupportedException implements Exception {
  const AiToolChoiceUnsupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 其他 HTTP 错误；[message] 是服务商返回的原文，界面上由上层按状态码给友好提示
class AiToolChatHttpException implements Exception {
  const AiToolChatHttpException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'HTTP $statusCode: $message';
}

typedef _Sse = ({String? event, String data});

class _OaCall {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
}

/// 工具对话服务。网络客户端由调用方注入（应用网络栈 / 可取消的 client）。
class AiToolChatService {
  AiToolChatService({this.bridgedClient});

  final http.Client? bridgedClient;

  Stream<AiToolEvent> stream({
    required AiProvider provider,
    required String model,
    required String apiKey,
    required List<AiToolTurn> turns,
    required List<AiToolSpec> tools,
    String? systemPrompt,
    AiToolChoice toolChoice = AiToolChoice.auto,
    int maxOutputTokens = 2000,
    http.Client? requestClient,
  }) {
    // 取消订阅时主动打断这一次请求（abortTrigger + 自己创建的 client），
    // 不能等生成器走到下一个 yield。
    final abort = Completer<void>();
    final client = requestClient ?? bridgedClient ?? http.Client();
    final ownsClient = requestClient == null && bridgedClient == null;
    StreamSubscription<AiToolEvent>? inner;
    late final StreamController<AiToolEvent> out;
    out = StreamController<AiToolEvent>(
      onListen: () {
        inner = _run(
          client,
          abort,
          provider,
          model,
          apiKey,
          turns,
          tools,
          systemPrompt,
          toolChoice,
          maxOutputTokens,
        ).listen(
          out.add,
          onError: out.addError,
          onDone: () {
            if (ownsClient) client.close();
            out.close();
          },
        );
      },
      onPause: () => inner?.pause(),
      onResume: () => inner?.resume(),
      onCancel: () {
        if (!abort.isCompleted) abort.complete();
        if (ownsClient) client.close();
        // 不 await：生成器停在读网络的 await 上时，取消要等它走到下一步才完成，
        // 这里已经主动打断了请求，不用等
        inner?.cancel().then<void>((_) {}, onError: (Object _) {});
      },
    );
    return out.stream;
  }

  Stream<AiToolEvent> _run(
    http.Client client,
    Completer<void> abort,
    AiProvider provider,
    String model,
    String apiKey,
    List<AiToolTurn> turns,
    List<AiToolSpec> tools,
    String? systemPrompt,
    AiToolChoice toolChoice,
    int maxOutputTokens,
  ) async* {
    final trigger = abort.future;
    final req = switch (provider.type) {
      AiProviderType.openai => _openAiRequest(provider.baseUrl, apiKey, model,
          turns, tools, systemPrompt, toolChoice, maxOutputTokens, trigger),
      AiProviderType.openaiResponse => _responsesRequest(provider.baseUrl,
          apiKey, model, turns, tools, systemPrompt, toolChoice,
          maxOutputTokens, trigger),
      AiProviderType.anthropic => _anthropicRequest(provider.baseUrl, apiKey,
          model, turns, tools, systemPrompt, toolChoice, maxOutputTokens,
          trigger),
      AiProviderType.gemini => _geminiRequest(provider.baseUrl, apiKey, model,
          turns, tools, systemPrompt, toolChoice, maxOutputTokens, trigger),
    };
    final http.StreamedResponse response;
    try {
      response = await client.send(req);
    } on http.RequestAbortedException {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 10), onTimeout: () => '');
      throw classifyHttpError(response.statusCode, body);
    }
    // 200 但不是 SSE（代理把错误包成 JSON 返回）：带上原文报错，不当成「没有内容」
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.isNotEmpty && !contentType.contains('event-stream')) {
      final body = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 10), onTimeout: () => '');
      final msg = _errorMessage(body);
      throw AiToolChatHttpException(
        response.statusCode,
        msg.isEmpty ? '服务商没有返回流式数据' : msg,
      );
    }
    final events = _sse(response.stream);
    try {
      yield* switch (provider.type) {
        AiProviderType.openai => _parseOpenAi(events),
        AiProviderType.openaiResponse => _parseResponses(events),
        AiProviderType.anthropic => _parseAnthropic(events),
        AiProviderType.gemini => _parseGemini(events),
      };
    } on http.RequestAbortedException {
      return;
    }
  }

  // ───────────────────────── 错误分类 ─────────────────────────

  /// 只认明确的「不支持工具」说法；上下文超长、文档链接里的 #tool-calls、
  /// FastAPI 422 里的 `tool_call_id` 之类都不算。
  static final List<RegExp> _unsupportedPatterns = [
    RegExp(r'does(?:n.t| not) support (?:the )?(?:tools?|function)', caseSensitive: false),
    RegExp(r'tools? (?:are|is) not supported', caseSensitive: false),
    RegExp(r'tool use is not supported', caseSensitive: false),
    RegExp(r'no endpoints found that support tool', caseSensitive: false),
    RegExp(r'function[ _-]?calling is not supported', caseSensitive: false),
    RegExp(r'(?:does not|doesn.t) support (?:function[ _-]?calling|tool[ _-]?use)', caseSensitive: false),
    RegExp(r'unrecognized request arguments? supplied:?[^"]*\btools?\b', caseSensitive: false),
    RegExp(r'tools? param requires --jinja', caseSensitive: false),
  ];

  /// 是不是明确的「不支持工具」报错（返回 400/404/422，llama.cpp 的 --jinja 提示是 500）
  static bool isToolsUnsupported(int status, String message, String body) {
    final text = '$message\n$body';
    final llama = RegExp(r'tools? param requires --jinja', caseSensitive: false);
    if (status == 500) return llama.hasMatch(text);
    if (status != 400 && status != 404 && status != 422) return false;
    return _unsupportedPatterns.any((p) => p.hasMatch(text));
  }

  /// 把非 2xx 的响应归类：不支持工具、不接受 tool_choice、Key 无效、其他。
  static Exception classifyHttpError(int status, String body) {
    final message = _errorMessage(body);
    final lower = '$message $body'.toLowerCase();
    if (status == 400 || status == 404 || status == 422) {
      if (lower.contains('tool_choice') ||
          lower.contains('toolchoice') ||
          lower.contains('function_calling_config') ||
          lower.contains('functioncallingconfig')) {
        return AiToolChoiceUnsupportedException(message);
      }
    }
    if (isToolsUnsupported(status, message, body)) {
      return AiToolsUnsupportedException(message);
    }
    // Gemini 的 Key 错误是 400 + API_KEY_INVALID：按鉴权失败处理
    if (status == 400 &&
        (lower.contains('api_key_invalid') || lower.contains('api key not valid'))) {
      return AiToolChatHttpException(401, message);
    }
    return AiToolChatHttpException(status, message);
  }

  static String _errorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        if (e is Map && e['message'] is String) return e['message'] as String;
        if (e is String) return e;
        if (j['message'] is String) return j['message'] as String;
      }
    } catch (_) {}
    final t = body.trim();
    return t.length > 500 ? t.substring(0, 500) : t;
  }

  // ───────────────────────── SSE ─────────────────────────

  static Stream<_Sse> _sse(Stream<List<int>> bytes) async* {
    String? event;
    final data = <String>[];
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) yield (event: event, data: data.join('\n'));
        event = null;
        data.clear();
        continue;
      }
      if (line.startsWith(':')) {
        yield (event: ':', data: ''); // 心跳：只用来表示连接还活着
        continue;
      }
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        var v = line.substring(5);
        if (v.startsWith(' ')) v = v.substring(1);
        data.add(v);
      }
    }
    if (data.isNotEmpty) yield (event: event, data: data.join('\n'));
  }

  static Map<String, dynamic>? _json(String data) {
    try {
      final j = jsonDecode(data);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static String _choiceName(AiToolChoice c, String auto, String req, String none) =>
      switch (c) {
        AiToolChoice.auto => auto,
        AiToolChoice.required => req,
        AiToolChoice.none => none,
        AiToolChoice.unspecified => auto,
      };

  // ───────────────────────── OpenAI Chat Completions ─────────────────────────

  static http.Request _openAiRequest(
    String baseUrl,
    String apiKey,
    String model,
    List<AiToolTurn> turns,
    List<AiToolSpec> tools,
    String? system,
    AiToolChoice choice,
    int maxTokens,
    Future<void> abort,
  ) {
    final b = _splitBase(baseUrl);
    final base = b.query.isEmpty ? b.head : '${b.head}?${b.query}';
    final messages = <Map<String, Object?>>[
      if (system != null && system.isNotEmpty)
        {'role': 'system', 'content': system},
    ];
    for (final t in turns) {
      switch (t) {
        case AiUserTurn():
          messages.add({'role': 'user', 'content': t.text});
        case AiAssistantTurn():
          final state = t.providerState;
          final m = <String, Object?>{
            'role': 'assistant',
            'content': t.text.isEmpty ? null : t.text,
          };
          if (t.toolCalls.isNotEmpty) {
            m['tool_calls'] = [
              for (final c in t.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': _safeArgs(c)},
                },
            ];
          }
          if (state is Map &&
              state['protocol'] == 'openai' &&
              state['reasoning_content'] is String) {
            m['reasoning_content'] = state['reasoning_content'];
          }
          messages.add(m);
        case AiToolResultTurn():
          messages.add({
            'role': 'tool',
            'tool_call_id': t.callId,
            'content': t.content,
          });
      }
    }
    // OpenAI 官方的新模型不认 max_tokens；兼容服务（DeepSeek、Ollama 等）认 max_tokens
    final official = b.head.contains('api.openai.com');
    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (official) 'max_completion_tokens': maxTokens else 'max_tokens': maxTokens,
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final s in tools)
            {
              'type': 'function',
              'function': {
                'name': s.name,
                'description': s.description,
                'parameters': s.parameters,
              },
            },
        ],
        if (choice != AiToolChoice.unspecified)
          'tool_choice': _choiceName(choice, 'auto', 'required', 'none'),
      },
    };
    return _post(_join(base, '/chat/completions'), body, {
      'Authorization': 'Bearer $apiKey',
    }, abort);
  }

  static Stream<AiToolEvent> _parseOpenAi(Stream<_Sse> events) async* {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final list = <_OaCall>[];
    final byIndex = <int, _OaCall>{};
    String? stop;
    var finished = false;
    int? prompt, completion, cached;
    await for (final e in events) {
      yield const AiToolActivity();
      if (e.data.trim() == '[DONE]') {
        finished = true;
        break;
      }
      final j = _json(e.data);
      if (j == null) continue;
      // OpenRouter 等：流中间给 error 分片
      final err = j['error'];
      if (err != null) {
        final msg = err is Map ? (err['message'] ?? '$err') : '$err';
        throw AiToolInterruptedException('$msg', partialText: text.toString());
      }
      final usage = j['usage'];
      if (usage is Map) {
        prompt = _int(usage['prompt_tokens']) ?? prompt;
        completion = _int(usage['completion_tokens']) ?? completion;
        final d = usage['prompt_tokens_details'];
        if (d is Map) cached = _int(d['cached_tokens']) ?? cached;
      }
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices.first;
      if (choice is! Map) continue;
      final fr = choice['finish_reason'];
      if (fr is String) {
        if (fr == 'error') {
          throw AiToolInterruptedException('服务商在生成中途出错', partialText: text.toString());
        }
        stop = fr;
        finished = true;
      }
      final delta = choice['delta'];
      if (delta is! Map) continue;
      final c = delta['content'];
      if (c is String && c.isNotEmpty) {
        text.write(c);
        yield AiToolTextDelta(c);
      }
      final r = delta['reasoning_content'] ?? delta['reasoning'];
      if (r is String && r.isNotEmpty) reasoning.write(r);
      final tcs = delta['tool_calls'];
      if (tcs is List) {
        for (final tc in tcs) {
          if (tc is! Map) continue;
          final index = _int(tc['index']);
          final idStr = (tc['id'] is String && (tc['id'] as String).isNotEmpty)
              ? tc['id'] as String
              : null;
          final fn = tc['function'];
          // 找当前这个调用：有 index 按 index，没有就按 id，再没有接在最后一个后面
          _OaCall? cur = index != null
              ? byIndex[index]
              : (idStr != null
                  ? list.where((x) => x.id == idStr).firstOrNull
                  : list.lastOrNull);
          // 同一个 index 出现新的 id：是另一个调用
          if (cur != null && idStr != null && cur.id.isNotEmpty && cur.id != idStr) {
            cur = null;
          }
          if (cur == null) {
            cur = _OaCall()..id = idStr ?? '';
            list.add(cur);
          } else if (cur.id.isEmpty && idStr != null) {
            cur.id = idStr;
          }
          if (index != null) byIndex[index] = cur;
          if (fn is Map) {
            if (fn['name'] is String && (fn['name'] as String).isNotEmpty) {
              cur.name = fn['name'] as String;
            }
            if (fn['arguments'] is String) cur.args.write(fn['arguments']);
          }
        }
      }
    }
    if (!finished) {
      throw AiToolInterruptedException('连接在回答结束前断开了', partialText: text.toString());
    }
    if (prompt != null || completion != null) {
      yield AiToolUsage(
        promptTokens: prompt,
        responseTokens: completion,
        cachedTokens: cached,
      );
    }
    yield AiToolTurnDone(
      AiAssistantTurn(
        text: text.toString(),
        toolCalls: [
          for (var i = 0; i < list.length; i++)
            AiToolCall(
              id: list[i].id.isEmpty ? 'call_$i' : list[i].id,
              name: list[i].name,
              argumentsJson: list[i].args.toString(),
            ),
        ],
        providerState: reasoning.isEmpty
            ? null
            : {'protocol': 'openai', 'reasoning_content': reasoning.toString()},
      ),
      stopReason: stop,
    );
  }

  // ───────────────────────── OpenAI Responses ─────────────────────────

  static final RegExp _openAiReasoningModel = RegExp(r'(^|[/:])(o\d|gpt-5)');

  static http.Request _responsesRequest(
    String baseUrl,
    String apiKey,
    String model,
    List<AiToolTurn> turns,
    List<AiToolSpec> tools,
    String? system,
    AiToolChoice choice,
    int maxTokens,
    Future<void> abort,
  ) {
    final b = _splitBase(baseUrl);
    final base = b.query.isEmpty ? b.head : '${b.head}?${b.query}';
    final input = <Map<String, Object?>>[];
    for (final t in turns) {
      switch (t) {
        case AiUserTurn():
          input.add({'role': 'user', 'content': t.text});
        case AiAssistantTurn():
          final state = t.providerState;
          if (state is Map &&
              state['protocol'] == 'responses' &&
              state['output'] is List) {
            // 原样放回上一轮的全部输出项（reasoning、message、function_call）
            for (final item in state['output'] as List) {
              if (item is! Map) continue;
              // 没有 encrypted_content 的推理项在 store:false 下放回去会 400，不放
              if (item['type'] == 'reasoning' && item['encrypted_content'] == null) continue;
              input.add(Map<String, Object?>.from(item));
            }
          } else {
            if (t.text.isNotEmpty) {
              input.add({'role': 'assistant', 'content': t.text});
            }
            for (final c in t.toolCalls) {
              input.add({
                'type': 'function_call',
                'call_id': c.id,
                'name': c.name,
                'arguments': _safeArgs(c),
              });
            }
          }
        case AiToolResultTurn():
          input.add({
            'type': 'function_call_output',
            'call_id': t.callId,
            'output': t.content,
          });
      }
    }
    final reasoning = _openAiReasoningModel.hasMatch(model.toLowerCase());
    final body = <String, Object?>{
      'model': model,
      'input': input,
      if (system != null && system.isNotEmpty) 'instructions': system,
      'stream': true,
      'store': false,
      'max_output_tokens': maxTokens,
      if (reasoning) 'include': ['reasoning.encrypted_content'],
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final s in tools)
            {
              'type': 'function',
              'name': s.name,
              'description': s.description,
              'parameters': s.parameters,
            },
        ],
        if (choice != AiToolChoice.unspecified)
          'tool_choice': _choiceName(choice, 'auto', 'required', 'none'),
      },
    };
    return _post(_join(base, '/responses'), body, {'Authorization': 'Bearer $apiKey'}, abort);
  }

  static Stream<AiToolEvent> _parseResponses(Stream<_Sse> events) async* {
    final text = StringBuffer();
    final output = <Map<String, dynamic>>[];
    int? prompt, completion, cached;
    String? stop;
    var finished = false;
    List<dynamic>? completedOutput;
    await for (final e in events) {
      yield const AiToolActivity();
      final j = _json(e.data);
      if (j == null) continue;
      switch (j['type']) {
        case 'response.output_text.delta':
          final d = j['delta'];
          if (d is String && d.isNotEmpty) {
            text.write(d);
            yield AiToolTextDelta(d);
          }
        case 'response.output_item.done':
          final item = j['item'];
          if (item is Map<String, dynamic>) output.add(item);
        case 'response.completed':
        case 'response.incomplete':
          finished = true;
          final r = j['response'];
          if (r is Map) {
            final u = r['usage'];
            if (u is Map) {
              prompt = _int(u['input_tokens']);
              completion = _int(u['output_tokens']);
              final d = u['input_tokens_details'];
              if (d is Map) cached = _int(d['cached_tokens']);
            }
            stop = r['status'] as String?;
            if (j['type'] == 'response.incomplete') {
              final d = r['incomplete_details'];
              final reason = d is Map ? d['reason'] as String? : null;
              stop = reason == 'max_output_tokens'
                  ? 'length'
                  : (reason == 'content_filter' ? 'content_filter' : 'incomplete');
            }
            // 只在 completed 里给完整输出（没有 output_item.done）时从这里取
            if (r['output'] is List) completedOutput = r['output'] as List;
          }
        case 'response.failed':
        case 'error':
          final r = j['response'];
          final err = (r is Map ? r['error'] : null) ?? j['error'] ?? j;
          final msg = err is Map ? (err['message'] ?? '$err') : '$err';
          throw AiToolInterruptedException('$msg', partialText: text.toString());
      }
    }
    if (!finished) {
      throw AiToolInterruptedException('连接在回答结束前断开了', partialText: text.toString());
    }
    if (output.isEmpty && completedOutput != null) {
      for (final item in completedOutput) {
        if (item is Map<String, dynamic>) output.add(item);
      }
      if (text.isEmpty) {
        for (final item in output) {
          if (item['type'] == 'message' && item['content'] is List) {
            for (final c in item['content'] as List) {
              if (c is Map && c['type'] == 'output_text' && c['text'] is String) {
                text.write(c['text']);
                yield AiToolTextDelta(c['text'] as String);
              }
            }
          }
        }
      }
    }
    if (prompt != null || completion != null) {
      yield AiToolUsage(
        promptTokens: prompt,
        responseTokens: completion,
        cachedTokens: cached,
      );
    }
    final calls = <AiToolCall>[
      for (final item in output)
        if (item['type'] == 'function_call')
          AiToolCall(
            id: (item['call_id'] ?? item['id'] ?? '') as String,
            name: (item['name'] ?? '') as String,
            argumentsJson: (item['arguments'] ?? '') as String,
          ),
    ];
    yield AiToolTurnDone(
      AiAssistantTurn(
        text: text.toString(),
        toolCalls: calls,
        providerState: output.isEmpty
            ? null
            : {'protocol': 'responses', 'output': output},
      ),
      stopReason: calls.isNotEmpty ? 'tool_calls' : stop,
    );
  }

  // ───────────────────────── Anthropic ─────────────────────────

  static http.Request _anthropicRequest(
    String baseUrl,
    String apiKey,
    String model,
    List<AiToolTurn> turns,
    List<AiToolSpec> tools,
    String? system,
    AiToolChoice choice,
    int maxTokens,
    Future<void> abort,
  ) {
    final b = _splitBase(baseUrl);
    final base = b.query.isEmpty ? b.head : '${b.head}?${b.query}';
    final messages = <Map<String, Object?>>[];
    List<Map<String, Object?>>? pendingResults;
    void flush() {
      if (pendingResults != null) {
        messages.add({'role': 'user', 'content': pendingResults});
        pendingResults = null;
      }
    }

    for (final t in turns) {
      switch (t) {
        case AiUserTurn():
          flush();
          messages.add({'role': 'user', 'content': t.text});
        case AiAssistantTurn():
          flush();
          final state = t.providerState;
          List<Object?> blocks;
          if (state is Map &&
              state['protocol'] == 'anthropic' &&
              state['content'] is List) {
            blocks = [...(state['content'] as List)];
          } else {
            blocks = [
              if (t.text.isNotEmpty) {'type': 'text', 'text': t.text},
              for (final c in t.toolCalls)
                {
                  'type': 'tool_use',
                  'id': c.id,
                  'name': c.name,
                  'input': c.arguments ?? const <String, Object?>{},
                },
            ];
          }
          // Anthropic 不接受空文本块
          blocks.removeWhere(
            (b) =>
                b is Map &&
                b['type'] == 'text' &&
                ((b['text'] as String?) ?? '').isEmpty,
          );
          if (blocks.isEmpty) blocks = [{'type': 'text', 'text': '…'}];
          messages.add({'role': 'assistant', 'content': blocks});
        case AiToolResultTurn():
          (pendingResults ??= []).add({
            'type': 'tool_result',
            'tool_use_id': t.callId,
            'content': t.content,
            if (t.isError) 'is_error': true,
          });
      }
    }
    flush();
    final body = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      if (system != null && system.isNotEmpty) 'system': system,
      'messages': messages,
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final s in tools)
            {
              'name': s.name,
              'description': s.description,
              'input_schema': s.parameters,
            },
        ],
        if (choice != AiToolChoice.unspecified)
          'tool_choice': {'type': _choiceName(choice, 'auto', 'any', 'none')},
      },
    };
    return _post(_join(base, '/messages'), body, {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    }, abort);
  }

  static Stream<AiToolEvent> _parseAnthropic(Stream<_Sse> events) async* {
    final text = StringBuffer();
    final blocks = <int, Map<String, dynamic>>{};
    final jsonBuf = <int, StringBuffer>{};
    int? prompt, completion, cached;
    String? stop;
    var finished = false;
    await for (final e in events) {
      yield const AiToolActivity();
      final j = _json(e.data);
      if (j == null) continue;
      switch (j['type']) {
        case 'message_stop':
          finished = true;
        case 'message_start':
          final m = j['message'];
          if (m is Map && m['usage'] is Map) {
            final u = m['usage'] as Map;
            prompt = _int(u['input_tokens']);
            completion = _int(u['output_tokens']);
            cached = _int(u['cache_read_input_tokens']);
          }
        case 'content_block_start':
          final i = _int(j['index']) ?? 0;
          final b = j['content_block'];
          if (b is Map<String, dynamic>) {
            blocks[i] = Map<String, dynamic>.from(b);
            if (b['type'] == 'tool_use') jsonBuf[i] = StringBuffer();
          }
        case 'content_block_delta':
          final i = _int(j['index']) ?? 0;
          final d = j['delta'];
          final b = blocks[i];
          if (d is! Map || b == null) break;
          switch (d['type']) {
            case 'text_delta':
              final t = d['text'] as String? ?? '';
              if (t.isNotEmpty) {
                b['text'] = '${b['text'] ?? ''}$t';
                text.write(t);
                yield AiToolTextDelta(t);
              }
            case 'input_json_delta':
              jsonBuf[i]?.write(d['partial_json'] ?? '');
            case 'thinking_delta':
              b['thinking'] = '${b['thinking'] ?? ''}${d['thinking'] ?? ''}';
            case 'signature_delta':
              b['signature'] = '${b['signature'] ?? ''}${d['signature'] ?? ''}';
          }
        case 'content_block_stop':
          final i = _int(j['index']) ?? 0;
          final buf = jsonBuf[i];
          if (buf != null && blocks[i] != null) {
            try {
              blocks[i]!['input'] =
                  buf.isEmpty ? <String, dynamic>{} : jsonDecode(buf.toString());
            } catch (_) {
              blocks[i]!['input'] = <String, dynamic>{};
              blocks[i]!['_raw_input'] = buf.toString();
            }
          }
        case 'message_delta':
          final d = j['delta'];
          if (d is Map && d['stop_reason'] is String) {
            stop = d['stop_reason'] as String;
          }
          final u = j['usage'];
          if (u is Map) {
            completion = _int(u['output_tokens']) ?? completion;
            prompt = _int(u['input_tokens']) ?? prompt;
          }
        case 'error':
          final err = j['error'];
          final msg = err is Map ? (err['message'] ?? '$err') : '$err';
          throw AiToolInterruptedException('$msg', partialText: text.toString());
      }
    }
    if (!finished) {
      throw AiToolInterruptedException('连接在回答结束前断开了', partialText: text.toString());
    }
    if (prompt != null || completion != null) {
      yield AiToolUsage(
        promptTokens: prompt,
        responseTokens: completion,
        cachedTokens: cached,
      );
    }
    final order = blocks.keys.toList()..sort();
    final content = <Map<String, dynamic>>[];
    final calls = <AiToolCall>[];
    for (final i in order) {
      final b = Map<String, dynamic>.from(blocks[i]!);
      final raw = b.remove('_raw_input') as String?;
      if (b['type'] == 'tool_use') {
        calls.add(AiToolCall(
          id: b['id'] as String? ?? 'toolu_$i',
          name: b['name'] as String? ?? '',
          argumentsJson: raw ?? jsonEncode(b['input'] ?? const {}),
        ));
      }
      content.add(b);
    }
    yield AiToolTurnDone(
      AiAssistantTurn(
        text: text.toString(),
        toolCalls: calls,
        providerState: content.isEmpty
            ? null
            : {'protocol': 'anthropic', 'content': content},
      ),
      stopReason: stop,
    );
  }

  // ───────────────────────── Gemini ─────────────────────────

  /// Gemini：地址里的查询串（`?key=…`）留到最后；用户写的 `/v1` `/v1beta`
  /// 先去掉，请求路径里自己带 `/v1beta`，不会重复。
  static ({String head, String query}) _geminiUrl(String baseUrl) {
    if (baseUrl.trim().isEmpty) {
      return (head: 'https://generativelanguage.googleapis.com', query: '');
    }
    final b = _splitBase(baseUrl, withVersion: false);
    return (
      head: b.head.replaceFirst(RegExp(r'/v1(beta)?$', caseSensitive: false), ''),
      query: b.query,
    );
  }

  /// Gemini 的 schema 类型名用大写
  static Object? _geminiSchema(Object? s) {
    if (s is Map) {
      return {
        for (final e in s.entries)
          e.key: e.key == 'type' && e.value is String
              ? (e.value as String).toUpperCase()
              : _geminiSchema(e.value),
      };
    }
    if (s is List) return [for (final v in s) _geminiSchema(v)];
    return s;
  }

  static http.Request _geminiRequest(
    String baseUrl,
    String apiKey,
    String model,
    List<AiToolTurn> turns,
    List<AiToolSpec> tools,
    String? system,
    AiToolChoice choice,
    int maxTokens,
    Future<void> abort,
  ) {
    final g = _geminiUrl(baseUrl);
    final base = g.query.isEmpty ? g.head : '${g.head}?${g.query}';
    final contents = <Map<String, Object?>>[];
    List<Map<String, Object?>>? pending;
    void flush() {
      if (pending != null) {
        contents.add({'role': 'user', 'parts': pending});
        pending = null;
      }
    }

    for (final t in turns) {
      switch (t) {
        case AiUserTurn():
          flush();
          contents.add({
            'role': 'user',
            'parts': [
              {'text': t.text},
            ],
          });
        case AiAssistantTurn():
          flush();
          final state = t.providerState;
          List<Object?> parts;
          if (state is Map &&
              state['protocol'] == 'gemini' &&
              state['parts'] is List) {
            parts = [...(state['parts'] as List)];
          } else {
            parts = [
              if (t.text.isNotEmpty) {'text': t.text},
              for (final c in t.toolCalls)
                {
                  'functionCall': {
                    'name': c.name,
                    'args': c.arguments ?? const <String, Object?>{},
                  },
                },
            ];
          }
          // 没有内容也没有签名的空 text 部件不放回（和 Anthropic 一致）
          parts.removeWhere(
            (p) =>
                p is Map &&
                p['text'] is String &&
                (p['text'] as String).isEmpty &&
                p['thoughtSignature'] == null &&
                p['functionCall'] == null,
          );
          if (parts.isEmpty) parts = [{'text': '…'}];
          contents.add({'role': 'model', 'parts': parts});
        case AiToolResultTurn():
          Object? payload;
          try {
            payload = jsonDecode(t.content);
          } catch (_) {}
          final response = payload is Map
              ? payload
              : {(t.isError ? 'error' : 'result'): t.content};
          (pending ??= []).add({
            'functionResponse': {'name': t.name, 'response': response},
          });
      }
    }
    flush();
    final body = <String, Object?>{
      'contents': contents,
      if (system != null && system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'generationConfig': {'maxOutputTokens': maxTokens},
      if (tools.isNotEmpty) ...{
        'tools': [
          {
            'functionDeclarations': [
              for (final s in tools)
                {
                  'name': s.name,
                  'description': s.description,
                  // 没有参数的工具不能带空的 properties
                  if (((s.parameters['properties'] as Map?) ?? const {})
                      .isNotEmpty)
                    'parameters': _geminiSchema(s.parameters),
                },
            ],
          },
        ],
        if (choice != AiToolChoice.unspecified)
          'toolConfig': {
            'functionCallingConfig': {
              'mode': _choiceName(choice, 'AUTO', 'ANY', 'NONE'),
            },
          },
      },
    };
    return _post(
      _join(base, '/v1beta/models/$model:streamGenerateContent', query: 'alt=sse'),
      body,
      {'x-goog-api-key': apiKey},
      abort,
    );
  }

  static Stream<AiToolEvent> _parseGemini(Stream<_Sse> events) async* {
    final text = StringBuffer();
    final parts = <Map<String, dynamic>>[];
    final calls = <AiToolCall>[];
    int? prompt, completion, cached;
    String? stop;
    var finished = false;
    await for (final e in events) {
      yield const AiToolActivity();
      final j = _json(e.data);
      if (j == null) continue;
      final err = j['error'];
      if (err != null) {
        final msg = err is Map ? (err['message'] ?? '$err') : '$err';
        throw AiToolInterruptedException('$msg', partialText: text.toString());
      }
      final u = j['usageMetadata'];
      if (u is Map) {
        prompt = _int(u['promptTokenCount']) ?? prompt;
        completion = _int(u['candidatesTokenCount']) ?? completion;
        cached = _int(u['cachedContentTokenCount']) ?? cached;
      }
      final cands = j['candidates'];
      if (cands is! List || cands.isEmpty || cands.first is! Map) continue;
      final cand = cands.first as Map;
      if (cand['finishReason'] is String) {
        stop = cand['finishReason'] as String;
        finished = true;
      }
      final content = cand['content'];
      final ps = content is Map ? content['parts'] : null;
      if (ps is! List) continue;
      for (final p in ps) {
        if (p is! Map<String, dynamic>) continue;
        parts.add(Map<String, dynamic>.from(p));
        final fc = p['functionCall'];
        if (fc is Map) {
          calls.add(AiToolCall(
            id: 'gemini_call_${calls.length}',
            name: fc['name'] as String? ?? '',
            argumentsJson: jsonEncode(fc['args'] ?? const {}),
          ));
        } else if (p['text'] is String && p['thought'] != true) {
          final t = p['text'] as String;
          if (t.isNotEmpty) {
            text.write(t);
            yield AiToolTextDelta(t);
          }
        }
      }
    }
    if (!finished) {
      throw AiToolInterruptedException('连接在回答结束前断开了', partialText: text.toString());
    }
    if (prompt != null || completion != null) {
      yield AiToolUsage(
        promptTokens: prompt,
        responseTokens: completion,
        cachedTokens: cached,
      );
    }
    yield AiToolTurnDone(
      AiAssistantTurn(
        text: text.toString(),
        toolCalls: calls,
        providerState:
            parts.isEmpty ? null : {'protocol': 'gemini', 'parts': parts},
      ),
      stopReason: calls.isNotEmpty ? 'tool_calls' : stop,
    );
  }

  // ───────────────────────── 公共 ─────────────────────────

  /// 规范化用户配置的地址：先拆出查询串，再按 ApiHostFormatter 的规则处理路径
  /// （末尾 `#` 严格使用、已有版本段不重复补），查询串原样留到最后。
  static ({String head, String query}) _splitBase(
    String baseUrl, {
    bool withVersion = true,
  }) {
    var s = baseUrl.trim();
    var strict = false;
    if (s.endsWith('#')) {
      strict = true;
      s = s.substring(0, s.length - 1);
    }
    final q = s.indexOf('?');
    var head = q < 0 ? s : s.substring(0, q);
    final query = q < 0 ? '' : s.substring(q + 1);
    while (head.endsWith('/')) {
      head = head.substring(0, head.length - 1);
    }
    if (!strict) {
      head = ApiHostFormatter.format(head, supportApiVersion: withVersion);
    }
    return (head: head, query: query);
  }

  static String _join(String base, String path, {String? query}) {
    final q = base.indexOf('?');
    final head = q < 0 ? base : base.substring(0, q);
    final own = q < 0 ? '' : base.substring(q + 1);
    final all = [own, if (query != null) query].where((e) => e.isNotEmpty).join('&');
    return '$head$path${all.isEmpty ? '' : '?$all'}';
  }

  /// 各协议实际请求的地址（测试用）
  static String urlFor(AiProviderType type, String baseUrl, String model) {
    switch (type) {
      case AiProviderType.openai:
        final b = _splitBase(baseUrl);
        return _join(b.query.isEmpty ? b.head : '${b.head}?${b.query}', '/chat/completions');
      case AiProviderType.openaiResponse:
        final b = _splitBase(baseUrl);
        return _join(b.query.isEmpty ? b.head : '${b.head}?${b.query}', '/responses');
      case AiProviderType.anthropic:
        final b = _splitBase(baseUrl);
        return _join(b.query.isEmpty ? b.head : '${b.head}?${b.query}', '/messages');
      case AiProviderType.gemini:
        final g = _geminiUrl(baseUrl);
        return _join(
          g.query.isEmpty ? g.head : '${g.head}?${g.query}',
          '/v1beta/models/$model:streamGenerateContent',
          query: 'alt=sse',
        );
    }
  }

  /// 参数原文不合法或为空时回传 `{}`（各家都要求 arguments 是合法 JSON）
  static String _safeArgs(AiToolCall c) =>
      c.argumentsJson.trim().isEmpty || c.arguments == null ? '{}' : c.argumentsJson;

  static http.Request _post(
    String url,
    Map<String, Object?> body,
    Map<String, String> headers,
    Future<void> abortTrigger,
  ) {
    final req = http.AbortableRequest('POST', Uri.parse(url), abortTrigger: abortTrigger);
    req.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      ...headers,
    });
    req.body = jsonEncode(body);
    return req;
  }
}
