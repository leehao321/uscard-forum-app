import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 审阅核实 M-1：本机已经写过 0.4.0 笔记（v2 非空）时导入 0.3.x 备份（只有 v1），
// 备份里的笔记不能被忽略。

String _v1Backup() => jsonEncode([
  {
    'id': 7,
    'title': '旧话题',
    'text': '备份里的话题笔记',
    'excerpts': [
      {'text': '备份里的摘录', 'at': 1700000000000},
    ],
    'updated': 1700000100000,
  },
  {
    'id': 9,
    'title': '两边都有的话题',
    'text': '',
    'excerpts': [
      {'text': '只在备份里的摘录', 'at': 1700000000000},
    ],
    'updated': 1700000100000,
  },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'fluxdo',
      packageName: 'app.fluxdo',
      version: '0.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('本机已有 v2 笔记时，导入只带 v1 的旧备份：备份里的笔记并进来', () async {
    SharedPreferences.setMockInitialValues({});
    // 先在 0.4.0 里写一条笔记（只有 v2）
    await TopicNoteStore.save(
      TopicNote(
        topicId: 9,
        title: '两边都有的话题',
        text: '本机的话题笔记',
        floorNotes: const {3: '本机的 3 楼笔记'},
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000200000),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    await DataBackupService.importData(prefs, {
      'version': 1,
      'data': {
        'topic_notes_v1': {'type': 'String', 'value': _v1Backup()},
      },
    });

    final seven = await TopicNoteStore.get(7);
    expect(seven, isNotNull, reason: '只在备份里的话题要出现');
    expect(seven!.text, '备份里的话题笔记');

    final nine = await TopicNoteStore.get(9);
    expect(nine!.text, '本机的话题笔记', reason: '两边都有时保留本机的话题文字');
    expect(nine.floorNotes[3], '本机的 3 楼笔记', reason: '楼层笔记不能丢');
    expect(
      nine.excerpts.map((e) => e.text),
      contains('只在备份里的摘录'),
      reason: '摘录取并集',
    );
  });
}
