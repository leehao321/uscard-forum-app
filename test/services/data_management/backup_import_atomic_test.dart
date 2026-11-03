import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_profile.dart';
import 'package:fluxdo/services/data_management/cache_size_service.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:fluxdo/services/site_context.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'pref_a': 'old-a',
      'pref_b': 'old-b',
    });
    prefs = await SharedPreferences.getInstance();
    SiteContext.activate(SitePresets.uscard);
  });

  tearDown(SiteContext.debugReset);

  Map<String, dynamic> backup(Map<String, dynamic> data, {Object? apiKeys}) => {
    'version': 2,
    'data': data,
    'apiKeys': ?apiKeys,
  };

  group('G-1 备份导入不留半截', () {
    Future<void> expectRejectedUntouched(Map<String, dynamic> data, {Object? apiKeys}) async {
      await expectLater(
        DataBackupService.importData(prefs, backup(data, apiKeys: apiKeys)),
        throwsFormatException,
      );
      expect(prefs.getString('pref_a'), 'old-a', reason: '校验失败前不能写入任何一项');
      expect(prefs.getString('pref_b'), 'old-b');
    }

    const good = {'type': 'String', 'value': 'new-a'};

    // 错误提示用 S.current，要有挂着 navigatorKey 的 App
    testWidgets('有一项值的类型不对：全部不写', (tester) async {
      await pumpApp(tester, const SizedBox());
      await expectRejectedUntouched({
        'pref_a': good,
        'pref_b': {'type': 'bool', 'value': 'not-bool'},
      });
    });

    testWidgets('有一项结构不对：全部不写', (tester) async {
      await pumpApp(tester, const SizedBox());
      await expectRejectedUntouched({'pref_a': good, 'pref_b': 'oops'});
    });

    testWidgets('type 不是字符串：全部不写', (tester) async {
      await pumpApp(tester, const SizedBox());
      await expectRejectedUntouched({
        'pref_a': good,
        'pref_b': {'type': 1, 'value': 'x'},
      });
    });

    testWidgets('字符串列表里混了别的类型：全部不写', (tester) async {
      await pumpApp(tester, const SizedBox());
      await expectRejectedUntouched({
        'pref_a': good,
        'pref_b': {
          'type': 'StringList',
          'value': ['a', 1],
        },
      });
    });

    testWidgets('apiKeys 结构不对：设置也不写', (tester) async {
      await pumpApp(tester, const SizedBox());
      await expectRejectedUntouched({'pref_a': good}, apiKeys: 'oops');
      await expectRejectedUntouched({'pref_a': good}, apiKeys: {'p': 1});
    });

    test('合法备份全部写入，各类型都对', () async {
      await DataBackupService.importData(
        prefs,
        backup({
          'pref_a': good,
          'pref_bool': {'type': 'bool', 'value': true},
          'pref_int': {'type': 'int', 'value': 3},
          'pref_double': {'type': 'double', 'value': 2},
          'pref_list': {
            'type': 'StringList',
            'value': ['x'],
          },
        }),
      );
      expect(prefs.getString('pref_a'), 'new-a');
      expect(prefs.getBool('pref_bool'), isTrue);
      expect(prefs.getInt('pref_int'), 3);
      expect(prefs.getDouble('pref_double'), 2.0);
      expect(prefs.getStringList('pref_list'), ['x']);
    });

    test('未知类型跳过，不算错（新版本备份导入旧版本）', () async {
      await DataBackupService.importData(
        prefs,
        backup({
          'pref_a': good,
          'pref_new': {'type': 'FutureType', 'value': 1},
        }),
      );
      expect(prefs.getString('pref_a'), 'new-a');
      expect(prefs.containsKey('pref_new'), isFalse);
    });

    test('被排除的 key 结构不对也不影响导入', () async {
      await DataBackupService.importData(
        prefs,
        backup({'pref_a': good, 'current_user_cache': 'oops'}),
      );
      expect(prefs.getString('pref_a'), 'new-a');
    });
  });

  group('G-2 导出的临时文件不留下', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('backup-export-');
      PackageInfo.setMockInitialValues(
        appName: 'a',
        packageName: 'p',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
    });

    tearDown(() => temp.delete(recursive: true));

    test('保存成功后删除，保存时文件还在', () async {
      late String seen;
      final result = await DataBackupService.withExportFile(prefs, (path) async {
        seen = path;
        expect(await File(path).exists(), isTrue);
        return 7;
      });
      expect(result, 7);
      expect(await File(seen).exists(), isFalse);
    });

    test('保存失败也删除，异常原样抛出', () async {
      late String seen;
      await expectLater(
        DataBackupService.withExportFile<void>(prefs, (path) async {
          seen = path;
          throw StateError('save failed');
        }),
        throwsStateError,
      );
      expect(await File(seen).exists(), isFalse);
    });

    test('文件已被别处删掉也不报错', () async {
      await DataBackupService.withExportFile(prefs, (path) => File(path).delete());
    });
  });

  group('F12 AI 聊天占用统计', () {
    test('统计当前站的会话数据', () async {
      await prefs.setString(SiteContext.scopedKey('ai_chat_session_messages_1'), 'abcd');
      await prefs.setString(SiteContext.scopedKey('ai_chat_all_sessions_index'), 'ef');
      expect(await CacheSizeService.getAiChatDataSize(prefs), 12);
    });

    test('别的站和全局设置不算：清除按钮只清当前站', () async {
      final other = SitePresets.linuxdo;
      await prefs.setString(other.scopedKey('ai_chat_session_messages_1'), 'abcd');
      await prefs.setString('ai_chat_title_model', 'p:m');
      expect(await CacheSizeService.getAiChatDataSize(prefs), 0);
    });
  });
}
