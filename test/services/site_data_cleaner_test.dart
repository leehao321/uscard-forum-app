import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/site_data_cleaner.dart';
import 'package:fluxdo/services/storage/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final removed = SiteProfile(baseUrl: 'https://removed.test', title: 'Removed');
  final other = SiteProfile(baseUrl: 'https://other.test', title: 'Other');
  late Directory docs;
  late InMemorySecretStore secrets;
  late List<String> webViewCleared;

  SiteDataCleaner cleaner({Future<void> Function(SiteProfile)? webView}) =>
      SiteDataCleaner(
        secrets: secrets,
        documentsDirectory: () async => docs,
        prefs: SharedPreferences.getInstance,
        deleteWebViewCookies:
            webView ?? (site) async => webViewCleared.add(site.id),
      );

  Future<File> cookieFile(SiteProfile site) async {
    final file = File('${docs.path}/.cookies/${site.storageId}/cookies.v1.json');
    await file.create(recursive: true);
    await file.writeAsString('{}');
    return file;
  }

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('site-cleaner-');
    secrets = InMemorySecretStore();
    webViewCleared = [];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => docs.delete(recursive: true));

  test('清掉这个站的凭证、Cookie、账号缓存和 WebView Cookie', () async {
    for (final key in [
      'user_api_key_key',
      'login_credential_password',
      'linux_do_username',
    ]) {
      await secrets.write(SecretKey.raw(removed.scopedKey(key)), 'secret');
    }
    final file = await cookieFile(removed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(removed.scopedKey('current_user_cache'), '{}');

    expect(await cleaner().clearLogin(removed), isTrue);

    for (final key in [
      'user_api_key_key',
      'login_credential_password',
      'linux_do_username',
    ]) {
      expect(await secrets.read(SecretKey.raw(removed.scopedKey(key))), isNull);
    }
    expect(await file.exists(), isFalse);
    expect(prefs.containsKey(removed.scopedKey('current_user_cache')), isFalse);
    expect(webViewCleared, [removed.id]);
  });

  test('别的站的数据不受影响', () async {
    final key = SecretKey.raw(other.scopedKey('user_api_key_key'));
    await secrets.write(key, 'keep');
    final file = await cookieFile(other);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(other.scopedKey('current_user_cache'), '{}');

    await cleaner().clearLogin(removed);

    expect(await secrets.read(key), 'keep');
    expect(await file.exists(), isTrue);
    expect(prefs.containsKey(other.scopedKey('current_user_cache')), isTrue);
  });

  test('笔记、阅读统计这些用户数据保留', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(removed.scopedKey('topic_notes_v2'), '{}');
    await prefs.setString(removed.scopedKey('reading_stats_v1'), '{}');

    await cleaner().clearLogin(removed);

    expect(prefs.containsKey(removed.scopedKey('topic_notes_v2')), isTrue);
    expect(prefs.containsKey(removed.scopedKey('reading_stats_v1')), isTrue);
  });

  test('一步失败不影响其他步，并返回 false', () async {
    final file = await cookieFile(removed);
    final ok = await cleaner(
      webView: (_) async => throw StateError('no webview'),
    ).clearLogin(removed);
    expect(ok, isFalse);
    expect(await file.exists(), isFalse);
  });

  test('没有数据时也算成功', () async {
    expect(await cleaner().clearLogin(removed), isTrue);
  });
}
