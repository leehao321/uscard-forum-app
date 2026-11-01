import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/models/mcp_server_config.dart';
import 'package:ai_model_manager/services/mcp_client_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 审查第 9 批（协议）：会话失效重建、并发初始化合并、307/308、响应体上限、通知不读响应、超时标记。

const _server = McpServerConfig(id: 's1', name: '示例', url: 'https://mcp.example.com/mcp');

class _Req {
  _Req(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  Object? get id => body['id'];
}

typedef _Reply = Future<http.StreamedResponse> Function(_Req r);

http.StreamedResponse _json(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        headers: {'content-type': 'application/json', ...headers});

Map<String, dynamic> _ok(Object? id, Map<String, dynamic> r) => {'jsonrpc': '2.0', 'id': id, 'result': r};

class _Fake {
  _Fake({this.onMethod = const {}, this.sessionId = 'sess-1'});

  final Map<String, _Reply> onMethod;
  final String? sessionId;
  final requests = <_Req>[];
  List<String> get methods => [for (final r in requests) r.method];

  McpClientService get service => build();

  McpClientService build({Duration call = const Duration(seconds: 30)}) => McpClientService(
    callTimeout: call,
    clientFactory: () => MockClient.streaming((req, body) async {
      final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      final r = _Req('${j['method']}', req.url, req.headers, j);
      requests.add(r);
      final custom = onMethod[r.method];
      if (custom != null) return custom(r);
      switch (r.method) {
        case 'initialize':
          return _json(_ok(r.id, {'protocolVersion': '2025-06-18'}), headers: {if (sessionId != null) 'mcp-session-id': sessionId!});
        case 'notifications/initialized':
          return http.StreamedResponse(const Stream.empty(), 202);
        default:
          return _json(_ok(r.id, {'content': [{'type': 'text', 'text': '好'}]}));
      }
    }),
  );
}

void main() {
  test('带着会话 id 的请求被 400 拒绝：丢掉会话、重新初始化后重试一次', () async {
    var calls = 0;
    final fake = _Fake(onMethod: {
      'tools/call': (r) async {
        calls++;
        if (calls == 1) return _json({'error': 'bad session'}, status: 400);
        return _json(_ok(r.id, {'content': [{'type': 'text', 'text': '恢复了'}]}));
      },
    });
    final r = await fake.service.callTool(_server, const McpSecrets(), 'a', {});
    expect(r.text, '恢复了');
    expect(fake.methods.where((m) => m == 'initialize').length, 2);
  });

  test('没有会话 id 时的 400 不重试（那是参数错误，不是会话问题）', () async {
    final fake = _Fake(sessionId: null, onMethod: {'tools/call': (r) async => _json({'error': 'bad args'}, status: 400)});
    await expectLater(
      fake.service.callTool(_server, const McpSecrets(), 'a', {}),
      throwsA(isA<McpException>().having((e) => e.statusCode, 'status', 400)),
    );
    expect(fake.methods.where((m) => m == 'tools/call').length, 1);
  });

  test('并发要会话：同一个服务只初始化一次', () async {
    final gate = Completer<void>();
    final fake = _Fake(onMethod: {
      'initialize': (r) async {
        await gate.future;
        return _json(_ok(r.id, {'protocolVersion': '2025-06-18'}), headers: {'mcp-session-id': 'sess-1'});
      },
    });
    final service = fake.service;
    final a = service.callTool(_server, const McpSecrets(), 'a', {});
    final b = service.callTool(_server, const McpSecrets(), 'b', {});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.complete();
    await Future.wait([a, b]);
    expect(fake.methods.where((m) => m == 'initialize').length, 1);
  });

  test('同源 307 / 308：手动跟随一次（还是 POST，请求体不变）；跨域不跟随', () async {
    for (final status in [307, 308]) {
      var hits = 0;
      final fake = _Fake(onMethod: {
        'tools/call': (r) async {
          if (r.url.path == '/mcp') {
            return http.StreamedResponse(const Stream.empty(), status, headers: {'location': '/moved/mcp'});
          }
          hits++;
          return _json(_ok(r.id, {'content': [{'type': 'text', 'text': '到了新地址'}]}));
        },
      });
      final r = await fake.service.callTool(_server, const McpSecrets(), 'a', {'q': 1});
      expect(r.text, '到了新地址');
      expect(hits, 1);
      expect(fake.requests.last.url.path, '/moved/mcp');
      expect(fake.requests.last.body['params'], {'name': 'a', 'arguments': {'q': 1}});
    }
    final cross = _Fake(onMethod: {
      'tools/call': (r) async => http.StreamedResponse(const Stream.empty(), 307, headers: {'location': 'https://evil.example/mcp'}),
    });
    await expectLater(
      cross.service.callTool(_server, const McpSecrets(), 'a', {}),
      throwsA(isA<McpException>().having((e) => e.message, 'message', contains('重定向'))),
    );
    expect(cross.requests.any((r) => r.url.host == 'evil.example'), isFalse);
  });

  test('notifications/initialized 的响应直接取消，不读（响应体很大也不影响）', () async {
    var cancelled = false;
    final fake = _Fake(onMethod: {
      'notifications/initialized': (r) async {
        final c = StreamController<List<int>>(onCancel: () => cancelled = true);
        c.add(utf8.encode('x' * 100));
        return http.StreamedResponse(c.stream, 202);
      },
    });
    await fake.service.callTool(_server, const McpSecrets(), 'a', {});
    expect(cancelled, isTrue);
  });

  test('响应体超过 2 MB：报错，不继续读（JSON 和 SSE 都一样）', () async {
    final big = 'x' * (McpClientService.maxBodyBytes + 10);
    final json = _Fake(onMethod: {
      'tools/call': (r) async => http.StreamedResponse(Stream.value(utf8.encode(big)), 200, headers: {'content-type': 'application/json'}),
    });
    await expectLater(
      json.service.callTool(_server, const McpSecrets(), 'a', {}),
      throwsA(isA<McpException>().having((e) => e.message, 'message', contains('2 MB'))),
    );
    final sse = _Fake(onMethod: {
      'tools/call': (r) async => http.StreamedResponse(
        Stream.value(utf8.encode('data: $big\n\n')),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    });
    await expectLater(
      sse.service.callTool(_server, const McpSecrets(), 'a', {}),
      throwsA(isA<McpException>().having((e) => e.message, 'message', contains('2 MB'))),
    );
  });

  test('超时的异常带 timedOut 标记（桥据此在本题里不再调用这个服务）', () async {
    final never = Completer<http.StreamedResponse>();
    final fake = _Fake(onMethod: {'tools/call': (r) => never.future});
    await expectLater(
      fake.build(call: const Duration(milliseconds: 80)).callTool(_server, const McpSecrets(), 'a', {}),
      throwsA(isA<McpException>().having((e) => e.timedOut, 'timedOut', isTrue)),
    );
  });

  test('McpToolInfo.fromJson 对不是 bool / 不是字符串的字段容错，不抛错', () {
    final t = McpToolInfo.fromJson({
      'name': 'x',
      'description': 123,
      'title': ['不是字符串'],
      'annotations': {'readOnlyHint': 'yes', 'destructiveHint': 1, 'title': 5},
      'inputSchema': 'not a map',
    });
    expect(t.name, 'x');
    expect(t.description, '');
    expect(t.title, isNull);
    expect(t.readOnlyHint, isNull);
    expect(t.destructiveHint, isNull);
    expect(t.defaultEnabled, isFalse);
    expect(t.inputSchema['type'], 'object');
  });

  test('工具说明（含 schema 里嵌套的 description）截到 1000 字', () {
    final long = '长' * 5000;
    final t = McpToolInfo.fromJson({
      'name': 'x',
      'description': long,
      'inputSchema': {
        'type': 'object',
        'properties': {
          'q': {'type': 'string', 'description': long},
          'obj': {
            'type': 'object',
            'properties': {
              'inner': {'type': 'string', 'description': long},
            },
          },
        },
      },
    });
    expect(t.description.length, lessThanOrEqualTo(McpToolInfo.maxDescriptionChars + 1));
    final props = t.inputSchema['properties']! as Map;
    expect(((props['q'] as Map)['description'] as String).length, lessThanOrEqualTo(1001));
    final inner = (((props['obj'] as Map)['properties'] as Map)['inner'] as Map)['description'] as String;
    expect(inner.length, lessThanOrEqualTo(1001));
    // 参数名叫 description 的不被当成关键字截断
    final t2 = McpToolInfo.fromJson({
      'name': 'y',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'description': {'type': 'string'},
        },
      },
    });
    expect(((t2.inputSchema['properties']! as Map)['description'] as Map)['type'], 'string');
  });
}
