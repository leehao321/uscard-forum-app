import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mcp_server_config.dart';

/// 远程 MCP 请求出错：[message] 是给用户看的可读原因。
class McpException implements Exception {
  const McpException(this.message, {this.statusCode, this.rpcCode, this.cancelled = false});

  final String message;
  final int? statusCode;

  /// JSON-RPC 错误码
  final int? rpcCode;

  /// 是被取消的（不是真的失败）
  final bool cancelled;

  @override
  String toString() => message;
}

/// 一次工具调用的结果（已转成纯文本）
class McpCallResult {
  const McpCallResult({required this.text, this.isError = false});

  final String text;

  /// 服务端返回 `isError: true`：工具自己报告执行失败
  final bool isError;
}

class _Session {
  String? id;
  String protocol = McpClientService.protocolVersion;
}

/// 远程 MCP 客户端，只支持 Streamable HTTP 传输
/// （POST，响应是 JSON 或 SSE 都能解析；旧版 HTTP+SSE 传输不支持）。
///
/// 流程：`initialize` → `notifications/initialized` → `tools/list`（含分页）→ `tools/call`。
/// 网络客户端由调用方注入，每个请求一个独立的 client，取消时立即断开。
class McpClientService {
  McpClientService({
    http.Client Function()? clientFactory,
    this.initTimeout = const Duration(seconds: 15),
    this.callTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  static const protocolVersion = '2025-06-18';

  final http.Client Function() _clientFactory;

  /// 初始化和列工具的超时
  final Duration initTimeout;

  /// 调用工具的超时
  final Duration callTimeout;

  /// 服务 id → 会话（`Mcp-Session-Id` 和协商好的协议版本）
  final Map<String, _Session> _sessions = {};
  int _nextId = 1;

  /// 忘掉某个服务的会话（配置改过后调用）
  void forget(String serverId) => _sessions.remove(serverId);

  /// 拉取全部工具（含分页 `nextCursor`）
  Future<List<McpToolInfo>> listTools(
    McpServerConfig server,
    McpSecrets secrets, {
    Future<void>? abort,
  }) async {
    final out = <McpToolInfo>[];
    String? cursor;
    for (var page = 0; page < 50; page++) {
      final result = await _request(
        server,
        secrets,
        'tools/list',
        {if (cursor != null) 'cursor': cursor},
        timeout: initTimeout,
        abort: abort,
      );
      final tools = result['tools'];
      if (tools is List) {
        for (final t in tools) {
          if (t is Map && t['name'] is String) {
            out.add(McpToolInfo.fromJson(Map<String, dynamic>.from(t)));
          }
        }
      }
      final next = result['nextCursor'];
      if (next is! String || next.isEmpty) break;
      cursor = next;
    }
    return out;
  }

  /// 调用一个工具
  Future<McpCallResult> callTool(
    McpServerConfig server,
    McpSecrets secrets,
    String name,
    Map<String, Object?> arguments, {
    Future<void>? abort,
  }) async {
    final result = await _request(
      server,
      secrets,
      'tools/call',
      {'name': name, 'arguments': arguments},
      timeout: callTimeout,
      abort: abort,
    );
    return McpCallResult(
      text: _contentText(result),
      isError: result['isError'] == true,
    );
  }

  // ───────────────────────── 内部 ─────────────────────────

  static String _contentText(Map<String, dynamic> result) {
    final parts = <String>[];
    final content = result['content'];
    if (content is List) {
      for (final c in content) {
        if (c is! Map) continue;
        switch (c['type']) {
          case 'text':
            parts.add('${c['text'] ?? ''}');
          case 'image':
            parts.add('[图片]');
          case 'audio':
            parts.add('[音频]');
          case 'resource':
            final r = c['resource'];
            parts.add(r is Map && r['text'] is String ? r['text'] as String : '[资源 ${r is Map ? r['uri'] ?? '' : ''}]');
          case 'resource_link':
            parts.add('[链接 ${c['uri'] ?? ''}]');
        }
      }
    }
    var text = parts.join('\n').trim();
    if (text.isEmpty && result['structuredContent'] != null) {
      text = jsonEncode(result['structuredContent']);
    }
    return text;
  }

  /// 发一个带 id 的请求（必要时先初始化会话）；会话过期（404）自动重新初始化重试一次
  Future<Map<String, dynamic>> _request(
    McpServerConfig server,
    McpSecrets secrets,
    String method,
    Map<String, Object?> params, {
    required Duration timeout,
    Future<void>? abort,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final session = await _ensureSession(server, secrets, abort);
        return await _rpc(server, secrets, session, method, params, timeout: timeout, abort: abort);
      } on McpException catch (e) {
        if (e.statusCode == 404 && attempt == 0 && _sessions[server.id]?.id != null) {
          _sessions.remove(server.id);
          continue;
        }
        rethrow;
      }
    }
    throw const McpException('MCP 会话无法建立');
  }

  Future<_Session> _ensureSession(
    McpServerConfig server,
    McpSecrets secrets,
    Future<void>? abort,
  ) async {
    final known = _sessions[server.id];
    if (known != null) return known;
    final session = _Session();
    final result = await _rpc(
      server,
      secrets,
      session,
      'initialize',
      {
        'protocolVersion': protocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'fluxdo', 'version': '1.0'},
      },
      timeout: initTimeout,
      abort: abort,
      isInit: true,
    );
    final negotiated = result['protocolVersion'];
    if (negotiated is String && negotiated.isNotEmpty) session.protocol = negotiated;
    await _notify(server, secrets, session, 'notifications/initialized', abort: abort);
    _sessions[server.id] = session;
    return session;
  }

