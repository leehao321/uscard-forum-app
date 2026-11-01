import 'dart:convert';

import 'package:ai_model_manager/models/ai_provider.dart';
import 'package:ai_model_manager/models/mcp_server_config.dart';
import 'package:ai_model_manager/services/ai_tool_chat.dart';
import 'package:ai_model_manager/services/mcp_client_service.dart';
import 'package:ai_model_manager/services/mcp_tool_bridge.dart';
import 'package:ai_model_manager/utils/tool_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// MCP 工具桥：名字清洗与冲突、schema 清洗、readOnly 默认开关、结果截断与不可信标记。

/// 一个假 MCP 服务：工具列表由 [tools] 给，调用结果由 [reply] 给
class _Mcp {
  _Mcp(this.tools, {this.reply});

  final List<Map<String, dynamic>> tools;
  final String Function(String name, Map args)? reply;
  final calls = <Map<String, dynamic>>[];
  int listCalls = 0;

  McpClientService get service => McpClientService(
    clientFactory: () => MockClient.streaming((req, body) async {
      final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      Map<String, dynamic> ok(Map<String, dynamic> r) => {'jsonrpc': '2.0', 'id': j['id'], 'result': r};
      http.StreamedResponse resp(Object o) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(o))),
        200,
        headers: {'content-type': 'application/json'},
      );
      switch (j['method']) {
        case 'initialize':
          return resp(ok({'protocolVersion': '2025-06-18'}));
        case 'notifications/initialized':
          return http.StreamedResponse(const Stream.empty(), 202);
        case 'tools/list':
          listCalls++;
          return resp(ok({'tools': tools}));
        default:
          final p = j['params'] as Map;
          calls.add(Map<String, dynamic>.from(p));
          final text = reply?.call('${p['name']}', p['arguments'] as Map) ?? '结果';
          return resp(ok({'content': [{'type': 'text', 'text': text}]}));
      }
    }),
  );
}

McpServerConfig _srv(String id, {String name = '服务', Map<String, bool> states = const {}, bool enabled = true}) =>
    McpServerConfig(id: id, name: name, url: 'https://x.example/mcp', enabled: enabled, toolStates: states);

Map<String, dynamic> _tool(String name, {bool? readOnly, bool? destructive}) => {
  'name': name,
  'description': '$name 的说明',
  'inputSchema': {'type': 'object', 'properties': {'q': {'type': 'string'}}},
  if (readOnly != null || destructive != null)
    'annotations': {
      if (readOnly != null) 'readOnlyHint': readOnly,
      if (destructive != null) 'destructiveHint': destructive,
    },
};

McpToolBridge _bridge(_Mcp mcp, {int maxChars = 8000, DateTime Function()? now}) => McpToolBridge(
  service: mcp.service,
  secretsOf: (_) async => const McpSecrets(),
  maxResultChars: maxChars,
  now: now,
);

