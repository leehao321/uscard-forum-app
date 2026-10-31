import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 0.4.0 M5：笔记升到 v2（按楼层），v1 迁移与备份往返。

String _v1() => jsonEncode([
  {
    'id': 7,
    'title': '旧话题',
    'text': '一段旧笔记',
    'excerpts': [
      {'text': '旧摘录', 'at': 1700000000000},
    ],
    'updated': 1700000100000,
  },
  {'id': 0, 'title': '坏数据', 'text': 'x', 'updated': 1},
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

  group('v1 → v2 迁移', () {
    test('读到 v1 时迁到 v2，v1 原样保留，内容不丢', () async {
      SharedPreferences.setMockInitialValues({'topic_notes_v1': _v1()});
      final note = await TopicNoteStore.get(7);
      expect(note, isNotNull);
      expect(note!.title, '旧话题');
      expect(note.text, '一段旧笔记');
      expect(note.excerpts.single.text, '旧摘录');
      expect(note.excerpts.single.postNumber, isNull);
      expect(note.floorNotes, isEmpty);
      // id 为 0 的坏数据被丢掉
      expect((await TopicNoteStore.list()).length, 1);

      final prefs = await SharedPreferences.getInstance();
      final v2 = jsonDecode(prefs.getString('topic_notes_v2')!) as Map;
      expect(v2['v'], 2);
      expect((v2['notes'] as List).length, 1);
      // 回退到旧版本时笔记还在
      expect(prefs.getString('topic_notes_v1'), _v1());
    });

    test('迁移之后只读写 v2，v1 不再影响结果', () async {
      SharedPreferences.setMockInitialValues({'topic_notes_v1': _v1()});
      await TopicNoteStore.get(7);
      await TopicNoteStore.delete(7);
      expect(await TopicNoteStore.get(7), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('topic_notes_v1'), _v1());
    });

    test('损坏的数据读成空，不抛异常', () async {
      SharedPreferences.setMockInitialValues({'topic_notes_v2': '{oops'});
      expect(await TopicNoteStore.list(), isEmpty);
    });
  });

  group('按楼层的笔记', () {
    test('楼层笔记存取、搜索、空判断', () async {
      SharedPreferences.setMockInitialValues({});
      final note = TopicNote(
        topicId: 9,
        title: 'Hello',
        floorNotes: const {12: '第十二楼的 要点', 3: ''},
        excerpts: [
          NoteExcerpt(
            text: '摘录',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1),
            postNumber: 12,
          ),
        ],
        updatedAt: DateTime.now(),
      );
      expect(note.isEmpty, isFalse);
      expect(note.floors, [12]);
      expect(note.searchText, contains('要点'));

      await TopicNoteStore.save(note);
      final back = (await TopicNoteStore.get(9))!;
      expect(back.floorNotes[12], '第十二楼的 要点');
      expect(back.excerpts.single.postNumber, 12);

      // 全部清空 = 删除这条笔记
      await TopicNoteStore.save(
        back.copyWith(floorNotes: const {}, excerpts: const [], text: ''),
      );
      expect(await TopicNoteStore.get(9), isNull);
    });
  });

  group('数据备份', () {
    test('笔记的键不在排除清单里', () {
      expect(DataBackupService.debugShouldBackup('topic_notes_v2'), isTrue);
      expect(DataBackupService.debugShouldBackup('topic_notes_v1'), isTrue);
    });

    test('导出再导入到另一台设备，笔记原样回来', () async {
      SharedPreferences.setMockInitialValues({});
      await TopicNoteStore.save(
        TopicNote(
          topicId: 5,
          title: '备份测试',
          text: '话题级',
          floorNotes: const {2: '二楼'},
          updatedAt: DateTime.now(),
        ),
      );
      final source = await SharedPreferences.getInstance();
      final backup = await DataBackupService.exportData(source);
      // 过一遍 JSON，和真实的文件往返一致
      final restored = jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;
      expect((restored['data'] as Map).containsKey('topic_notes_v2'), isTrue);

      SharedPreferences.setMockInitialValues({});
      final target = await SharedPreferences.getInstance();
      await DataBackupService.importData(target, restored);

      final note = (await TopicNoteStore.get(5))!;
      expect(note.title, '备份测试');
      expect(note.text, '话题级');
      expect(note.floorNotes, {2: '二楼'});
    });
  });
}
