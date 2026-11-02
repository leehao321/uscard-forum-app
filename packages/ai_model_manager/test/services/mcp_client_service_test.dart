import 'dart:async';
import 'dart:convert';

import 'package:ai_model_manager/models/mcp_server_config.dart';
import 'package:ai_model_manager/services/mcp_client_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 通用远程 MCP 客户端（Streamable HTTP）。全部用 MockClient，不联网。

const _server = McpServerConfig(id: 's1', name: '示例', url: 'https://mcp.example.com/mcp');

/// 收到的一条 JSON-RPC 请求
class _Req {
  _Req(this.method, this.headers, this.body);
  final String method;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  Object? get id => body['id'];
  Map<String, dynamic> get params => (body['params'] as Map?)?.cast<String, dynamic>() ?? {};
}

typedef _Reply = Future<http.StreamedResponse> Function(_Req req);

http.StreamedResponse _json(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

http.StreamedResponse _sse(List<Object> events, {Map<String, String> headers = const {}}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(events.map((e) => 'event: message\ndata: ${jsonEncode(e)}\n\n').join())),
      200,
      headers: {'content-type': 'text/event-stream', ...headers},
    );

Map<String, dynamic> _ok(Object? id, Map<String, dynamic> result) => {'jsonrpc': '2.0', 'id': id, 'result': result};

/// 一个按方法路由的假服务；[onMethod] 覆盖默认回复
class _Fake {
  _Fake({this.onMethod = const {}, this.sessionId});

  final Map<String, _Reply> onMethod;
  final String? sessionId;
  final requests = <_Req>[];

  List<String> get methods => [for (final r in requests) r.method];

  McpClientService service({Duration init = const Duration(seconds: 15), Duration call = const Duration(seconds: 30)}) =>
      McpClientService(
        initTimeout: init,
        callTimeout: call,
        clientFactory: () => MockClient.streaming((req, body) async {
          final text = await body.bytesToString();
          final json = jsonDecode(text) as Map<String, dynamic>;
          final r = _Req('${json['method']}', req.headers, json);
          requests.add(r);
          final custom = onMethod[r.method];
          if (custom != null) return custom(r);
          switch (r.method) {
            case 'initialize':
              return _json(
                _ok(r.id, {'protocolVersion': '2025-03-26', 'capabilities': {}, 'serverInfo': {'name': 'x'}}),
                headers: {if (sessionId != null) 'mcp-session-id': sessionId!},
              );
            case 'notifications/initialized':
              return http.StreamedResponse(const Stream.empty(), 202);
            case 'tools/list':
              return _json(_ok(r.id, {
                'tools': [
                  {'name': 'a', 'inputSchema': {'type': 'object'}},
                ],
              }));
            default:
              return _json(_ok(r.id, {
                'content': [
                  {'type': 'text', 'text': '结果'},
                ],
              }));
          }
        }),
      );
}

