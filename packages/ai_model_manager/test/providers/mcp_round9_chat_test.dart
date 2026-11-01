import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 审查第 9 批：公开 AI 对话的 MCP 工具循环 —— 降级（不支持工具 / tool_choice 被拒 / 首轮 400）、
// 没有正文不能标完成、超时的服务本次不再调用、销毁 / 停止的三种卡点、代号。全部 MockClient，不联网。

const _provider = AiProvider(id: 'p1', name: 'p', type: AiProviderType.openai, baseUrl: 'https://llm.example.com/v1');
const _model = AiModel(id: 'm', abilities: [ModelAbility.tool]);
const _server = McpServerConfig(id: 'srvabc123', name: '文档', url: 'https://mcp.example.com/mcp', toolStates: {'search': true});
const _tool = 'mcp_srvabc__search';

String _sse(List<Object> events) => events.map((e) => 'data: ${e is String ? e : jsonEncode(e)}\n\n').join();

String _toolCall() => _sse([
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {'index': 0, 'id': 'c1', 'type': 'function', 'function': {'name': _tool, 'arguments': '{"q":"x"}'}},
          ],
        },
        'finish_reason': null,
      },
    ],
  },
  {
    'choices': [
      {'delta': {}, 'finish_reason': 'tool_calls'},
    ],
  },
  '[DONE]',
]);

String _text(String t) => _sse([
  {
    'choices': [
      {'delta': {'content': t}, 'finish_reason': null},
    ],
  },
  {
    'choices': [
      {'delta': {}, 'finish_reason': 'stop'},
    ],
  },
  '[DONE]',
]);

/// (状态码, 正文)；正文为 null = 一直不出数据
typedef _Reply = (int, String?);

class _Llm {
  _Llm(this.script);

  final List<_Reply> script;
  final bodies = <Map<String, dynamic>>[];

  http.Client call() => MockClient.streaming((req, body) async {
    bodies.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
    final r = script[bodies.length - 1 < script.length ? bodies.length - 1 : script.length - 1];
    if (r.$2 == null) {
      return http.StreamedResponse(StreamController<List<int>>().stream, r.$1, headers: {'content-type': 'text/event-stream'});
    }
    final isSse = r.$1 == 200;
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.$2!)),
      r.$1,
      headers: {'content-type': isSse ? 'text/event-stream' : 'application/json'},
    );
  });
}

class _Mcp {
  _Mcp({this.holdList, this.holdCall, this.callTimeout = const Duration(seconds: 30)});

  final Completer<void>? holdList;
  final Completer<void>? holdCall;
  final Duration callTimeout;
  int calls = 0;

  McpToolBridge bridge() => McpToolBridge(
    secretsOf: (_) async => const McpSecrets(),
    service: McpClientService(
      callTimeout: callTimeout,
      clientFactory: () => MockClient.streaming((req, body) async {
        final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        Map<String, dynamic> ok(Map<String, dynamic> r) => {'jsonrpc': '2.0', 'id': j['id'], 'result': r};
        http.StreamedResponse resp(Object o) =>
            http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(o))), 200, headers: {'content-type': 'application/json'});
        switch (j['method']) {
          case 'initialize':
            return resp(ok({'protocolVersion': '2025-06-18'}));
          case 'notifications/initialized':
            return http.StreamedResponse(const Stream.empty(), 202);
          case 'tools/list':
            if (holdList != null) await holdList!.future;
            return resp(ok({'tools': [{'name': 'search', 'annotations': {'readOnlyHint': true}}]}));
          default:
            calls++;
            if (holdCall != null) await holdCall!.future;
            return resp(ok({'content': [{'type': 'text', 'text': '资料'}]}));
        }
      }),
    ),
  );
}

