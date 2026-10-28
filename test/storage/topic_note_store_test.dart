import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存、按修改时间排序、空笔记自动删除', () async {
    await TopicNoteStore.save(
      TopicNote(topicId: 1, title: 'A', text: '第一条', updatedAt: DateTime(2026, 1, 1)),
    );
    await TopicNoteStore.save(
      TopicNote(
        topicId: 2,
        title: 'B',
        excerpts: [NoteExcerpt(text: '摘录', createdAt: DateTime(2026, 1, 2))],
        updatedAt: DateTime(2026, 1, 2),
      ),
    );
    final list = await TopicNoteStore.list();
    expect(list.map((n) => n.topicId), [2, 1]);
    expect(list.first.excerpts.single.text, '摘录');
    expect(list.first.searchText, contains('摘录'));

    await TopicNoteStore.save(
      TopicNote(topicId: 1, title: 'A', updatedAt: DateTime(2026, 1, 3)),
    );
    expect(await TopicNoteStore.get(1), isNull);
    await TopicNoteStore.delete(2);
    expect(await TopicNoteStore.list(), isEmpty);
  });
}
