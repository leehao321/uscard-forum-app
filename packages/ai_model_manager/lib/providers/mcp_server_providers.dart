import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/mcp_server_config.dart';
import '../services/mcp_client_service.dart';
import '../services/mcp_tool_bridge.dart';
import 'ai_chat_providers.dart' show aiRequestClientFactoryProvider;
import 'ai_provider_providers.dart' show aiSharedPreferencesProvider;

/// 安全存储写不进去
class McpSecretStoreException implements Exception {
  const McpSecretStoreException(this.cause);
  final Object cause;
  @override
  String toString() => '系统安全存储不可用：$cause';
}

/// 存 MCP 服务的 Token 和请求头。默认实现用系统安全存储；
/// 写不进去就报错，不降级成明文。
abstract class McpSecretStore {
  Future<McpSecrets> read(String serverId);
  Future<void> write(String serverId, McpSecrets secrets);
  Future<void> delete(String serverId);
}

class SecureMcpSecretStore implements McpSecretStore {
  SecureMcpSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  final FlutterSecureStorage _storage;

  /// 安全存储里的键
  @visibleForTesting
  static String keyOf(String serverId) => 'mcp_server_secret_$serverId';

  @override
  Future<McpSecrets> read(String serverId) async {
    try {
      final raw = await _storage.read(key: keyOf(serverId));
      if (raw == null || raw.isEmpty) return const McpSecrets();
      return McpSecrets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Mcp] 读取凭据失败: $e');
      return const McpSecrets();
    }
  }

  @override
  Future<void> write(String serverId, McpSecrets secrets) async {
    try {
      if (secrets.isEmpty) {
        await _storage.delete(key: keyOf(serverId));
      } else {
        await _storage.write(key: keyOf(serverId), value: jsonEncode(secrets.toJson()));
      }
    } catch (e) {
      throw McpSecretStoreException(e);
    }
  }

  @override
  Future<void> delete(String serverId) async {
    try {
      await _storage.delete(key: keyOf(serverId));
    } catch (e) {
      debugPrint('[Mcp] 删除凭据失败: $e');
    }
  }
}

final mcpSecretStoreProvider = Provider<McpSecretStore>((_) => SecureMcpSecretStore());

/// MCP 服务列表。公开部分存 SharedPreferences（`mcp_servers_v1`），敏感部分存 [McpSecretStore]。
class McpServerListNotifier extends StateNotifier<List<McpServerConfig>> {
  McpServerListNotifier(this._prefs, this._secrets) : super(const []) {
    _load();
  }

  /// SharedPreferences 里的键（不进数据备份，见备份服务的排除清单）
  static const storageKey = 'mcp_servers_v1';
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  final McpSecretStore _secrets;

  void _load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = [
        for (final e in jsonDecode(raw) as List) McpServerConfig.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      // 数据损坏时忽略
    }
  }

  Future<void> _save() => _prefs.setString(storageKey, jsonEncode([for (final s in state) s.toJson()]));

  Future<McpSecrets> secretsOf(String id) => _secrets.read(id);

  /// 添加；先写敏感部分，写失败就整个不保存
  Future<String> add({
    required String name,
    required String url,
    McpSecrets secrets = const McpSecrets(),
    bool enabled = true,
  }) async {
    final id = _uuid.v4();
    await _secrets.write(id, secrets);
    state = [...state, McpServerConfig(id: id, name: name, url: url.trim(), enabled: enabled)];
    await _save();
    return id;
  }

  /// 更新；[secrets] 为空表示不改敏感部分
  Future<void> update(
    String id, {
    String? name,
    String? url,
    bool? enabled,
    Map<String, bool>? toolStates,
    McpSecrets? secrets,
  }) async {
    if (secrets != null) await _secrets.write(id, secrets);
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(name: name, url: url?.trim(), enabled: enabled, toolStates: toolStates) else s,
    ];
    await _save();
  }

  Future<void> remove(String id) async {
    state = [for (final s in state) if (s.id != id) s];
    await _save();
    await _secrets.delete(id);
  }
}

final mcpServerListProvider = StateNotifierProvider<McpServerListNotifier, List<McpServerConfig>>(
  (ref) => McpServerListNotifier(ref.watch(aiSharedPreferencesProvider), ref.watch(mcpSecretStoreProvider)),
);

/// MCP 客户端：每个请求用应用网络栈（跟随应用网络配置时）创建的独立 client
final mcpClientServiceProvider = Provider<McpClientService>((ref) {
  http.Client Function() factory = ref.watch(aiRequestClientFactoryProvider);
  return McpClientService(clientFactory: factory);
});

/// 至少有一个启用的服务
final hasEnabledMcpServerProvider = Provider<bool>(
  (ref) => ref.watch(mcpServerListProvider).any((s) => s.enabled),
);

/// 新建一个工具桥（调用方持有，用完不用管；工具列表有缓存，所以最好长期持有同一个）
McpToolBridge createMcpToolBridge(Ref ref) {
  final notifier = ref.read(mcpServerListProvider.notifier);
  return McpToolBridge(service: ref.read(mcpClientServiceProvider), secretsOf: notifier.secretsOf);
}