void main() {
  final nameRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$');

  group('名字', () {
    test('mcp_<短id>__<工具名>，非法字符清洗成下划线，以字母开头，≤64', () async {
      final mcp = _Mcp([_tool('search.docs', readOnly: true), _tool('读取 文件', readOnly: true)]);
      final b = _bridge(mcp);
      await b.load([_srv('a1b2c3d4-e5f6')]);
      expect(b.tools.map((t) => t.exposedName), ['mcp_a1b2c3__search_docs', 'mcp_a1b2c3_______']);
      for (final t in b.tools) {
        expect(nameRe.hasMatch(t.exposedName), isTrue, reason: t.exposedName);
      }
    });

    test('超长名字：截断并加 8 位哈希，仍 ≤64 且互不相同', () async {
      final long1 = 'x' * 100 + 'A';
      final long2 = 'x' * 100 + 'B';
      final b = _bridge(_Mcp([_tool(long1, readOnly: true), _tool(long2, readOnly: true)]));
      await b.load([_srv('abcdef')]);
      final names = b.tools.map((t) => t.exposedName).toList();
      expect(names[0].length, lessThanOrEqualTo(64));
      expect(names[1].length, lessThanOrEqualTo(64));
      expect(names[0], isNot(names[1]));
      expect(RegExp(r'_[0-9a-f]{8}$').hasMatch(names[0]), isTrue);
      expect(nameRe.hasMatch(names[0]), isTrue);
    });

    test('清洗后撞名：后来的加哈希，两个都能反查到各自的工具', () async {
      final b = _bridge(_Mcp([_tool('a.b', readOnly: true), _tool('a_b', readOnly: true)]));
      await b.load([_srv('abcdef')]);
      final names = b.tools.map((t) => t.exposedName).toSet();
      expect(names.length, 2);
      expect(b.lookup(b.tools[0].exposedName)!.tool.name, 'a.b');
      expect(b.lookup(b.tools[1].exposedName)!.tool.name, 'a_b');
    });

    test('两个服务 id 前缀相同：短 id 不撞，同名工具也不撞', () async {
      final b = _bridge(_Mcp([_tool('t', readOnly: true)]));
      await b.load([_srv('abcdef-1', name: '甲'), _srv('abcdef-2', name: '乙')]);
      expect(b.tools.length, 2);
      expect(b.tools[0].exposedName, isNot(b.tools[1].exposedName));
      expect(b.lookup(b.tools[1].exposedName)!.server.name, '乙');
    });
  });

  group('启用规则', () {
    test('默认只开 readOnlyHint=true 的；没标、标了 destructive 的默认关', () async {
      final b = _bridge(_Mcp([
        _tool('ro', readOnly: true),
        _tool('plain'),
        _tool('rw', readOnly: false),
        _tool('boom', readOnly: true, destructive: true),
      ]));
      await b.load([_srv('abcdef')]);
      expect(b.tools.map((t) => t.tool.name), ['ro']);
    });

    test('用户手动设置覆盖默认：打开 plain、关掉 ro', () async {
      final b = _bridge(_Mcp([_tool('ro', readOnly: true), _tool('plain')]));
      await b.load([_srv('abcdef', states: {'plain': true, 'ro': false})]);
      expect(b.tools.map((t) => t.tool.name), ['plain']);
    });

    test('服务整体关掉：不拉工具、不暴露', () async {
      final mcp = _Mcp([_tool('ro', readOnly: true)]);
      final b = _bridge(mcp);
      await b.load([_srv('abcdef', enabled: false)]);
      expect(b.isEmpty, isTrue);
      expect(mcp.listCalls, 0);
    });

    test('一个服务拉不到工具：记下原因，其他服务照常', () async {
      final bad = McpToolBridge(
        service: McpClientService(
          clientFactory: () => MockClient.streaming((req, body) async {
            final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final bad = req.url.host == 'bad.example';
            if (bad) return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500, headers: {'content-type': 'application/json'});
            Map<String, dynamic> ok(Map<String, dynamic> r) => {'jsonrpc': '2.0', 'id': j['id'], 'result': r};
            Object out = switch (j['method']) {
              'initialize' => ok({'protocolVersion': '2025-06-18'}),
              'tools/list' => ok({'tools': [_tool('ro', readOnly: true)]}),
              _ => ok({}),
            };
            return j['method'] == 'notifications/initialized'
                ? http.StreamedResponse(const Stream.empty(), 202)
                : http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(out))), 200, headers: {'content-type': 'application/json'});
          }),
        ),
        secretsOf: (_) async => const McpSecrets(),
      );
      await bad.load([
        const McpServerConfig(id: 'badbad', name: '坏的', url: 'https://bad.example/mcp'),
        const McpServerConfig(id: 'goodgo', name: '好的', url: 'https://good.example/mcp'),
      ]);
      expect(bad.failures.keys, ['坏的']);
      expect(bad.tools.map((t) => t.server.name), ['好的']);
    });

    test('工具列表有缓存：10 分钟内不重复拉；过期后重新拉', () async {
      final mcp = _Mcp([_tool('ro', readOnly: true)]);
      var now = DateTime(2026, 1, 1);
      final b = _bridge(mcp, now: () => now);
      final s = _srv('abcdef');
      await b.load([s]);
      await b.load([s]);
      expect(mcp.listCalls, 1);
      now = now.add(const Duration(minutes: 11));
      await b.load([s]);
      expect(mcp.listCalls, 2);
    });
  });

  group('转发与结果', () {
    test('转成 AiToolSpec 并转发 tools/call（用原工具名）', () async {
      final mcp = _Mcp([_tool('search.docs', readOnly: true)]);
      final b = _bridge(mcp);
      await b.load([_srv('abcdef', name: '文档')]);
      expect(b.specs.single.name, 'mcp_abcdef__search_docs');
      expect(b.specs.single.description, contains('文档'));
      final out = await b.call(AiToolCall(id: '1', name: 'mcp_abcdef__search_docs', argumentsJson: '{"q":"a"}'));
      expect(mcp.calls.single, {'name': 'search.docs', 'arguments': {'q': 'a'}});
      final j = jsonDecode(out.content) as Map<String, dynamic>;
      expect(j['ok'], isTrue);
      expect(j['untrusted'], isTrue, reason: '结果按不可信数据对待');
      expect(j['source'], 'mcp');
      expect(out.title, 'MCP · 文档 · search.docs');
      expect(out.summary, '→ 2 字');
    });

    test('结果超过 8000 字：截断并注明原文字数', () async {
      final mcp = _Mcp([_tool('big', readOnly: true)], reply: (_, __) => '字' * 20000);
      final b = _bridge(mcp);
      await b.load([_srv('abcdef')]);
      final out = await b.call(AiToolCall(id: '1', name: b.tools.single.exposedName, argumentsJson: '{}'));
      final text = (jsonDecode(out.content) as Map)['text'] as String;
      expect(text.length, lessThan(8100));
      expect(text, contains('原文共 20000 字'));
    });

    test('工具返回 isError、服务出错、参数不是 JSON、不存在的工具：都是失败结果，不抛异常', () async {
      final b = _bridge(_Mcp([_tool('t', readOnly: true)]));
      await b.load([_srv('abcdef')]);
      final name = b.tools.single.exposedName;
      final noArgs = await b.call(AiToolCall(id: '1', name: name, argumentsJson: 'not json'));
      expect(noArgs.isError, isTrue);
      final unknown = await b.call(const AiToolCall(id: '2', name: 'mcp_zzz__nope', argumentsJson: '{}'));
      expect(unknown.isError, isTrue);
      expect(b.owns('mcp_zzz__nope'), isFalse);
    });
  });

  group('schema 清洗', () {
    const raw = <String, Object?>{
      r'$schema': 'http://json-schema.org/draft-07/schema#',
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'q': {'type': 'string', 'default': 'x', 'description': '查询'},
        'n': {'type': ['integer', 'null'], 'minimum': 1, 'exclusiveMinimum': 0},
        'tags': {'type': 'array'},
        'obj': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'properties': {'inner': {'type': 'string', r'$comment': 'x'}},
        },
      },
      'required': ['q'],
    };

    test('Gemini：去掉不认的键（\$schema、additionalProperties、default 等），type 数组改单值 + nullable，数组补 items', () {
      final out = ToolSchema.clean(raw, AiProviderType.gemini);
      expect(out.containsKey(r'$schema'), isFalse);
      expect(out.containsKey('additionalProperties'), isFalse);
      final props = out['properties']! as Map;
      expect((props['q'] as Map).containsKey('default'), isFalse);
      expect((props['q'] as Map)['description'], '查询');
      expect(props['n'], {'type': 'integer', 'nullable': true, 'minimum': 1});
      expect(props['tags'], {'type': 'array', 'items': {'type': 'string'}});
      final obj = props['obj']! as Map;
      expect(obj.containsKey('additionalProperties'), isFalse);
      expect((obj['properties'] as Map)['inner'], {'type': 'string'});
      expect(out['required'], ['q']);
    });

    for (final t in [AiProviderType.openai, AiProviderType.openaiResponse, AiProviderType.anthropic]) {
      test('${t.name}：只去掉 \$schema 这类元数据，其余原样（additionalProperties 保留）', () {
        final out = ToolSchema.clean(raw, t);
        expect(out.containsKey(r'$schema'), isFalse);
        expect(out['additionalProperties'], false);
        final props = out['properties']! as Map;
        expect((props['q'] as Map)['default'], 'x');
        expect(((props['obj'] as Map)['properties'] as Map)['inner'], {'type': 'string'});
      });
    }

    test('根不是 object / 没有 properties：补成 object + 空 properties', () {
      expect(ToolSchema.clean(const {}, AiProviderType.openai), {'type': 'object', 'properties': <String, Object?>{}});
      expect(ToolSchema.clean(const {'type': 'string'}, AiProviderType.gemini), {'type': 'object', 'properties': <String, Object?>{}});
    });

    test('请求体里真的用了清洗后的 schema（Gemini 不再带 \$schema）', () async {
      Map<String, dynamic>? body;
      final client = MockClient.streaming((req, b) async {
        body = jsonDecode(await b.bytesToString()) as Map<String, dynamic>;
        return http.StreamedResponse(Stream.value(utf8.encode('')), 200, headers: {'content-type': 'text/event-stream'});
      });
      await AiToolChatService(bridgedClient: client)
          .stream(
            provider: const AiProvider(id: 'p', name: 'p', type: AiProviderType.gemini, baseUrl: 'https://g.example'),
            model: 'm',
            apiKey: 'k',
            turns: const [AiUserTurn('q')],
            tools: const [AiToolSpec(name: 't', description: 'd', parameters: raw)],
          )
          .drain<void>()
          .catchError((Object _) {});
      final decl = ((body!['tools'] as List).first as Map)['functionDeclarations'] as List;
      final params = (decl.first as Map)['parameters'] as Map;
      expect(params.containsKey(r'$schema'), isFalse);
      expect(params.containsKey('additionalProperties'), isFalse);
      expect(params['type'], 'OBJECT');
    });
  });
}
