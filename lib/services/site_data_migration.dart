import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_profile.dart';
import 'site_registry_service.dart';
import 'storage/secret_store.dart';
import 'storage/site_directories.dart';
import 'storage/system_secret_store.dart';

/// 按站存放的 SharedPreferences key。没列在这里的都是全局设置（外观、网络、
/// 阅读偏好等）。新增按站 key 时要同步加到这里，老备份导入和升级迁移都靠它。
class SiteScopedPrefKeys {
  SiteScopedPrefKeys._();

  static const exact = {
    'ai_chat_all_sessions_index',
    'ai_post_review_guidelines_cache',
    'ai_post_review_guidelines_cache_updated_at',
    'auth_clear_data_suggestion_at_v1',
    'auth_passive_logout_history_v1',
    'bg_long_polling_base_url',
    'bg_notification_last_message_id',
    'bg_notification_user_id',
    'bg_shared_session_key',
    'chat_recent_reactions',
    'current_user_cache',
    'current_user_cache_username',
    'pinned_category_ids',
    'pref_blocked_usernames',
    'pref_hcaptcha_create_endpoint',
    'read_later_items',
    'recent_emojis',
    'seeking_config',
    'seeking_config.unread',
    'seeking_enabled',
    'seeking_pace_seconds',
    'user_summary_cache',
    'user_summary_cache_username',
    // 1.0.0 的本机笔记和阅读统计，S2 搬功能时要用 scopedKey 读这些 key
    'reading_stats_v1',
    'topic_notes_v1',
    'topic_notes_v2',
  };

  static const prefixes = [
    'ai_chat_session_messages_',
    'ai_chat_topic_sessions_',
    'bookmark_last_full_sync_',
    'invite_link_cache:',
    'nested_reading_v1_',
    'nested_sort_',
    'notion_config_',
  ];

  static bool matches(String key) =>
      exact.contains(key) || prefixes.any(key.startsWith);
}

/// 安全存储里按站存放的 key。
const siteScopedSecureKeys = [
  'linux_do_csrf_token',
  'linux_do_username',
  'login_credential_password',
  'login_credential_username',
  'user_api_key_client_id',
  'user_api_key_key',
  'user_api_key_pending_nonce',
  'user_api_key_qr_client_id',
  'user_api_key_rsa_private',
];

/// 把存储隔离之前（1.0.0）的全部数据归到美卡预置站，装完不掉登录、不丢笔记。
///
/// 这份代码随壳一起发，但只有和 1.0.0 同包名覆盖安装时才有旧数据可迁；
/// 用新包名 `com.hao.uscardforum.flux` 并存时检测不到旧数据，什么也不做。
///
/// 每一步都可重入：中途被杀或安全存储暂时不可用时，状态保持 pending，下次启动
/// 继续。目标已有值时以目标为准（说明已迁过，或用户已重新登录）。
class SiteDataMigration {
  SiteDataMigration({
    required this._prefs,
    required this._registry,
    required this._secrets,
    required this._documentsDirectory,
    required this._supportDirectory,
  });

  factory SiteDataMigration.forDevice(SharedPreferences prefs) =>
      SiteDataMigration(
        prefs: prefs,
        registry: SiteRegistryService.instance,
        secrets: SystemSecretStore.instance,
        documentsDirectory: getApplicationDocumentsDirectory,
        supportDirectory: getApplicationSupportDirectory,
      );

  /// 以 `site_registry_` 开头，不进数据备份。
  @visibleForTesting
  static const stateKey = 'site_registry_legacy_migration';
  static const _statePending = 'pending';
  static const _stateDone = 'done';

  /// `ResilientSecureStorage` 早期版本写过的明文兜底 key 前缀。
  static const _legacyPlainFallbackPrefix = '__secure_fallback__';

  /// 旧数据归属的站点。
  static const SiteProfile _target = SitePresets.uscard;

  /// 旧版 Hive 盒名的开头。按站隔离后的盒名以 storageId 开头，不会匹配。
  static const _legacyBoxPrefixes = [
    'bookmark_cache_',
    'chat_cache_',
    'export_history_',
    'local_drafts',
  ];

  final SharedPreferences _prefs;
  final SiteRegistryService _registry;
  final SecretStore _secrets;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _supportDirectory;

  /// 在 Cookie、Hive 等服务初始化之前调用；它们一旦打开旧文件就不能再搬。
  Future<void> run() async {
    final state = _prefs.getString(stateKey);
    if (state == _stateDone) return;

    if (state == null) {
      // 已经选过站，或者是全新安装：都没有旧数据要迁
      if (_registry.current != null || !await _hasLegacyData()) {
        await _prefs.setString(stateKey, _stateDone);
        return;
      }
      await _prefs.setString(stateKey, _statePending);
    }

    // 先定下当前站：即使下面某步失败，也不会再弹选站页把旧数据晾在一边
    if (_registry.current == null) {
      await _registry.addAndActivate(_target);
    }

    final steps = await Future.wait([
      _migrateSecureStorage(),
      _migratePrefs(),
      _migrateFiles(),
    ]);
    if (steps.every((ok) => ok)) {
      await _prefs.setString(stateKey, _stateDone);
      debugPrint('[SiteDataMigration] 旧数据已归到 ${_target.host}');
    } else {
      debugPrint('[SiteDataMigration] 部分数据未迁完，下次启动继续');
    }
  }

