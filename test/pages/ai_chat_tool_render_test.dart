import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/pages/topic_detail_page/widgets/ai_chat_message_item.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';

// 用过外部工具（MCP）的回答：渲染时不自动加载外站图片、不出网址预览；没用过的原样。

const _content =
    '结果如下：\n\n![图](https://evil.example/a.png)\n\nhttps://evil.example/page\n';

Widget _app(List<String>? notes) => ProviderScope(
  child: TranslationProvider(
    child: MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      home: Scaffold(
        body: AiChatMessageItem(
          message: AiChatMessage(
            id: 'm',
            role: ChatRole.assistant,
            content: _content,
            createdAt: DateTime(2026, 10, 31),
            toolNotes: notes,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('用过工具：交给渲染器的文字里没有图片语法，网址变成链接', (tester) async {
    await tester.pumpWidget(_app(const ['MCP · 文档 · search → 10 字']));
    await tester.pump(const Duration(milliseconds: 100));

    final data = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data;
    expect(data, isNot(contains('![')));
    expect(data, contains('[图片：图](https://evil.example/a.png)'));
    expect(data, contains('[链接：evil.example](https://evil.example/page)'));
    expect(find.byKey(const ValueKey('ai-tool-notes')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('没用过工具：原文原样交给渲染器（行为不变）', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pump(const Duration(milliseconds: 100));

    final data = tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data;
    expect(data, _content);
    expect(find.byKey(const ValueKey('ai-tool-notes')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