Future<void> _waitIdle(TopicAiChatNotifier n) async {
  for (var i = 0; i < 300 && n.state.isGenerating; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TopicAiChatNotifier> make(_Llm llm, _Mcp mcp) async {
    SharedPreferences.setMockInitialValues({'ai_apikey_p1': 'sk-test'});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final n = TopicAiChatNotifier(
      chatService: AiChatService(),
      storageService: AiChatStorageService(prefs),
      topicId: 1,
      requestClientFactory: llm.call,
      mcpServers: () => const [_server],
      mcpBridgeFactory: mcp.bridge,
    );
    addTearDown(() {
      try {
        n.dispose();
      } catch (_) {}
    });
    return n;
  }

  Future<void> send(TopicAiChatNotifier n) =>
      n.sendMessage('帮我查一下', ContextScope.firstPostOnly, selectedModel: (provider: _provider, model: _model));

  group('降级', () {
    test('首轮「不支持工具」：退回原来的路径（第二个请求不带 tools），正常出回答', () async {
      final llm = _Llm([
        (400, jsonEncode({'error': {'message': 'registry/model does not support tools'}})),
        (200, _text('普通路径的回答')),
      ]);
      final n = await make(llm, _Mcp());
      await send(n);
      await _waitIdle(n);
      expect(llm.bodies.length, 2);
      expect(llm.bodies[0].containsKey('tools'), isTrue);
      expect(llm.bodies[1].containsKey('tools'), isFalse, reason: '退回原路径，不带工具');
      expect(n.state.messages.last.content, contains('普通路径的回答'));
      expect(n.state.messages.last.status, MessageStatus.completed);
    });

    test('tool_choice 被拒：不带 tool_choice 重发一次，工具照常可用', () async {
      final llm = _Llm([
        (400, jsonEncode({'error': {'message': "Unsupported parameter: 'tool_choice'"}})),
        (200, _text('重发之后的回答')),
      ]);
      final n = await make(llm, _Mcp());
      await send(n);
      await _waitIdle(n);
      expect(llm.bodies.length, 2);
      expect(llm.bodies[0].containsKey('tool_choice'), isTrue);
      expect(llm.bodies[1].containsKey('tool_choice'), isFalse);
      expect(llm.bodies[1].containsKey('tools'), isTrue);
      expect(n.state.messages.last.content, contains('重发之后的回答'));
    });

    test('首轮带外部工具被 400 拒绝：去掉外部工具、走原路径重发，并在消息下面注明', () async {
      final llm = _Llm([
        (400, jsonEncode({'error': {'message': 'Invalid schema for function mcp_x: bad'}})),
        (200, _text('没有外部工具也答了')),
      ]);
      final n = await make(llm, _Mcp());
      await send(n);
      await _waitIdle(n);
      expect(llm.bodies.length, 2);
      expect(llm.bodies[1].containsKey('tools'), isFalse);
      final m = n.state.messages.last;
      expect(m.status, MessageStatus.completed);
      expect(m.content, contains('没有外部工具也答了'));
      expect(m.toolNotes, contains('外部工具的定义被服务商拒绝，这次没有使用外部工具'));
    });

    test('最后一轮只给了工具调用、没有正文：标成错误「模型没有给出回答」，不能标完成', () async {
      final llm = _Llm([(200, _toolCall())]);
      final n = await make(llm, _Mcp());
      await send(n);
      await _waitIdle(n);
      final m = n.state.messages.last;
      expect(m.status, MessageStatus.error);
      expect(m.errorMessage, '模型没有给出回答');
    });
  });

  group('超时的服务', () {
    test('本次回答里调用超时过一次的服务不再调用：第二次直接失败，不发请求', () async {
      final hang = Completer<void>();
      final mcp = _Mcp(holdCall: hang, callTimeout: const Duration(milliseconds: 100));
      final llm = _Llm([(200, _toolCall()), (200, _toolCall()), (200, _text('用已有资料回答'))]);
      final n = await make(llm, mcp);
      await send(n);
      await _waitIdle(n);
      hang.complete();
      expect(mcp.calls, 1, reason: '超时之后同一个服务没有再被调用');
      final notes = n.state.messages.last.toolNotes!;
      expect(notes.length, 2);
      expect(notes[0], contains('超时'));
      expect(notes[1], contains('不再调用'));
    });
  });

  group('销毁 / 停止的三种卡点', () {
    Future<void> stuckThenDispose(_Llm llm, _Mcp mcp, bool Function() stuck) async {
      final n = await make(llm, mcp);
      final sending = send(n);
      for (var i = 0; i < 200 && !stuck(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(stuck(), isTrue, reason: '确实卡在了这一步');
      final before = llm.bodies.length;
      n.dispose();
      await sending.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(llm.bodies.length, before, reason: '销毁之后不再发请求');
    }

    test('卡在模型这一轮', () async {
      final llm = _Llm([(200, null)]);
      await stuckThenDispose(llm, _Mcp(), () => llm.bodies.isNotEmpty);
    });

    test('卡在加载工具列表', () async {
      final hold = Completer<void>();
      final llm = _Llm([(200, _text('不该到这里'))]);
      final mcp = _Mcp(holdList: hold);
      var started = false;
      // 工具列表请求发出（initialize 之后）才算卡住：用一个短等待判断
      await stuckThenDispose(llm, mcp, () {
        started = true;
        return started;
      });
      hold.complete();
      expect(llm.bodies, isEmpty, reason: '加载还没完成就销毁，模型一次都没请求');
    });

    test('卡在 MCP 工具调用', () async {
      final hold = Completer<void>();
      final llm = _Llm([(200, _toolCall()), (200, _text('不该出现'))]);
      final mcp = _Mcp(holdCall: hold);
      await stuckThenDispose(llm, mcp, () => mcp.calls > 0);
      hold.complete();
    });
  });

  test('点停止后马上再发一条：旧的循环退出，不会碰新的这条消息', () async {
    final llm = _Llm([(200, null), (200, _text('新的回答'))]);
    final n = await make(llm, _Mcp());
    final first = send(n);
    for (var i = 0; i < 200 && llm.bodies.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    n.stopGeneration();
    await first.timeout(const Duration(seconds: 2));
    await send(n);
    await _waitIdle(n);
    final last = n.state.messages.last;
    expect(last.content, contains('新的回答'));
    expect(last.status, MessageStatus.completed);
    expect(n.state.isGenerating, isFalse);
  });
}