  Future<bool> _hasLegacyData() async {
    if (_prefs.getBool('onboarding_completed') == true) return true;
    if (_prefs.getKeys().any(SiteScopedPrefKeys.matches)) return true;
    try {
      final docs = await _documentsDirectory();
      if (await File(_legacyCookieFile(docs)).exists()) return true;
    } catch (e) {
      debugPrint('[SiteDataMigration] 检查旧 Cookie 失败: $e');
    }
    try {
      for (final key in const ['linux_do_username', 'user_api_key_key']) {
        if (await _readLegacySecret(key) != null) return true;
      }
    } catch (e) {
      debugPrint('[SiteDataMigration] 检查旧凭证失败: $e');
    }
    return false;
  }

  static String _legacyCookieFile(Directory docs) =>
      p.join(docs.path, '.cookies', 'cookies.v1.json');

  /// 严格模式：系统安全存储不可用时抛异常，不降级到内存。
  ///
  /// 平时用的 `ResilientSecureStorage` 写失败时只存进内存、不报错。迁移如果走它，
  /// 接着删掉旧 key，重启后凭证就没了。
  SecretKey _strictKey(String key) =>
      SecretKey.raw(key, fallbackPolicy: SecretFallbackPolicy.deny);

  Future<String?> _readLegacySecret(String key) async =>
      await _secrets.read(_strictKey(key)) ??
      _prefs.getString('$_legacyPlainFallbackPrefix$key');

  /// 日志只写 key 名，不写值。
  Future<bool> _migrateSecureStorage() async {
    var ok = true;
    for (final key in siteScopedSecureKeys) {
      try {
        final legacy = await _readLegacySecret(key);
        if (legacy == null) continue;
        final target = _strictKey(_target.scopedKey(key));
        if (await _secrets.read(target) == null) {
          await _secrets.write(target, legacy);
        }
        // 确认新位置读得出来，才能删旧的
        if (await _secrets.read(target) == null) {
          throw StateError('写入后读不到');
        }
        await _secrets.delete(_strictKey(key));
        await _prefs.remove('$_legacyPlainFallbackPrefix$key');
      } catch (e) {
        ok = false;
        debugPrint('[SiteDataMigration] 安全存储 $key 迁移失败: ${e.runtimeType}');
      }
    }
    return ok;
  }

  Future<bool> _migratePrefs() async {
    var ok = true;
    for (final key in _prefs.getKeys().where(SiteScopedPrefKeys.matches).toList()) {
      try {
        final targetKey = _target.scopedKey(key);
        if (!_prefs.containsKey(targetKey)) {
          await _writePref(targetKey, _prefs.get(key));
        }
        await _prefs.remove(key);
      } catch (e) {
        ok = false;
        debugPrint('[SiteDataMigration] 偏好 $key 迁移失败: ${e.runtimeType}');
      }
    }
    return ok;
  }

  Future<void> _writePref(String key, Object? value) async {
    switch (value) {
      case final bool v:
        await _prefs.setBool(key, v);
      case final int v:
        await _prefs.setInt(key, v);
      case final double v:
        await _prefs.setDouble(key, v);
      case final String v:
        await _prefs.setString(key, v);
      case final List<dynamic> v:
        await _prefs.setStringList(key, v.cast<String>());
      default:
        throw ArgumentError('不支持的偏好类型: ${value.runtimeType}');
    }
  }

  Future<bool> _migrateFiles() async {
    try {
      final docs = await _documentsDirectory();
      final support = await _supportDirectory();
      final siteDir = siteDataDirectory(support.path, _target);

      await _moveFile(
        _legacyCookieFile(docs),
        p.join(docs.path, '.cookies', _target.storageId, 'cookies.v1.json'),
      );
      await _moveHiveBoxes(p.join(docs.path, 'hive'));
      await _moveFile(
        p.join(support.path, 'emoji_groups_snapshot.json'),
        p.join(siteDir, 'emoji_groups_snapshot.json'),
      );
      // 1.0.0 的「看过就存」，S2 搬功能时存到 siteSupportDirectory()/saved_topics
      await _moveDirectory(
        p.join(support.path, 'saved_topics'),
        p.join(siteDir, 'saved_topics'),
      );
      return true;
    } catch (e) {
      debugPrint('[SiteDataMigration] 文件迁移失败: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _moveHiveBoxes(String hivePath) async {
    final dir = Directory(hivePath);
    if (!await dir.exists()) return;
    for (final entity in await dir.list().toList()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!_legacyBoxPrefixes.any(name.startsWith)) continue;
      await _moveFile(
        entity.path,
        p.join(hivePath, '${_target.storageId}__$name'),
      );
    }
  }

  /// 目标已存在时保留两份，不覆盖也不删除，宁可多占点空间也不丢数据。
  Future<void> _moveFile(String from, String to) async {
    final source = File(from);
    if (!await source.exists() || await File(to).exists()) return;
    await File(to).parent.create(recursive: true);
    await source.rename(to);
  }

  Future<void> _moveDirectory(String from, String to) async {
    final source = Directory(from);
    if (!await source.exists() || await Directory(to).exists()) return;
    await Directory(to).parent.create(recursive: true);
    await source.rename(to);
  }
}
