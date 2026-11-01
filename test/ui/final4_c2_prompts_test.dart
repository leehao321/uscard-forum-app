import 'dart:convert';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 补充稿 43 / 44 / 45：快捷词管理（更多菜单、分组卡片、空态）、新建快捷词表单、图标搜索。

const _builtIns = [
  PromptPreset(
    id: 'builtin_image_cover',
    type: PromptType.image,
    name: '封面海报',
    iconRaw: 'image_outlined',
    promptTemplate: 'a',
    aspectRatio: '16:9',
    tags: ['封面'],
    builtIn: true,
    sortOrder: 1,
  ),
  PromptPreset(
    id: 'builtin_image_illustration',
    type: PromptType.image,
    name: '话题插画',
    iconRaw: 'brush_outlined',
    promptTemplate: 'b',
    aspectRatio: '1:1',
    builtIn: true,
    sortOrder: 2,
  ),
  PromptPreset(
    id: 'builtin_text_summary',
    type: PromptType.text,
    name: '总结这个话题',
    iconRaw: 'summarize_outlined',
    promptTemplate: 'c',
    builtIn: true,
    sortOrder: 3,
  ),
  PromptPreset(
    id: 'builtin_text_translate',
    type: PromptType.text,
    name: '翻译主帖',
    iconRaw: 'translate_outlined',
    promptTemplate: 'd',
    builtIn: true,
    sortOrder: 4,
  ),
];

class _Env {
  _Env(this.prefs);

  final SharedPreferences prefs;

  List<Override> get overrides => [
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    builtInPresetsProvider.overrideWithValue(_builtIns),
  ];

  /// 当前持久化的自定义快捷词
  List<Map<String, dynamic>> get userPresets {
    final raw = prefs.getString('ai_prompt_presets_v1');
    if (raw == null) return [];
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final p in (json['userPresets'] as List? ?? const []))
        p as Map<String, dynamic>,
    ];
  }

  List<Map<String, dynamic>> get customizations {
    final raw = prefs.getString('ai_prompt_presets_v1');
    if (raw == null) return [];
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final p in (json['customizations'] as List? ?? const []))
        p as Map<String, dynamic>,
    ];
  }
}

Future<_Env> _env({List<Map<String, dynamic>> userPresets = const []}) async {
  SharedPreferences.setMockInitialValues({
    if (userPresets.isNotEmpty)
      'ai_prompt_presets_v1': jsonEncode({
        'version': 1,
        'customizations': <Object>[],
        'userPresets': userPresets,
      }),
  });
  return _Env(await SharedPreferences.getInstance());
}

Map<String, dynamic> _user(
  String id,
  String name, {
  String type = 'image',
  String icon = 'sparkles',
}) => {
  'id': id,
  'type': type,
  'name': name,
  'iconRaw': icon,
  'promptTemplate': 'tpl',
  'builtIn': false,
  'sortOrder': 1000,
};

Future<void> _openManage(
  WidgetTester tester,
  _Env env, {
  PromptType type = PromptType.image,
}) async {
  await pumpUi(
    tester,
    PromptPresetsPage(initialType: type),
    overrides: env.overrides,
  );
}

Future<void> _openEdit(WidgetTester tester, _Env env, {PromptPreset? preset}) =>
    pumpUi(
      tester,
      PromptPresetEditPage(preset: preset),
      overrides: env.overrides,
    );

Finder _field(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(AppFilledField),
  ),
  matching: find.byType(TextField),
);

/// 图标网格里的格子（按图标名，来自语义标签）
Finder _cell(String name) =>
    find.byWidgetPredicate((w) => w is AppPressable && w.semanticLabel == name);

bool _cellSelected(WidgetTester tester, String name) =>
    tester.widget<AppPressable>(_cell(name)).selected ?? false;

