import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/ai_chat_message_item.dart';

import 'support/ui_harness.dart';

// 0.4.0 收尾 B：AI 回复下的「复制 · 重新生成」行。

AiChatMessage _reply(String content) => AiChatMessage(
  id: 'a1',
  role: ChatRole.assistant,
  content: content,
  createdAt: DateTime(2026, 10, 30),
);

void main() {
  setUpAll(loadUiFonts);

  testUi('最后一条已完成回复显示「重新生成」，点了回调', (tester) async {
    var regenerated = 0;
    await pumpUi(
      tester,
      Scaffold(
        body: AiChatMessageItem(
          message: _reply('从前 20 楼看，大约一半的人拿到了 offer'),
          onCopyText: () {},
          onRegenerate: () => regenerated++,
        ),
      ),
    );
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    await tester.tap(find.text('重新生成'));
    expect(regenerated, 1);
  });

  testUi('不是最后一条时不显示「重新生成」', (tester) async {
    await pumpUi(
      tester,
      Scaffold(
        body: AiChatMessageItem(
          message: _reply('旧回复'),
          onCopyText: () {},
        ),
      ),
    );
    expect(find.text('重新生成'), findsNothing);
  });

  for (final variant in [...UiVariant.portrait, ...UiVariant.landscape]) {
    testUi('回复操作行不溢出（${variant.label}）', (tester) async {
      await pumpUi(
        tester,
        Scaffold(
          body: AiChatMessageItem(
            message: _reply('从前 20 楼看，大约一半的人拿到了 offer'),
            onCopyText: () {},
            onShareAsImage: () {},
            onRegenerate: () {},
          ),
        ),
        variant: variant,
      );
      expectNoUiException(tester);
    });
  }
}
