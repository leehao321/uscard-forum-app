import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:fluxdo/services/site_data_migration.dart';
import 'package:fluxdo/services/site_registry_service.dart';
import 'package:fluxdo/services/storage/secret_store.dart';
import 'package:fluxdo/services/storage/site_directories.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 可以模拟安全存储暂时不可用（如 iOS 首次解锁前）。
class _FakeSecrets implements SecretStore {
  _FakeSecrets(Map<String, String> initial) : values = Map.of(initial);

  final Map<String, String> values;
  bool failWrites = false;
  bool failDeletes = false;
  bool failReads = false;

  /// 模拟「写入没报错但没落盘」。
  bool dropWrites = false;

  @override
  Future<String?> read(SecretKey key) async {
    if (failReads) throw StateError('keychain locked');
    return values[key.storageKey];
  }

  @override
  Future<void> write(SecretKey key, String value) async {
    if (failWrites) throw StateError('keychain locked');
    if (!dropWrites) values[key.storageKey] = value;
  }

  @override
  Future<void> delete(SecretKey key) async {
    if (failDeletes) throw StateError('keychain locked');
    values.remove(key.storageKey);
  }

  @override
  Future<void> deleteScope(SecretScope scope) async {}

  @override
  Future<SecretStoreAvailability> checkAvailability() async =>
      SecretStoreAvailability.available;
}

