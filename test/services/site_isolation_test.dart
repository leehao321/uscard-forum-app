import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_data_migration.dart';
import 'package:fluxdo/services/storage/site_directories.dart';
import 'package:fluxdo/services/storage/site_scoped_secure_storage.dart';
import 'package:fluxdo/services/user_api_key_service.dart';
import 'package:fluxdo/storage/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 两个站上的同名用户 alice 不能共用任何数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final siteA = SitePresets.uscard;
  final siteB = SiteProfile(baseUrl: 'https://example.com/forum', title: 'B');
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('site_isolation');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async => root.path);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await AppDatabase.debugReset();
    SiteContext.debugReset();
    AiChatStorageService.keyScope = '';
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上 Hive 可能还持有文件句柄，留给系统清理临时目录
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SiteContext.debugReset();
  });

  test('storageId 不能变：已落盘的数据靠它定位', () {
    expect(SitePresets.uscard.storageId, 'www_uscardforum_com_be583a3a');
    expect(SitePresets.linuxdo.storageId, 'linux_do_a2d3caa8');
    expect(siteB.storageId, 'example_com_forum_28992da4');
    expect(
      SitePresets.uscard.scopedKey('x'),
      'site.www_uscardforum_com_be583a3a.x',
    );
  });

  test('形似的地址不撞名', () {
    final a = SiteProfile(baseUrl: 'https://a.b/c', title: 'a');
    final b = SiteProfile(baseUrl: 'https://a-b/c'.replaceAll('-', '.'), title: 'b');
    final c = SiteProfile(baseUrl: 'https://a.b.c', title: 'c');
    expect(a.storageId, b.storageId, reason: '同一地址必须稳定');
    expect(a.storageId, isNot(c.storageId));
  });

  test('unscopedKey 还原任意站点的 key', () {
    expect(SiteContext.unscopedKey(siteA.scopedKey('read_later_items')), 'read_later_items');
    expect(SiteContext.unscopedKey(siteB.scopedKey('a.b')), 'a.b');
    expect(SiteContext.unscopedKey('theme_mode'), 'theme_mode');
    expect(SiteContext.unscopedKey('site_registry_sites'), 'site_registry_sites');
  });

  group('安全存储', () {
    test('同一个 key 两站各存各的', () async {
      final storage = SiteScopedSecureStorage();

      SiteContext.activate(siteA);
      await storage.write(key: 'linux_do_username', value: 'alice-a');
      SiteContext.activate(siteB);
      expect(await storage.read(key: 'linux_do_username'), isNull);
      await storage.write(key: 'linux_do_username', value: 'alice-b');

      SiteContext.activate(siteA);
      expect(await storage.read(key: 'linux_do_username'), 'alice-a');
      await storage.delete(key: 'linux_do_username');
      SiteContext.activate(siteB);
      expect(await storage.read(key: 'linux_do_username'), 'alice-b');
    });

    test('A 站的 User API Key 不会发给 B 站', () async {
      FlutterSecureStorage.setMockInitialValues({
        siteA.scopedKey('user_api_key_key'): 'key-of-a',
      });
      final service = UserApiKeyService();

      SiteContext.activate(siteA);
      expect(await service.readApiKey(), 'key-of-a');
      SiteContext.activate(siteB);
      expect(await service.readApiKey(), isNull);
    });
  });

  group('Hive', () {
    test('同名用户的书签盒和命名盒互不相干', () async {
      SiteContext.activate(siteA);
      final bookmarksA = await AppDatabase.bookmarkBox('alice');
      await bookmarksA.put(1, {'site': 'a'});
      final draftsA = await AppDatabase.namedBox('local_drafts');
      await draftsA.put('k', {'site': 'a'});

      SiteContext.activate(siteB);
      final bookmarksB = await AppDatabase.bookmarkBox('alice');
      final draftsB = await AppDatabase.namedBox('local_drafts');
      expect(bookmarksB.get(1), isNull);
      expect(draftsB.get('k'), isNull);
      expect(bookmarksB.name, isNot(bookmarksA.name));

      // 迁移把旧盒文件改成的名字，必须和这里打开的盒名一致
      expect(
        File(p.join(root.path, 'hive', '${siteA.storageId}__bookmark_cache_alice.hive'))
            .existsSync(),
        isTrue,
      );
    });
  });

  test('Cookie 按站分目录', () async {
    SiteContext.activate(siteA);
    await CookieJarService().initialize();
    expect(
      Directory(p.join(root.path, '.cookies', siteA.storageId)).existsSync(),
      isTrue,
    );
  });

  test('站点数据目录按站分开', () async {
    SiteContext.activate(siteB);
    final dir = await siteSupportDirectory();
    expect(dir.path, siteDataDirectory(root.path, siteB));
    expect(dir.existsSync(), isTrue);
  });

  test('AI 会话按站隔离，话题 ID 相同也不串', () async {
    final prefs = await SharedPreferences.getInstance();
    final storage = AiChatStorageService(prefs);
    final message = AiChatMessage(
      id: 'm1',
      role: ChatRole.user,
      content: 'hi',
      createdAt: DateTime(2026),
    );

    AiChatStorageService.keyScope = siteA.scopePrefix;
    await storage.saveSessionMessages(12, 's1', [message]);
    expect(storage.getTopicSessions(12), isNotEmpty);

    AiChatStorageService.keyScope = siteB.scopePrefix;
    expect(storage.getTopicSessions(12), isEmpty);
    expect(storage.loadSessionMessages('s1'), isEmpty);
    await storage.deleteAllSessions();

    AiChatStorageService.keyScope = siteA.scopePrefix;
    expect(storage.getTopicSessions(12), isNotEmpty);
  });

  group('数据备份', () {
    test('排除规则对按站 key 同样生效', () {
      for (final key in const [
        'current_user_cache',
        'user_summary_cache',
        'bg_shared_session_key',
        'linux_do_username',
      ]) {
        expect(
          DataBackupService.debugShouldBackup(siteA.scopedKey(key)),
          isFalse,
          reason: key,
        );
      }
      expect(
        DataBackupService.debugShouldBackup(siteA.scopedKey('read_later_items')),
        isTrue,
      );
    });

    test('新备份导回原站；按站隔离前的老备份归到当前站', () async {
      SiteContext.activate(siteB);
      final prefs = await SharedPreferences.getInstance();

      await DataBackupService.importData(prefs, {
        'data': {
          siteA.scopedKey('read_later_items'): {'type': 'String', 'value': 'a'},
          'pinned_category_ids': {
            'type': 'StringList',
            'value': <dynamic>['9'],
          },
          'theme_mode': {'type': 'int', 'value': 1},
        },
      });

      expect(prefs.getString(siteA.scopedKey('read_later_items')), 'a');
      expect(prefs.getStringList(siteB.scopedKey('pinned_category_ids')), ['9']);
      expect(prefs.containsKey('pinned_category_ids'), isFalse);
      expect(prefs.getInt('theme_mode'), 1);
    });
  });

  test('按站 key 表覆盖精确名和前缀，不误伤全局设置', () {
    expect(SiteScopedPrefKeys.matches('read_later_items'), isTrue);
    expect(SiteScopedPrefKeys.matches('notion_config_alice'), isTrue);
    expect(SiteScopedPrefKeys.matches('theme_mode'), isFalse);
    expect(SiteScopedPrefKeys.matches('onboarding_completed'), isFalse);
    expect(SiteScopedPrefKeys.matches('pref_topic_filter_keywords'), isFalse);
    expect(
      SiteScopedPrefKeys.matches(siteA.scopedKey('read_later_items')),
      isFalse,
    );
  });

  test('约定：只有白名单文件可以用全局安全存储', () {
    const allowed = {
      'lib/services/storage/resilient_secure_storage.dart',
      'lib/services/storage/site_scoped_secure_storage.dart',
      // 只导出 AI 供应商的 API Key
      'lib/services/data_management/data_backup_service.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (allowed.contains(path)) continue;
      if (entity.readAsStringSync().contains('ResilientSecureStorage(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });
}