void main() {
  group('握手与请求头', () {
    test('initialize → notifications/initialized → tools/list；头部和协议版本', () async {
      final fake = _Fake();
      final tools = await fake.service().listTools(
        _server,
        const McpSecrets(bearerToken: 'tok', headers: {'X-Api': 'v'}),
      );
      expect(fake.methods, ['initialize', 'notifications/initialized', 'tools/list']);
      expect(tools.single.name, 'a');
      for (final r in fake.requests) {
        expect(r.headers['Accept'], 'application/json, text/event-stream');
        expect(r.headers['Content-Type'], contains('application/json'));
        expect(r.headers['Authorization'], 'Bearer tok');
        expect(r.headers['X-Api'], 'v');
        expect(r.body['jsonrpc'], '2.0');
      }
      expect(fake.requests[0].headers.containsKey('MCP-Protocol-Version'), isFalse, reason: '初始化请求不带协议版本头');
      expect(fake.requests[0].params['protocolVersion'], McpClientService.protocolVersion);
      expect(fake.requests[1].id, isNull, reason: '通知没有 id');
      expect(fake.requests[2].headers['MCP-Protocol-Version'], '2025-03-26', reason: '用服务端协商的版本');
    });

    test('自定义头不能覆盖鉴权头和协议头', () async {
      final fake = _Fake();
      await fake.service().listTools(
        _server,
        const McpSecrets(bearerToken: 'real', headers: {'Authorization': 'Bearer fake', 'MCP-Protocol-Version': 'x'}),
      );
      expect(fake.requests.last.headers['Authorization'], 'Bearer real');
      expect(fake.requests.last.headers['MCP-Protocol-Version'], '2025-03-26');
    });

    test('Mcp-Session-Id：初始化后每个请求都带；同一服务不重复初始化', () async {
      final fake = _Fake(sessionId: 'sess-1');
      final service = fake.service();
      await service.listTools(_server, const McpSecrets());
      await service.callTool(_server, const McpSecrets(), 'a', {});
      expect(fake.methods.where((m) => m == 'initialize').length, 1);
      expect(fake.requests[0].headers.containsKey('Mcp-Session-Id'), isFalse);
      for (final r in fake.requests.skip(1)) {
        expect(r.headers['Mcp-Session-Id'], 'sess-1');
      }
    });

    test('会话过期（404）：重新初始化后重试一次', () async {
      var calls = 0;
      final fake = _Fake(
        sessionId: 'sess-1',
        onMethod: {
          'tools/call': (r) async {
            calls++;
            if (calls == 1) return _json({'error': 'expired'}, status: 404);
            return _json(_ok(r.id, {'content': [{'type': 'text', 'text': '好了'}]}));
          },
        },
      );
      final r = await fake.service().callTool(_server, const McpSecrets(), 'a', {});
      expect(r.text, '好了');
      expect(fake.methods.where((m) => m == 'initialize').length, 2);
    });
  });

  group('响应格式', () {
    test('SSE：按 JSON-RPC id 匹配，前面的通知和别的 id 忽略', () async {
      final fake = _Fake(
        onMethod: {
          'tools/call': (r) async => _sse([
            {'jsonrpc': '2.0', 'method': 'notifications/progress', 'params': {}},
            _ok(9999, {'content': [{'type': 'text', 'text': '别人的'}]}),
            _ok(r.id, {'content': [{'type': 'text', 'text': '我的'}]}),
          ]),
        },
      );
      final r = await fake.service().callTool(_server, const McpSecrets(), 'a', {'q': 1});
      expect(r.text, '我的');
      expect(fake.requests.last.params, {'name': 'a', 'arguments': {'q': 1}});
    });

    test('SSE 的初始化响应也能解析', () async {
      final fake = _Fake(
        onMethod: {
          'initialize': (r) async => _sse([_ok(r.id, {'protocolVersion': '2025-06-18'})]),
        },
      );
      await fake.service().listTools(_server, const McpSecrets());
      expect(fake.requests.last.headers['MCP-Protocol-Version'], '2025-06-18');
    });

    test('SSE 在给出结果前就结束：报可读错误', () async {
      final fake = _Fake(onMethod: {'tools/call': (r) async => _sse([])});
      expect(
        fake.service().callTool(_server, const McpSecrets(), 'a', {}),
        throwsA(isA<McpException>().having((e) => e.message, 'message', contains('结束'))),
      );
    });

    test('tools/list 分页：跟着 nextCursor 取完', () async {
      final fake = _Fake(
        onMethod: {
          'tools/list': (r) async {
            final cursor = r.params['cursor'];
            if (cursor == null) {
              return _json(_ok(r.id, {'tools': [{'name': 'a'}], 'nextCursor': 'c2'}));
            }
            if (cursor == 'c2') {
              return _json(_ok(r.id, {'tools': [{'name': 'b'}], 'nextCursor': 'c3'}));
            }
            return _json(_ok(r.id, {'tools': [{'name': 'c'}]}));
          },
        },
      );
      final tools = await fake.service().listTools(_server, const McpSecrets());
      expect([for (final t in tools) t.name], ['a', 'b', 'c']);
      expect(fake.methods.where((m) => m == 'tools/list').length, 3);
    });

    test('annotations：readOnlyHint / destructiveHint 解析，默认启用只看只读', () async {
      final fake = _Fake(
        onMethod: {
          'tools/list': (r) async => _json(_ok(r.id, {
            'tools': [
              {'name': 'ro', 'annotations': {'readOnlyHint': true}},
              {'name': 'none'},
              {'name': 'rw', 'annotations': {'readOnlyHint': false}},
              {'name': 'bad', 'annotations': {'readOnlyHint': true, 'destructiveHint': true}},
            ],
          })),
        },
      );
      final tools = {for (final t in await fake.service().listTools(_server, const McpSecrets())) t.name: t};
      expect(tools['ro']!.defaultEnabled, isTrue);
      expect(tools['none']!.defaultEnabled, isFalse);
      expect(tools['rw']!.defaultEnabled, isFalse);
      expect(tools['bad']!.defaultEnabled, isFalse);
      expect(tools['none']!.mayModify, isTrue);
    });

    test('调用结果转纯文本：多段文字、图片占位、structuredContent', () async {
      final fake = _Fake(
        onMethod: {
          'tools/call': (r) async => _json(_ok(r.id, {
            'content': [
              {'type': 'text', 'text': '第一段'},
              {'type': 'image', 'data': 'xx', 'mimeType': 'image/png'},
              {'type': 'text', 'text': '第二段'},
            ],
          })),
        },
      );
      expect((await fake.service().callTool(_server, const McpSecrets(), 'a', {})).text, '第一段\n[图片]\n第二段');
      final fake2 = _Fake(
        onMethod: {
          'tools/call': (r) async => _json(_ok(r.id, {'content': [], 'structuredContent': {'n': 3}})),
        },
      );
      expect((await fake2.service().callTool(_server, const McpSecrets(), 'a', {})).text, '{"n":3}');
    });
  });

  group('错误映射', () {
    test('JSON-RPC error → McpException（带错误码）', () async {
      final fake = _Fake(
        onMethod: {
          'tools/call': (r) async => _json({
            'jsonrpc': '2.0',
            'id': r.id,
            'error': {'code': -32602, 'message': '参数不对'},
          }),
        },
      );
      expect(
        fake.service().callTool(_server, const McpSecrets(), 'a', {}),
        throwsA(isA<McpException>().having((e) => e.message, 'message', '参数不对').having((e) => e.rpcCode, 'code', -32602)),
      );
    });

    test('isError: true → 结果标记失败，文字照常给出', () async {
      final fake = _Fake(
        onMethod: {
          'tools/call': (r) async => _json(_ok(r.id, {'isError': true, 'content': [{'type': 'text', 'text': '执行失败了'}]})),
        },
      );
      final r = await fake.service().callTool(_server, const McpSecrets(), 'a', {});
      expect(r.isError, isTrue);
      expect(r.text, '执行失败了');
    });

    for (final (status, expected) in [(401, '认证失败'), (403, '没有权限'), (429, '太频繁'), (502, '出错')]) {
      test('HTTP $status → 可读错误，带状态码', () async {
        final fake = _Fake(onMethod: {'initialize': (r) async => _json({'error': {'message': '细节'}}, status: status)});
        expect(
          fake.service().listTools(_server, const McpSecrets()),
          throwsA(
            isA<McpException>()
                .having((e) => e.message, 'message', allOf(contains(expected), contains('细节')))
                .having((e) => e.statusCode, 'status', status),
          ),
        );
      });
    }

    test('不是 JSON 的响应：报错并带前面一段原文', () async {
      final fake = _Fake(
        onMethod: {
          'tools/call': (r) async => http.StreamedResponse(
            Stream.value(utf8.encode('<html>oops</html>')),
            200,
            headers: {'content-type': 'text/html'},
          ),
        },
      );
      expect(
        fake.service().callTool(_server, const McpSecrets(), 'a', {}),
        throwsA(isA<McpException>().having((e) => e.message, 'message', contains('oops'))),
      );
    });

    test('地址不是 http(s)：不发请求直接报错', () async {
      final fake = _Fake();
      expect(
        fake.service().listTools(_server.copyWith(url: 'ftp://x'), const McpSecrets()),
        throwsA(isA<McpException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fake.requests, isEmpty);
    });
  });

  group('超时与取消', () {
    test('初始化超过 initTimeout：报超时', () async {
      final never = Completer<http.StreamedResponse>();
      final fake = _Fake(onMethod: {'initialize': (r) => never.future});
      expect(
        fake.service(init: const Duration(milliseconds: 80)).listTools(_server, const McpSecrets()),
        throwsA(isA<McpException>().having((e) => e.message, 'message', contains('超时'))),
      );
    });

    test('工具调用超过 callTimeout：报超时', () async {
      final never = Completer<http.StreamedResponse>();
      final fake = _Fake(onMethod: {'tools/call': (r) => never.future});
      expect(
        fake.service(call: const Duration(milliseconds: 80)).callTool(_server, const McpSecrets(), 'a', {}),
        throwsA(isA<McpException>().having((e) => e.message, 'message', contains('超时'))),
      );
    });

    test('取消：请求立即结束，标记 cancelled，之后不再发请求', () async {
      final abort = Completer<void>();
      final started = Completer<void>();
      final fake = _Fake(onMethod: {
        'tools/call': (r) {
          started.complete();
          return Completer<http.StreamedResponse>().future;
        },
      });
      final future = fake.service().callTool(_server, const McpSecrets(), 'a', {}, abort: abort.future);
      await started.future;
      abort.complete();
      await expectLater(
        future,
        throwsA(isA<McpException>().having((e) => e.cancelled, 'cancelled', isTrue)),
      );
      final sent = fake.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.requests.length, sent);
    });
  });
}
