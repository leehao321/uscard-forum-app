import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_profile.dart';
import 'site_data_migration.dart';
import 'storage/secret_store.dart';
import 'storage/system_secret_store.dart';

/// 移除论坛时清掉它的登录状态和保存的账号密码。
///
/// 笔记、阅读统计、已存帖子这些用户自己的数据不动，重新添加后还在。
class SiteDataCleaner {
  SiteDataCleaner({
    required SecretStore secrets,
    required Future<Directory> Function() documentsDirectory,
    required Future<SharedPreferences> Function() prefs,
    required Future<void> Function(SiteProfile site) deleteWebViewCookies,
  }) : _secrets = secrets,
       _documentsDirectory = documentsDirectory,
       _prefs = prefs,
       _deleteWebViewCookies = deleteWebViewCookies;

  factory SiteDataCleaner.forDevice() => SiteDataCleaner(
    secrets: SystemSecretStore.instance,
    documentsDirectory: getApplicationDocumentsDirectory,
    prefs: SharedPreferences.getInstance,
    deleteWebViewCookies: (site) => CookieManager.instance().deleteCookies(
      url: WebUri(site.baseUrl),
    ),
  );

  final SecretStore _secrets;
  final Future<Directory> Function() _documentsDirectory;
  final Future<SharedPreferences> Function() _prefs;
  final Future<void> Function(SiteProfile site) _deleteWebViewCookies;

  /// 和登录身份绑定的按站偏好：账号缓存和后台通知状态。
  static const _loginPrefKeys = [
    'bg_long_polling_base_url',
    'bg_notification_last_message_id',
    'bg_notification_user_id',
    'bg_shared_session_key',
    'current_user_cache',
    'current_user_cache_username',
    'user_summary_cache',
    'user_summary_cache_username',
  ];

  /// 每一步单独兜底：一步失败不影响其他步。全部成功返回 true。日志只写步骤名。
  Future<bool> clearLogin(SiteProfile site) async {
    var ok = true;
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        ok = false;
        debugPrint('[SiteDataCleaner] $name 失败: ${e.runtimeType}');
      }
    }

    for (final key in siteScopedSecureKeys) {
      await step(
        '安全存储 $key',
        () => _secrets.delete(
          SecretKey.raw(
            site.scopedKey(key),
            fallbackPolicy: SecretFallbackPolicy.deny,
          ),
        ),
      );
    }
    await step('Cookie 文件', () async {
      final docs = await _documentsDirectory();
      final dir = Directory(p.join(docs.path, '.cookies', site.storageId));
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await step('偏好', () async {
      final prefs = await _prefs();
      for (final key in _loginPrefKeys) {
        await prefs.remove(site.scopedKey(key));
      }
    });
    await step('WebView Cookie', () => _deleteWebViewCookies(site));
    return ok;
  }
}
