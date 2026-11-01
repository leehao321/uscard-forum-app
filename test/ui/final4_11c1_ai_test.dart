import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 第 11 批 · 11c-1（补充稿 39 / 40 / 41 / 42）：AI 会话记录空态、快捷词管理、高级设置。
// 数据全在 SharedPreferences 的 mock 里，不请求任何模型服务。

/// 图像快捷词：比例和标签会收成一行说明
const _imagePresets = [
  PromptPreset(
    id: 'img_a',
    type: PromptType.image,
    name: '示例图像甲',
    iconRaw: 'image_outlined',
    promptTemplate: 't',
    aspectRatio: '16:9',
    tags: ['封面'],
    sortOrder: 0,
    builtIn: true,
  ),
  PromptPreset(
    id: 'img_b',
    type: PromptType.image,
    name: '示例图像乙',
    iconRaw: 'brush_outlined',
    promptTemplate: 't',
    aspectRatio: '1:1',
    sortOrder: 1,
    builtIn: true,
  ),
  PromptPreset(
    id: 'img_c',
    type: PromptType.image,
    name: '示例图像丙',
    iconRaw: 'emoji_emotions_outlined',
    promptTemplate: 't',
    aspectRatio: '4:3',
    tags: ['漫画', '幽默'],
    sortOrder: 2,
    builtIn: true,
  ),
];

const _textPresets = [
  PromptPreset(
    id: 'txt_a',
    type: PromptType.text,
    name: '示例文本甲',
    iconRaw: 'summarize_outlined',
    promptTemplate: 't',
    sortOrder: 0,
    builtIn: true,
  ),
  PromptPreset(
    id: 'txt_b',
    type: PromptType.text,
    name: '示例文本乙',
    iconRaw: 'translate_outlined',
    promptTemplate: 't',
    sortOrder: 1,
    builtIn: true,
  ),
];