void main() {
  setUpAll(loadUiFonts);

  group('快捷词管理页', () {
    testUi('图像页：分段 + 内置分组卡片，每行拖拽柄 / 图标 / 名称 / 图钉，说明收成一行', (tester) async {
      final env = await _env();
      await _openManage(tester, env);

      expect(find.byType(AppSegmentedControl<int>), findsOneWidget);
      final labels = tester
          .widget<AppSegmentedControl<int>>(find.byType(AppSegmentedControl<int>))
          .segments
          .map((s) => s.label)
          .toList();
      expect(labels, ['图像', '文本']);
      expect(find.text('内置'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      // 图像类内置两条；每行有拖拽柄和图钉
      expect(find.text('封面海报'), findsOneWidget);
      expect(find.text('话题插画'), findsOneWidget);
      expect(find.byIcon(AppIcons.grip), findsNWidgets(2));
      expect(find.byIcon(AppIcons.pushPin), findsNWidgets(2));
      // 比例 / 标签收成一行 13 meta 说明
      expect(find.text('16:9 · 封面'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
      // 内置图标按历史名换成 Lucide：image、brush
      expect(find.byIcon(presetIconData('image_outlined')), findsOneWidget);
      expect(find.byIcon(presetIconData('brush_outlined')), findsOneWidget);
      // 旧样式不再出现
      expect(find.byType(SegmentedButton<PromptType>), findsNothing);
      expect(find.byType(Card), findsNothing);
      expectNoUiException(tester);
    });

    testUi('自定义空态：48 星光图标 + 标题 + 说明', (tester) async {
      final env = await _env();
      await _openManage(tester, env, type: PromptType.text);

      expect(find.byType(AppStateView), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == AppIcons.sparkles && w.size == 48,
        ),
        findsOneWidget,
      );
      expect(find.text('还没有自定义快捷词'), findsOneWidget);
      expect(find.text('点右上角 + 新建，或从剪贴板导入'), findsOneWidget);
    });

    testUi('切到「文本」只显示文本类；有自定义时空态消失', (tester) async {
      final env = await _env(userPresets: [_user('u1', '我的提问', type: 'text')]);
      await _openManage(tester, env);

      expect(find.text('封面海报'), findsOneWidget);
      expect(find.text('我的提问'), findsNothing);
      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();
      expect(find.text('封面海报'), findsNothing);
      expect(find.text('总结这个话题'), findsOneWidget);
      expect(find.text('翻译主帖'), findsOneWidget);
      expect(find.text('我的提问'), findsOneWidget);
      expect(find.byType(AppStateView), findsNothing);
    });

    testUi('右上 ⋯ 菜单：没有自定义时只有「从剪贴板导入」和「恢复内置默认」', (tester) async {
      final env = await _env();
      await _openManage(tester, env);
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();

      expect(find.byType(AppMenuPanel<String>), findsOneWidget);
      expect(find.text('从剪贴板导入'), findsOneWidget);
      expect(find.text('恢复内置默认'), findsOneWidget);
      expect(find.text('导出全部自定义'), findsNothing);
      expect(find.byIcon(AppIcons.paste), findsOneWidget);
      expect(find.byIcon(AppIcons.restartAlt), findsOneWidget);
      expectNoUiException(tester);
    });

    testUi('⋯ 菜单：有自定义时多出「导出全部自定义」，点它把 JSON 放进剪贴板', (tester) async {
      final env = await _env(userPresets: [_user('u1', '手绘小报')]);
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _openManage(tester, env);
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      expect(find.text('导出全部自定义'), findsOneWidget);
      await tester.tap(find.text('导出全部自定义'));
      await tester.pumpAndSettle();
      expect(clip, isNotNull);
      final exported = jsonDecode(clip!) as Map<String, dynamic>;
      expect((exported['presets'] as List).single['name'], '手绘小报');
    });

    testUi('⋯ › 恢复内置默认：先确认，确认后清掉内置项的置顶，取消则保留', (tester) async {
      final env = await _env();
      await _openManage(tester, env);

      // 先把「封面海报」置顶
      await tester.tap(find.byIcon(AppIcons.pushPin).first);
      await tester.pumpAndSettle();
      expect(env.customizations.single['pinned'], true);

      // 取消：仍然置顶
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复内置默认'));
      await tester.pumpAndSettle();
      expect(find.byType(AppAlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(env.customizations.single['pinned'], true);

      // 确认：customization 清空
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复内置默认'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppAlertDialog),
          matching: find.text('恢复内置默认'),
        ),
      );
      await tester.pumpAndSettle();
      expect(env.customizations, isEmpty);
    });

    testUi('⋯ › 从剪贴板导入：预览确认后加入自定义，取消不加入，空剪贴板给提示', (tester) async {
      final env = await _env();
      String? clipboard = jsonEncode({
        'version': 1,
        'presets': [
          {
            // 导入按 fromJson 解析，id 必须有（导出的 JSON 里没有 id，见报告）
            'id': 'imp-1',
            'type': 'image',
            'name': '导入的快捷词',
            'iconRaw': 'heart',
            'promptTemplate': '导入模板',
          },
        ],
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final toasts = <String>[];
      AiToastDelegate.configure(
        (m, {type = AiToastType.info}) => toasts.add(m),
      );

      await _openManage(tester, env);

      // 取消：不加入
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入'));
      await tester.pumpAndSettle();
      expect(find.text('即将导入以下快捷词'), findsOneWidget);
      expect(find.text('导入的快捷词'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(env.userPresets, isEmpty);

      // 确认：加入
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();
      expect(env.userPresets.single['name'], '导入的快捷词');
      expect(env.userPresets.single['builtIn'], false);
      // 自定义分组出现这一行，空态消失
      expect(find.text('导入的快捷词'), findsOneWidget);
      expect(find.byType(AppStateView), findsNothing);

      // 剪贴板为空：只提示，不弹预览
      clipboard = null;
      toasts.clear();
      await tester.tap(find.byIcon(AppIcons.moreHoriz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入'));
      await tester.pumpAndSettle();
      expect(find.text('即将导入以下快捷词'), findsNothing);
      expect(toasts, isNotEmpty);
    });

    testUi('点图钉切换置顶并保存；自定义行点开进编辑页', (tester) async {
      final env = await _env(userPresets: [_user('u1', '手绘小报')]);
      await _openManage(tester, env);

      // 自定义的图钉（第三个：内置两个在前）
      await tester.tap(find.byIcon(AppIcons.pushPin).last);
      await tester.pumpAndSettle();
      expect(env.userPresets.single['pinned'], true);
      await tester.tap(find.byIcon(AppIcons.pushPin).last);
      await tester.pumpAndSettle();
      expect(env.userPresets.single['pinned'], false);

      await tester.tap(find.text('手绘小报'));
      await tester.pumpAndSettle();
      expect(find.text('编辑快捷词'), findsOneWidget);
    });

    testUi('拖拽柄可以调整同组顺序', (tester) async {
      final env = await _env();
      await _openManage(tester, env);

      final first = find.text('封面海报');
      final second = find.text('话题插画');
      expect(
        tester.getTopLeft(first).dy < tester.getTopLeft(second).dy,
        isTrue,
      );
      // 第一行的拖拽柄往下拖过第二行
      final grip = find.byIcon(AppIcons.grip).first;
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('封面海报')).dy >
            tester.getTopLeft(find.text('话题插画')).dy,
        isTrue,
      );
    });

    testUi('左滑删除自定义：先确认，确认后删除', (tester) async {
      final env = await _env(userPresets: [_user('u1', '手绘小报')]);
      await _openManage(tester, env);

      await tester.drag(find.text('手绘小报'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确定删除快捷词「手绘小报」吗？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(env.userPresets, hasLength(1));

      await tester.drag(find.text('手绘小报'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppDialogAction, '删除'));
      await tester.pumpAndSettle();
      expect(env.userPresets, isEmpty);
      expect(find.byType(AppStateView), findsOneWidget);
    });
  });

  group('新建 / 编辑快捷词', () {
    testUi('新建表单：分段（图像 / 文本）、带标签的填充输入框、18 个图标、右上保存', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);

      expect(find.text('新建快捷词'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(
        tester
            .widget<AppSegmentedControl<int>>(find.byType(AppSegmentedControl<int>))
            .segments
            .map((s) => s.label),
        ['图像', '文本'],
      );
      // 名称 / Prompt 模板 / 标签三个填充输入框，标签在框上方
      expect(find.byType(AppFilledField), findsNWidgets(3));
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('Prompt 模板'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      // 图标：默认 sparkles，已选行 + 18 个格子，选中项是 sparkles
      expect(find.text('已选：sparkles'), findsOneWidget);
      for (final name in kPresetIconGrid) {
        expect(_cell(name), findsOneWidget, reason: name);
      }
      expect(_cellSelected(tester, 'sparkles'), isTrue);
      expect(_cellSelected(tester, 'heart'), isFalse);
      // 已经没有「图标 / Emoji」标签页
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Emoji'), findsNothing);
      // 图像类才有默认比例
      expect(find.text('默认比例'), findsOneWidget);
      expectNoUiException(tester);
    });

    testUi('点图标格子：已选行和高亮跟着变，保存后写入 iconRaw', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);

      await tester.tap(_cell('heart'));
      await tester.pumpAndSettle();
      expect(find.text('已选：heart'), findsOneWidget);
      expect(_cellSelected(tester, 'heart'), isTrue);
      expect(_cellSelected(tester, 'sparkles'), isFalse);

      await tester.enterText(_field('名称'), '手绘小报');
      await tester.enterText(_field('Prompt 模板'), '画一张 {title}');
      await tester.enterText(_field('标签'), '手绘, 信息图 ,');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final saved = env.userPresets.single;
      expect(saved['name'], '手绘小报');
      expect(saved['iconRaw'], 'heart');
      expect(saved['promptTemplate'], '画一张 {title}');
      expect(saved['type'], 'image');
      expect(saved['tags'], ['手绘', '信息图']);
    });

    testUi('切到「文本」：类型改成文本，默认比例分组消失，保存带上类型', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);

      await tester.tap(find.text('文本'));
      await tester.pumpAndSettle();
      expect(find.text('默认比例'), findsNothing);
      await tester.enterText(_field('名称'), '提问');
      await tester.enterText(_field('Prompt 模板'), '总结 {title}');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(env.userPresets.single['type'], 'text');
    });

    testUi('名称或模板为空：保存被拦下，显示提示，不写入', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入名称'), findsOneWidget);
      expect(find.text('请输入 prompt 模板'), findsOneWidget);
      expect(env.userPresets, isEmpty);

      await tester.enterText(_field('名称'), '只有名称');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入名称'), findsNothing);
      expect(find.text('请输入 prompt 模板'), findsOneWidget);
      expect(env.userPresets, isEmpty);
    });

    testUi('搜索图标：按英文名过滤，选中项描边高亮，Emoji 标签页已删除', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);

      // 默认不显示搜索框；点放大镜打开
      expect(find.byType(AppFilledField), findsNWidgets(3));
      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();
      expect(find.byType(AppFilledField), findsNWidgets(4));
      expect(find.text('按英文名搜索图标'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'heart');
      await tester.pumpAndSettle();
      // 结果是名字里带 heart 的图标，完全相同的排第一
      final expected = searchLucideIconNames('heart');
      expect(expected.first, 'heart');
      expect(expected.every((n) => n.contains('heart')), isTrue);
      expect(expected.length, greaterThan(5));
      for (final name in expected.take(8)) {
        expect(_cell(name), findsOneWidget, reason: name);
      }
      // 不在结果里的图标格子消失（默认网格里的 camera 不含 heart）
      expect(_cell('camera'), findsNothing);
      // 搜索时「已选」行收起，说明文字出现
      expect(find.text('已选：sparkles'), findsNothing);
      expect(find.text('不提供 Emoji：图标统一用线性图标，可按英文名搜索常用图标。'), findsOneWidget);

      // 选中搜索结果里的 heart-handshake：高亮、保存后写入
      await tester.tap(_cell('heart-handshake'));
      await tester.pumpAndSettle();
      expect(_cellSelected(tester, 'heart-handshake'), isTrue);
      expect(_cellSelected(tester, 'heart'), isFalse);

      // 清除搜索：回到默认 18 格，已选行显示新图标
      await tester.tap(find.byIcon(AppIcons.cancelCircle));
      await tester.pumpAndSettle();
      expect(find.text('已选：heart-handshake'), findsOneWidget);
      expect(_cell('camera'), findsOneWidget);

      await tester.enterText(_field('名称'), 'x');
      await tester.enterText(_field('Prompt 模板'), 'y');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(env.userPresets.single['iconRaw'], 'heart-handshake');
    });

    testUi('搜索：大小写与空格不敏感，查不到时提示，再点放大镜收起并清空', (tester) async {
      final env = await _env();
      await _openEdit(tester, env);
      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '  HEART Pulse ');
      await tester.pumpAndSettle();
      expect(_cell('heart-pulse'), findsOneWidget);
      expect(_cell('heart'), findsNothing);

      await tester.enterText(find.byType(TextField).at(1), 'zzzzqqqq');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的图标'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.search).first);
      await tester.pumpAndSettle();
      expect(find.byType(AppFilledField), findsNWidgets(3));
      expect(find.text('没有匹配的图标'), findsNothing);
      expect(_cell('camera'), findsOneWidget);
    });

    testUi('编辑旧的自定义快捷词：Material 图标名按对应 Lucide 图标高亮', (tester) async {
      final env = await _env(
        userPresets: [_user('u1', '旧快捷词', icon: 'translate_outlined')],
      );
      await _openEdit(
        tester,
        env,
        preset: PromptPreset.fromJson(env.userPresets.single),
      );
      expect(find.text('编辑快捷词'), findsOneWidget);
      expect(find.text('已选：languages'), findsOneWidget);
      expect(_cellSelected(tester, 'languages'), isTrue);

      // 不改图标直接保存：iconRaw 保持原样，不被悄悄改写
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(env.userPresets.single['iconRaw'], 'translate_outlined');
    });

    testUi('编辑内置快捷词：名称、模板、标签、类型不可改，图标只读展示', (tester) async {
      final env = await _env();
      await _openEdit(tester, env, preset: _builtIns.first);

      expect(find.byType(PresetIconPicker), findsNothing);
      expect(find.text('已选：image'), findsOneWidget);
      for (final f in tester.widgetList<AppFilledField>(
        find.byType(AppFilledField),
      )) {
        expect(f.enabled, isFalse);
      }
      // 类型分段点不动
      expect(
        tester
            .widget<AppSegmentedControl<int>>(find.byType(AppSegmentedControl<int>))
            .onChanged,
        isNull,
      );
    });
  });

  group('图标名与搜索（纯逻辑）', () {
    test('默认网格的 18 个图标都在目录里', () {
      expect(kPresetIconGrid, hasLength(18));
      for (final name in kPresetIconGrid) {
        expect(lucideIconByName(name), isNotNull, reason: name);
      }
    });

    test('历史 Material 图标名都能换成目录里的 Lucide 图标', () {
      for (final entry in kLegacyPresetIconNames.entries) {
        expect(
          lucideIconByName(entry.value),
          isNotNull,
          reason: '${entry.key} -> ${entry.value}',
        );
      }
      expect(presetLucideName('auto_awesome_outlined'), 'sparkles');
      expect(presetLucideName('heart'), 'heart');
      expect(presetLucideName('🎨'), isNull);
      expect(presetLucideName('no-such-icon-xyz'), isNull);
      // 认不出来的名字渲染成 sparkles
      expect(presetIconData('no-such-icon-xyz'), presetIconData('sparkles'));
    });

    test('搜索：完全匹配 → 前缀 → 包含，空词返回空，limit 生效', () {
      expect(searchLucideIconNames(''), isEmpty);
      expect(searchLucideIconNames('   '), isEmpty);
      final r = searchLucideIconNames('heart');
      expect(r.first, 'heart');
      // 前缀档（heart-xxx）在包含档（book-heart 等）之前
      expect(r.indexOf('heart-crack') < r.indexOf('hand-heart'), isTrue);
      expect(searchLucideIconNames('heart', limit: 3), hasLength(3));
      expect(searchLucideIconNames('HEART'), r);
      expect(searchLucideIconNames('heart pulse').first, 'heart-pulse');
      expect(searchLucideIconNames('zzzzqqqq'), isEmpty);
    });
  });
}
