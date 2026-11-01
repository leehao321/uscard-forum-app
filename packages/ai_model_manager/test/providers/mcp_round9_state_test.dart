import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 审查第 9 批：凭据读失败不能当成空凭据；服务列表逐条容错、读不出来时原文不被覆盖。

/// 读 / 写都抛的安全存储
class _Failing implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('钥匙串不可用');
}

class _Garbage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => '{这不是 json';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('读安全存储失败：抛 McpSecretReadException，不返回空凭据', () async {
    final store = SecureMcpSecretStore(_Failing());
    await expectLater(store.read('a'), throwsA(isA<McpSecretReadException>()));
  });

  test('存的内容读不懂：同样抛异常，不当成没有', () async {
    final store = SecureMcpSecretStore(_Garbage());
    await expectLater(store.read('a'), throwsA(isA<McpSecretReadException>()));
  });

  test('没有保存过：返回空凭据（不是异常）', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final secrets = await SecureMcpSecretStore().read('nobody');
    expect(secrets.isEmpty, isTrue);
  });

  test('列表逐条容错：坏条目跳过，好的保留；之后保存时坏条目原样写回，不丢', () async {
    final good = const McpServerConfig(id: 'g1', name: '好的', url: 'https://a.example/mcp').toJson();
    final bad = {'id': 5, 'name': null, 'weird': true}; // id 类型不对
    SharedPreferences.setMockInitialValues({
      McpServerListNotifier.storageKey: jsonEncode([good, bad, 'not a map']),
    });
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    expect(n.state.map((s) => s.id), ['g1']);
    await n.add(name: '新的', url: 'https://b.example/mcp');
    final saved = jsonDecode(prefs.getString(McpServerListNotifier.storageKey)!) as List;
    expect(saved.length, 4, reason: '2 个好的 + 2 个读不懂的原样保留');
    expect(saved.map(jsonEncode), contains(jsonEncode(bad)));
    expect(saved.map(jsonEncode), contains(jsonEncode('not a map')));
  });

  test('整份数据读不出来：原文备份到另一个键，之后保存不会把原文覆盖掉', () async {
    const raw = '{{{这不是 json';
    SharedPreferences.setMockInitialValues({McpServerListNotifier.storageKey: raw});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final n = McpServerListNotifier(prefs, SecureMcpSecretStore());
    expect(n.state, isEmpty);
    expect(prefs.getString(McpServerListNotifier.corruptBackupKey), raw);
    await n.add(name: '新的', url: 'https://b.example/mcp');
    expect(prefs.getString(McpServerListNotifier.storageKey), isNot(raw));
    expect(prefs.getString(McpServerListNotifier.corruptBackupKey), raw, reason: '原文还在');
  });

  test('备份规则：读不出来时的备份键也不进数据备份', () {
    expect(McpServerListNotifier.corruptBackupKey.startsWith('mcp_servers_'), isTrue);
  });
}