Future<(SharedPreferences, List<Override>)> _aiStore({
  Map<String, Object> values = const {},
  List<PromptPreset> builtIns = const [],
  bool withAdapter = true,
}) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return (
    prefs,
    <Override>[
      aiSharedPreferencesProvider.overrideWithValue(prefs),
      builtInPresetsProvider.overrideWithValue(builtIns),
      if (withAdapter)
        aiDioAdapterFactoryProvider.overrideWithValue(IOHttpClientAdapter.new),
    ],
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  setUpAll(loadUiFonts);

  group('39 AI · 会话记录 · 空', () {
    testUi('空态：48 图标 + 标题 + 说明，没有清空按钮', (tester) async {
      final (_, overrides) = await _aiStore();
      await pumpUi(tester, const AiChatHistoryPage(), overrides: overrides);
      expect(find.text('会话记录'), findsOneWidget);
      expect(find.text('暂无会话记录'), findsOneWidget);
      expect(find.text('和 AI 助手的对话会保存在这里'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.chatBubble));
      expect(icon.size, 48);
      // 没有记录时导航右上不放「清除所有对话」
      expect(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.byIcon(AppIcons.delete),
        ),
        findsNothing,
      );
      expectNoUiException(tester);
    });

    testUi('有记录时不显示空态，右上出现清除；清除后回到空态', (tester) async {
      final (prefs, overrides) = await _aiStore();
      await AiChatStorageService(prefs).saveSessionMessages(1, 's1', [
        AiChatMessage(
          id: 'm1',
          role: ChatRole.user,
          content: '你好',
          createdAt: DateTime(2026, 10, 30),
        ),
      ], topicTitle: '示例话题');
      await pumpUi(tester, const AiChatHistoryPage(), overrides: overrides);
      expect(find.text('示例话题'), findsOneWidget);
      expect(find.text('暂无会话记录'), findsNothing);

      final clear = find.descendant(
        of: find.byType(AppNavBar),
        matching: find.byIcon(AppIcons.delete),
      );
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除全部'));
      await tester.pumpAndSettle();
      expect(find.text('暂无会话记录'), findsOneWidget);
      expect(find.text('和 AI 助手的对话会保存在这里'), findsOneWidget);
    });
  });

  group('40 / 41 AI · 快捷词管理', () {
    Future<void> openPresets(
      WidgetTester tester,
      List<Override> overrides, {
      PromptType type = PromptType.image,
    }) async {
      await pumpUi(
        tester,
        PromptPresetsPage(initialType: type),
        overrides: overrides,
      );
    }

    testUi('图像：分段「图像 / 文本」，内置分组按排序列出，自定义为空时给一句说明', (tester) async {
      final (_, overrides) = await _aiStore(
        builtIns: [..._imagePresets, ..._textPresets],
      );
      await openPresets(tester, overrides);
      final seg = tester.widget<AppSegmented>(find.byType(AppSegmented));
      expect(seg.labels, ['图像', '文本']);
      expect(seg.selectedIndex, 0);
      expect(find.text('快捷词管理'), findsOneWidget);
      expect(find.text('内置'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(find.text('还没有自定义快捷词，点右上角 + 添加'), findsOneWidget);
      // 三条图像快捷词，顺序 甲 乙 丙；文本快捷词不在这一页
      final tops = [
        for (final n in ['示例图像甲', '示例图像乙', '示例图像丙'])
          tester.getTopLeft(find.text(n)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.text('示例文本甲'), findsNothing);
      expectNoUiException(tester);
    });

    testUi('图像：比例和标签收成一行 13 号说明，不再是一排 chips', (tester) async {
      final (_, overrides) = await _aiStore(builtIns: _imagePresets);
      await openPresets(tester, overrides);
      expect(find.text('16:9 · 封面'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
      expect(find.text('4:3 · 漫画 · 幽默'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('4:3 · 漫画 · 幽默')).style?.fontSize,
        13,
      );
      expect(find.byType(Chip), findsNothing);
    });

    testUi('点「文本」切到文本快捷词：同一套行、没有说明行', (tester) async {
      final (_, overrides) = await _aiStore(
        builtIns: [..._imagePresets, ..._textPresets],
      );
      await openPresets(tester, overrides);
      await tester.tap(find.text('文本'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<AppSegmented>(find.byType(AppSegmented)).selectedIndex,
        1,
      );
      expect(find.text('示例文本甲'), findsOneWidget);
      expect(find.text('示例文本乙'), findsOneWidget);
      expect(find.text('示例图像甲'), findsNothing);
      // 每行都有拖拽把手和图钉
      expect(find.byIcon(AppIcons.grip), findsNWidgets(2));
      expect(find.byIcon(AppIcons.pushPin), findsNWidgets(2));
    });

    testUi('图钉：点一下置顶，再点取消；颜色和朗读标签跟着变，状态进存储', (tester) async {
      final (prefs, overrides) = await _aiStore(builtIns: _imagePresets);
      await openPresets(tester, overrides);
      final colors = tester
          .element(find.byType(PromptPresetsPage))
          .tokens
          .colors;
      Finder pin(String label) => find.byWidgetPredicate(
        (w) => w is AppIconButton && w.semanticLabel == label,
      );
      expect(pin(AiL10n.current.quickPromptsPin), findsNWidgets(3));
      expect(
        tester.widget<Icon>(find.byIcon(AppIcons.pushPin).first).color,
        colors.textMeta,
      );

      await tester.tap(pin(AiL10n.current.quickPromptsPin).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(pin(AiL10n.current.quickPromptsUnpin), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(AppIcons.pushPin).first).color,
        colors.brandPrimary,
      );
      var list = _container(tester).read(promptPresetListProvider);
      expect(list.firstWhere((p) => p.id == 'img_a').pinned, isTrue);
      expect(prefs.getString('ai_prompt_presets_v1'), contains('img_a'));

      await tester.tap(pin(AiL10n.current.quickPromptsUnpin));
      await tester.pump(const Duration(milliseconds: 300));
      list = _container(tester).read(promptPresetListProvider);
      expect(list.firstWhere((p) => p.id == 'img_a').pinned, isFalse);
    });

    testUi('拖动 grip 排序：把第一条拖到最后，顺序写进存储', (tester) async {
      final (prefs, overrides) = await _aiStore(builtIns: _imagePresets);
      await openPresets(tester, overrides);
      await tester.timedDrag(
        find.byIcon(AppIcons.grip).first,
        const Offset(0, 200),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      final ordered = _container(tester)
          .read(promptPresetsByTypeProvider(PromptType.image))
          .map((p) => p.id)
          .toList();
      expect(ordered, ['img_b', 'img_c', 'img_a']);
      expect(prefs.getString('ai_prompt_presets_v1'), isNotNull);
    });

    testUi('自定义分组：自己建的快捷词在「自定义」下，点行进编辑页', (tester) async {
      final custom = const PromptPreset(
        id: 'mine',
        type: PromptType.image,
        name: '我的示例词',
        iconRaw: 'brush_outlined',
        promptTemplate: 't',
        aspectRatio: '3:4',
      ).toJson();
      final (_, overrides) = await _aiStore(
        builtIns: _imagePresets,
        values: {
          'ai_prompt_presets_v1': jsonEncode({
            'version': 1,
            'customizations': [],
            'userPresets': [custom],
          }),
        },
      );
      await openPresets(tester, overrides);
      expect(find.text('我的示例词'), findsOneWidget);
      expect(find.text('3:4'), findsOneWidget);
      expect(find.text('还没有自定义快捷词，点右上角 + 添加'), findsNothing);
      // 内置在上、自定义在下
      expect(
        tester.getTopLeft(find.text('示例图像甲')).dy,
        lessThan(tester.getTopLeft(find.text('我的示例词')).dy),
      );

      await tester.tap(find.text('我的示例词'));
      await tester.pumpAndSettle();
      expect(find.byType(PromptPresetEditPage), findsOneWidget);
    });

    testUi('右上 + 新建：打开编辑页', (tester) async {
      final (_, overrides) = await _aiStore(builtIns: _imagePresets);
      await openPresets(tester, overrides);
      await tester.tap(find.byIcon(AppIcons.add));
      await tester.pumpAndSettle();
      expect(find.byType(PromptPresetEditPage), findsOneWidget);
    });
  });

  group('42 AI · 高级设置', () {
    Finder switchTile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(SwitchListTile),
    );

    bool tileValue(WidgetTester tester, String title) =>
        tester.widget<SwitchListTile>(switchTile(title)).value;

    testUi('两条开关 + 页脚说明，默认都是关闭', (tester) async {
      final (_, overrides) = await _aiStore();
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      expect(find.text('高级设置'), findsOneWidget);
      expect(find.text('跟随应用网络配置'), findsOneWidget);
      expect(find.text('AI 请求使用应用的代理等网络设置'), findsOneWidget);
      expect(find.text('图像生成渐进帧'), findsOneWidget);
      expect(find.text('先返回模糊预览图，再返回最终图'), findsOneWidget);
      expect(
        find.text(
          '图像生成渐进帧仅支持 gpt-image 系列，需要 OpenAI 已验证 organization；未验证的账号开启后会生成失败。',
        ),
        findsOneWidget,
      );
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(tileValue(tester, '图像生成渐进帧'), isFalse);
      expectNoUiException(tester);
    });

    testUi('切换开关：状态翻转并写进存储，再切回关闭', (tester) async {
      final (prefs, overrides) = await _aiStore();
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );

      await tester.tap(switchTile('图像生成渐进帧'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '图像生成渐进帧'), isTrue);
      expect(prefs.getBool('ai_partial_images'), isTrue);
      // 另一条不受影响
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(prefs.getBool('ai_use_app_network'), isNull);

      await tester.tap(switchTile('跟随应用网络配置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '跟随应用网络配置'), isTrue);
      expect(prefs.getBool('ai_use_app_network'), isTrue);

      await tester.tap(switchTile('图像生成渐进帧'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '图像生成渐进帧'), isFalse);
      expect(prefs.getBool('ai_partial_images'), isFalse);
    });

    testUi('存储里已开启的开关，进页面就是开着的', (tester) async {
      final (_, overrides) = await _aiStore(
        values: {'ai_use_app_network': true, 'ai_partial_images': true},
      );
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      expect(tileValue(tester, '跟随应用网络配置'), isTrue);
      expect(tileValue(tester, '图像生成渐进帧'), isTrue);
    });

    testUi('应用没有提供网络适配器时，「跟随应用网络配置」点不动', (tester) async {
      final (prefs, overrides) = await _aiStore(withAdapter: false);
      await pumpUi(
        tester,
        const AiAdvancedSettingsPage(),
        overrides: overrides,
      );
      await tester.tap(switchTile('跟随应用网络配置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tileValue(tester, '跟随应用网络配置'), isFalse);
      expect(prefs.getBool('ai_use_app_network'), isNull);
    });
  });
}
