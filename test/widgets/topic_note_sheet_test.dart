import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/storage/topic_note_store.dart';
import 'package:fluxdo/widgets/notes/topic_note_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';

/// 1.0.0 能按楼层记笔记，这个界面不编辑它们，但不能在保存时丢掉。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSheet(WidgetTester tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showTopicNoteSheet(context, topicId: 9, title: '话题'),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('显示楼层笔记，改正文后楼层笔记还在', (tester) async {
    await tester.runAsync(
      () => TopicNoteStore.save(
        TopicNote(
          topicId: 9,
          title: '话题',
          text: '原来的',
          floorNotes: const {12: '十二楼的要点'},
          updatedAt: DateTime(2026),
        ),
      ),
    );

    await openSheet(tester);
    expect(find.text('楼层笔记'), findsOneWidget);
    expect(find.textContaining('十二楼的要点'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '改过的');
    await tester.pump();
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final note = await tester.runAsync(() => TopicNoteStore.get(9));
    expect(note!.text, '改过的');
    expect(note.floorNotes, {12: '十二楼的要点'});
  });

  testWidgets('没有楼层笔记时不显示这一块', (tester) async {
    await openSheet(tester);
    expect(find.text('楼层笔记'), findsNothing);
  });
}
