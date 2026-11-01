import 'dart:convert';

import 'package:ai_model_manager/models/mcp_server_config.dart';
import 'package:ai_model_manager/providers/mcp_server_providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// MCP 服务配置：公开部分在 SharedPreferences，Token 和请求头只在安全存储里。

const _token = 'SECRET-TOKEN-123';
const _headerValue = 'SECRET-HEADER-456';

class _FailingStore implements McpSecretStore {
  @override
  Future<McpSecrets> read(String serverId) async => const McpSecrets();
  @override
  Future<void> write(String serverId, McpSecrets secrets) async => throw const McpSecretStoreException('钥匙串不可用');
  @override
  Future<void> delete(String serverId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  const secrets = McpSecrets(bearerToken: _token, headers: {'X-Key': _headerValue});

  test('Token 和请求头只在安全存储里：SharedPreferences 里整个都搜不到', () async {
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    final id = await n.add(name: '示例', url: 'https://mcp.example.com/mcp', secrets: secrets);

    // 所有 SharedPreferences 的值里都没有这两段
    final all = jsonEncode({for (final k in prefs.getKeys()) k: prefs.get(k)});
    expect(all, isNot(contains(_token)));
    expect(all, isNot(contains(_headerValue)));
    expect(all, contains('https://mcp.example.com/mcp'), reason: '公开部分在这里');

    // 安全存储里有
    final stored = await const FlutterSecureStorage().read(key: SecureMcpSecretStore.keyOf(id));
    expect(stored, contains(_token));
    expect(stored, contains(_headerValue));
    final back = await n.secretsOf(id);
    expect(back.bearerToken, _token);
    expect(back.headers, {'X-Key': _headerValue});
  });

  test('配置对象的 JSON 不含敏感部分（也就进不了任何导出）', () async {
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    await n.add(name: '示例', url: 'https://mcp.example.com/mcp', secrets: secrets);
    final json = jsonEncode(n.state.single.toJson());
    expect(json, isNot(contains(_token)));
    expect(json, isNot(contains(_headerValue)));
    expect(json, isNot(contains('token')));
    expect(json, isNot(contains('headers')));
  });

  test('重启后：列表从 SharedPreferences 恢复，凭据从安全存储取', () async {
    final store = SecureMcpSecretStore();
    final n = McpServerListNotifier(prefs, store);
    final id = await n.add(name: '示例', url: ' https://mcp.example.com/mcp ', secrets: secrets);
    await n.update(id, toolStates: {'a': true, 'b': false});
    final n2 = McpServerListNotifier(prefs, store);
    expect(n2.state.single.url, 'https://mcp.example.com/mcp', reason: '地址去掉首尾空白');
    expect(n2.state.single.toolStates, {'a': true, 'b': false});
    expect((await n2.secretsOf(id)).bearerToken, _token);
  });

  test('更新时不传 secrets：凭据保持；传空：凭据清掉', () async {
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    final id = await n.add(name: 'a', url: 'https://x.example', secrets: secrets);
    await n.update(id, name: 'b');
    expect((await n.secretsOf(id)).bearerToken, _token);
    await n.update(id, secrets: const McpSecrets());
    expect((await n.secretsOf(id)).isEmpty, isTrue);
    expect(await const FlutterSecureStorage().read(key: SecureMcpSecretStore.keyOf(id)), isNull);
  });

  test('删除服务：安全存储里的凭据一起删', () async {
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    final id = await n.add(name: 'a', url: 'https://x.example', secrets: secrets);
    await n.remove(id);
    expect(n.state, isEmpty);
    expect(await const FlutterSecureStorage().read(key: SecureMcpSecretStore.keyOf(id)), isNull);
    expect(prefs.getString(McpServerListNotifier.storageKey), '[]');
  });

  test('安全存储写不进去：报错、不保存这个服务，更不会降级成明文', () async {
    final n = McpServerListNotifier(prefs, _FailingStore());
    await expectLater(
      n.add(name: 'a', url: 'https://x.example', secrets: secrets),
      throwsA(isA<McpSecretStoreException>()),
    );
    expect(n.state, isEmpty);
    expect(prefs.getKeys(), isEmpty);
  });

  test('非 https 地址允许保存，isPlainHttp 为真（编辑页据此给明文警告）', () async {
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    await n.add(name: 'a', url: 'http://192.168.1.2:8080/mcp');
    await n.add(name: 'b', url: 'https://x.example/mcp');
    expect(n.state[0].isPlainHttp, isTrue);
    expect(n.state[1].isPlainHttp, isFalse);
  });
}