void main() {
  const uscard = SitePresets.uscard;
  late Directory docs;
  late Directory support;
  late SiteRegistryService registry;
  late _FakeSecrets secure;
  late SharedPreferences prefs;

  Future<void> setUpWith(
    Map<String, Object> prefValues, {
    Map<String, String> secureValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefValues);
    prefs = await SharedPreferences.getInstance();
    registry = SiteRegistryService();
    await registry.init(prefs);
    secure = _FakeSecrets(secureValues);
  }

  SiteDataMigration migration() => SiteDataMigration(
    prefs: prefs,
    registry: registry,
    secrets: secure,
    documentsDirectory: () async => docs,
    supportDirectory: () async => support,
  );

  File writeFile(String path, [String content = 'x']) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  setUp(() async {
    SiteContext.debugReset();
    docs = await Directory.systemTemp.createTemp('migration_docs');
    support = await Directory.systemTemp.createTemp('migration_support');
  });

  tearDown(() async {
    SiteContext.debugReset();
    await docs.delete(recursive: true);
    await support.delete(recursive: true);
  });

  test('全新安装：不注册站点，留给选站页', () async {
    await setUpWith({});

    await migration().run();

    expect(SiteContext.isConfigured, isFalse);
    expect(registry.sites, isEmpty);
    expect(prefs.getString(SiteDataMigration.stateKey), 'done');
  });

  test('已经选过站：不当作旧数据，别的站不受影响', () async {
    await setUpWith(
      {},
      secureValues: {'user_api_key_key': 'should-stay'},
    );
    await registry.addAndActivate(SitePresets.linuxdo);

    await migration().run();

    expect(SiteContext.current.id, SitePresets.linuxdo.id);
    expect(secure.values['user_api_key_key'], 'should-stay');
    expect(prefs.getString(SiteDataMigration.stateKey), 'done');
  });

  group('从 1.0.0 覆盖安装', () {
    const legacySecure = {
      'linux_do_username': 'alice',
      'linux_do_csrf_token': 'csrf',
      'user_api_key_key': 'api-key',
      'user_api_key_rsa_private': 'rsa',
      'user_api_key_client_id': 'client',
      'login_credential_username': 'alice',
      'login_credential_password': 'secret',
      // AI 供应商的 Key 和站点无关
      'ai_apikey_openai': 'global-key',
    };

    const legacyPrefs = <String, Object>{
      'onboarding_completed': true,
      'theme_mode': 2,
      'pref_locale': 'zh',
      'cookie_clean_slate_v3': true,
      'read_later_items': '[1]',
      'pinned_category_ids': <String>['1', '2'],
      'pref_blocked_usernames': <String>['spammer'],
      'current_user_cache': '{}',
      'topic_notes_v2': '{"notes":[]}',
      'reading_stats_v1': '{}',
      'nested_reading_v1_alice': '{}',
      'notion_config_alice': '{}',
      'bookmark_last_full_sync_alice': '2026',
      'invite_link_cache:alice': 'x',
      'ai_chat_topic_sessions_12': '[]',
      'ai_chat_session_messages_abc': '[]',
      'bg_notification_user_id': 7,
    };

    void writeLegacyFiles() {
      writeFile(p.join(docs.path, '.cookies', 'cookies.v1.json'), 'cookies');
      writeFile(p.join(docs.path, 'hive', 'bookmark_cache_alice.hive'), 'b');
      writeFile(p.join(docs.path, 'hive', 'bookmark_cache_alice.lock'), 'l');
      writeFile(p.join(docs.path, 'hive', 'export_history_alice.hive'), 'e');
      writeFile(p.join(docs.path, 'hive', 'local_drafts.hive'), 'd');
      writeFile(p.join(support.path, 'emoji_groups_snapshot.json'), 'emoji');
      writeFile(p.join(support.path, 'saved_topics', 'index.json'), 'idx');
      writeFile(p.join(support.path, 'saved_topics', '12.json'), 'topic');
    }

    test('不弹选站页，当前站就是USCard', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      writeLegacyFiles();

      await migration().run();

      expect(SiteContext.isConfigured, isTrue);
      expect(SiteContext.current.id, uscard.id);
      expect(SiteContext.current.featurePack, SiteFeaturePack.uscard);
      expect(prefs.getString(SiteDataMigration.stateKey), 'done');
    });

    test('登录凭证归到USCard，全局 key 不再留明面上的凭证', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);

      await migration().run();

      for (final key in const [
        'linux_do_username',
        'linux_do_csrf_token',
        'user_api_key_key',
        'user_api_key_rsa_private',
        'user_api_key_client_id',
        'login_credential_username',
        'login_credential_password',
      ]) {
        expect(
          secure.values[uscard.scopedKey(key)],
          legacySecure[key],
          reason: key,
        );
        expect(secure.values.containsKey(key), isFalse, reason: key);
      }
      expect(secure.values['ai_apikey_openai'], 'global-key');
    });

    test('站点数据归到USCard，全局设置和迁移标记不动', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);

      await migration().run();

      expect(prefs.getString(uscard.scopedKey('read_later_items')), '[1]');
      expect(
        prefs.getStringList(uscard.scopedKey('pinned_category_ids')),
        ['1', '2'],
      );
      expect(
        prefs.getStringList(uscard.scopedKey('pref_blocked_usernames')),
        ['spammer'],
      );
      expect(prefs.getInt(uscard.scopedKey('bg_notification_user_id')), 7);
      expect(prefs.getString(uscard.scopedKey('topic_notes_v2')), isNotNull);
      expect(prefs.getString(uscard.scopedKey('reading_stats_v1')), isNotNull);
      expect(
        prefs.getString(uscard.scopedKey('ai_chat_topic_sessions_12')),
        '[]',
      );
      for (final key in const [
        'read_later_items',
        'pinned_category_ids',
        'topic_notes_v2',
        'nested_reading_v1_alice',
        'invite_link_cache:alice',
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }

      expect(prefs.getBool('onboarding_completed'), isTrue);
      expect(prefs.getInt('theme_mode'), 2);
      expect(prefs.getString('pref_locale'), 'zh');
      expect(prefs.getBool('cookie_clean_slate_v3'), isTrue);
    });

    test('文件搬到USCard的目录，内容不变', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      writeLegacyFiles();

      await migration().run();

      final id = uscard.storageId;
      final siteDir = siteDataDirectory(support.path, uscard);
      expect(
        File(p.join(docs.path, '.cookies', id, 'cookies.v1.json'))
            .readAsStringSync(),
        'cookies',
      );
      expect(File(p.join(docs.path, '.cookies', 'cookies.v1.json')).existsSync(), isFalse);
      for (final name in const [
        'bookmark_cache_alice.hive',
        'bookmark_cache_alice.lock',
        'export_history_alice.hive',
        'local_drafts.hive',
      ]) {
        expect(File(p.join(docs.path, 'hive', '${id}__$name')).existsSync(), isTrue, reason: name);
        expect(File(p.join(docs.path, 'hive', name)).existsSync(), isFalse, reason: name);
      }
      expect(
        File(p.join(siteDir, 'emoji_groups_snapshot.json')).readAsStringSync(),
        'emoji',
      );
      expect(
        File(p.join(siteDir, 'saved_topics', '12.json')).readAsStringSync(),
        'topic',
      );
      expect(Directory(p.join(support.path, 'saved_topics')).existsSync(), isFalse);
    });

    test('只有 Cookie 文件或只有凭证，也认得出是老用户', () async {
      await setUpWith({});
      writeFile(p.join(docs.path, '.cookies', 'cookies.v1.json'));
      await migration().run();
      expect(SiteContext.current.id, uscard.id);

      SiteContext.debugReset();
      await docs.delete(recursive: true);
      docs = await Directory.systemTemp.createTemp('migration_docs');
      await setUpWith({}, secureValues: {'user_api_key_key': 'k'});
      await migration().run();
      expect(secure.values[uscard.scopedKey('user_api_key_key')], 'k');
    });

    test('安全存储暂时不可用：不丢凭证，下次启动继续', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      writeLegacyFiles();
      secure.failWrites = true;

      await migration().run();

      // 这次迁不完也不弹选站页，其他数据照常迁
      expect(SiteContext.current.id, uscard.id);
      expect(prefs.getString(SiteDataMigration.stateKey), 'pending');
      expect(secure.values['user_api_key_key'], 'api-key');
      expect(prefs.getString(uscard.scopedKey('read_later_items')), '[1]');

      // 模拟下次启动
      secure.failWrites = false;
      SiteContext.debugReset();
      registry = SiteRegistryService();
      await registry.init(prefs);
      await migration().run();

      expect(SiteContext.current.id, uscard.id);
      expect(prefs.getString(SiteDataMigration.stateKey), 'done');
      expect(secure.values[uscard.scopedKey('user_api_key_key')], 'api-key');
      expect(secure.values.containsKey('user_api_key_key'), isFalse);
    });

    test('写入没落盘时不删旧凭证', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      secure.dropWrites = true;

      await migration().run();

      expect(secure.values['user_api_key_key'], 'api-key');
      expect(prefs.getString(SiteDataMigration.stateKey), 'pending');
    });

    test('读不出安全存储时不当作没有凭证，下次继续', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      secure.failReads = true;

      await migration().run();

      expect(prefs.getString(SiteDataMigration.stateKey), 'pending');
      expect(secure.values['user_api_key_key'], 'api-key');
    });

    test('新位置写好但旧 key 删不掉：下次补删，凭证只留新位置', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      secure.failDeletes = true;
      await migration().run();
      expect(prefs.getString(SiteDataMigration.stateKey), 'pending');
      expect(secure.values[uscard.scopedKey('user_api_key_key')], 'api-key');

      secure.failDeletes = false;
      await migration().run();

      expect(prefs.getString(SiteDataMigration.stateKey), 'done');
      expect(secure.values.containsKey('user_api_key_key'), isFalse);
    });

    test('早期版本的明文兜底也迁走并清掉', () async {
      await setUpWith({
        'onboarding_completed': true,
        '__secure_fallback__user_api_key_key': 'plain-key',
      });

      await migration().run();

      expect(secure.values[uscard.scopedKey('user_api_key_key')], 'plain-key');
      expect(prefs.containsKey('__secure_fallback__user_api_key_key'), isFalse);
    });

    test('目标已有值时以目标为准：重新登录过的凭证不会被旧值盖掉', () async {
      await setUpWith(
        {
          SiteDataMigration.stateKey: 'pending',
          'read_later_items': 'old',
          uscard.scopedKey('read_later_items'): 'new',
        },
        secureValues: {
          'user_api_key_key': 'old-key',
          uscard.scopedKey('user_api_key_key'): 'new-key',
        },
      );

      await migration().run();

      expect(secure.values[uscard.scopedKey('user_api_key_key')], 'new-key');
      expect(secure.values.containsKey('user_api_key_key'), isFalse);
      expect(prefs.getString(uscard.scopedKey('read_later_items')), 'new');
      expect(prefs.containsKey('read_later_items'), isFalse);
    });

    test('文件目标已存在时两份都留，不覆盖', () async {
      await setUpWith(legacyPrefs);
      final legacy = writeFile(p.join(docs.path, '.cookies', 'cookies.v1.json'), 'old');
      final current = writeFile(
        p.join(docs.path, '.cookies', uscard.storageId, 'cookies.v1.json'),
        'new',
      );

      await migration().run();

      expect(current.readAsStringSync(), 'new');
      expect(legacy.readAsStringSync(), 'old');
      expect(prefs.getString(SiteDataMigration.stateKey), 'done');
    });

    test('跑完不再重复：之后新出现的同名 key 不会被挪走', () async {
      await setUpWith(legacyPrefs, secureValues: legacySecure);
      await migration().run();

      await prefs.setString('read_later_items', 'later');
      await migration().run();

      expect(prefs.getString('read_later_items'), 'later');
    });
  });
}