  Map<String, String> _headers(McpSecrets secrets, _Session session, {required bool isInit}) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    // 自定义请求头先放，下面的协议头和鉴权头不被它覆盖
    ...secrets.headers,
    if (secrets.bearerToken.isNotEmpty) 'Authorization': 'Bearer ${secrets.bearerToken}',
    if (session.id != null) 'Mcp-Session-Id': session.id!,
    if (!isInit) 'MCP-Protocol-Version': session.protocol,
  };

  Future<void> _notify(
    McpServerConfig server,
    McpSecrets secrets,
    _Session session,
    String method, {
    Future<void>? abort,
  }) async {
    await _post(
      server,
      secrets,
      session,
      {'jsonrpc': '2.0', 'method': method},
      expectId: null,
      timeout: initTimeout,
      abort: abort,
      isInit: false,
    );
  }

  Future<Map<String, dynamic>> _rpc(
    McpServerConfig server,
    McpSecrets secrets,
    _Session session,
    String method,
    Map<String, Object?> params, {
    required Duration timeout,
    Future<void>? abort,
    bool isInit = false,
  }) async {
    final id = _nextId++;
    final msg = await _post(
      server,
      secrets,
      session,
      {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
      expectId: id,
      timeout: timeout,
      abort: abort,
      isInit: isInit,
    );
    if (msg == null) throw const McpException('服务没有返回结果');
    final error = msg['error'];
    if (error is Map) {
      throw McpException(
        '${error['message'] ?? 'MCP 服务返回错误'}',
        rpcCode: error['code'] is int ? error['code'] as int : null,
      );
    }
    final result = msg['result'];
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  /// POST 一条 JSON-RPC 消息。[expectId] 为空是通知（不等响应体）；
  /// 否则读 JSON 或 SSE，按 JSON-RPC id 匹配出对应的那一条。
  Future<Map<String, dynamic>?> _post(
    McpServerConfig server,
    McpSecrets secrets,
    _Session session,
    Map<String, Object?> body, {
    required int? expectId,
    required Duration timeout,
    required bool isInit,
    Future<void>? abort,
  }) async {
    final uri = Uri.tryParse(server.url.trim());
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
      throw const McpException('服务地址不是有效的 http(s) 地址');
    }
    // 取消（调用方）和超时共用一个触发器：触发后请求立即断开
    final trigger = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!trigger.isCompleted) trigger.complete();
    });
    abort?.then<void>((_) {
      if (!trigger.isCompleted) trigger.complete();
    });
    // 不依赖传输层认不认 abortTrigger：触发后等待中的 await 一律立即抛出
    final aborted = trigger.future.then<Never>((_) => throw http.RequestAbortedException(uri));
    aborted.ignore();
    Future<T> guard<T>(Future<T> f) {
      f.ignore();
      return Future.any([f, aborted]);
    }

    final client = _clientFactory();
    try {
      final req = http.AbortableRequest('POST', uri, abortTrigger: trigger.future)
        ..headers.addAll(_headers(secrets, session, isInit: isInit))
        ..body = jsonEncode(body);
      final resp = await guard(client.send(req));
      final sid = resp.headers['mcp-session-id'];
      if (sid != null && sid.isNotEmpty) session.id = sid;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = await guard(resp.stream.bytesToString());
        throw _httpError(resp.statusCode, text);
      }
      if (expectId == null) {
        await guard(resp.stream.drain<void>());
        return null;
      }
      final type = (resp.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('text/event-stream')) {
        return await guard(_readSse(resp.stream, expectId));
      }
      final text = await guard(resp.stream.bytesToString());
      return _pick(text, expectId);
    } on http.RequestAbortedException {
      if (timedOut) throw McpException('请求超时（${timeout.inSeconds} 秒）');
      throw const McpException('已取消', cancelled: true);
    } on http.ClientException catch (e) {
      if (timedOut) throw McpException('请求超时（${timeout.inSeconds} 秒）');
      throw McpException('连不上 MCP 服务：${e.message}');
    } finally {
      timer.cancel();
      client.close();
    }
  }

  /// 从 JSON 响应体里取 id 匹配的那条（可能是单个对象，也可能是批量数组）
  static Map<String, dynamic> _pick(String text, int id) {
    Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw McpException('服务返回的不是 JSON：${_cut(text)}');
    }
    final items = j is List ? j : [j];
    for (final m in items) {
      if (m is Map && m['id'] == id) return Map<String, dynamic>.from(m);
    }
    throw const McpException('服务的响应里没有对应的结果');
  }

  /// 读 SSE，遇到 id 匹配的消息就返回（不再读后面的）
  static Future<Map<String, dynamic>> _readSse(Stream<List<int>> bytes, int id) async {
    final data = <String>[];
    Map<String, dynamic>? found;

    Map<String, dynamic>? flush() {
      if (data.isEmpty) return null;
      final payload = data.join('\n');
      data.clear();
      try {
        final j = jsonDecode(payload);
        final items = j is List ? j : [j];
        for (final m in items) {
          if (m is Map && m['id'] == id && (m.containsKey('result') || m.containsKey('error'))) {
            return Map<String, dynamic>.from(m);
          }
        }
      } catch (_) {}
      return null;
    }

    await for (final line in bytes.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        found = flush();
        if (found != null) return found;
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    found = flush();
    if (found != null) return found;
    throw const McpException('服务的响应在给出结果之前就结束了');
  }

  static McpException _httpError(int status, String body) {
    var detail = '';
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        if (e is Map && e['message'] is String) detail = e['message'] as String;
        if (detail.isEmpty && e is String) detail = e;
        if (detail.isEmpty && j['message'] is String) detail = j['message'] as String;
      }
    } catch (_) {}
    if (detail.isEmpty) detail = _cut(body);
    final base = switch (status) {
      401 => '认证失败（401），请检查 Token',
      403 => '没有权限（403）',
      404 => '地址或会话无效（404）',
      429 => '请求太频繁（429）',
      >= 500 => 'MCP 服务出错（$status）',
      _ => '请求被拒绝（$status）',
    };
    return McpException(detail.isEmpty ? base : '$base：$detail', statusCode: status);
  }

  static String _cut(String s) {
    final t = s.trim();
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }
}
