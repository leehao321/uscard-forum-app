import 'dart:async';
import 'dart:io';

import 'package:ai_model_manager/ai_model_manager.dart'
    show aiSharedPreferencesProvider;
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/appearance_page.dart';
import 'package:fluxdo/widgets/settings/appearance_widgets.dart';
import 'package:fluxdo/pages/bottom_nav_settings_page.dart';
import 'package:fluxdo/pages/diagnostics_page.dart';
import 'package:fluxdo/pages/font_settings_page.dart';
import 'package:fluxdo/pages/settings_page.dart';
import 'package:fluxdo/providers/appearance_provider.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/user_content_providers.dart' show currentUsernameProvider;
import 'package:fluxdo/services/font_import_service.dart';
import 'package:fluxdo/settings/search/settings_search_index.dart';
import 'package:fluxdo/settings/settings_model.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

// 0.4.0 M8：设置首页与搜索、外观（预设 / 微调）、字体导入、标签栏、诊断。
// 不请求论坛；字体导入用临时目录。

class _FakeUser extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Future<List<Override>> _overrides([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiSharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWith(_FakeUser.new),
    // 用户名不走真站（Notion 配置按账号存，会去取用户名）
    currentUsernameProvider.overrideWith((ref) async => null),
  ];
}

void main() {
  setUpAll(loadUiFonts);

  group('设置首页', () {
    for (final variant in [
      ...UiVariant.portrait,
      ...UiVariant.landscape,
    ]) {
      testUi('不溢出、可访问（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const SettingsPage(),
          variant: variant,
          overrides: await _overrides(),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        expect(find.text('显示与阅读'), findsOneWidget);
        expect(find.text('外观'), findsOneWidget);
        // 外观行右侧显示当前预设
        expect(find.text('默认'), findsOneWidget);
        await expectUiAccessibility(tester, textContrast: false);
      });
    }

    testUi('搜索：结果带路径，命中字 brand，可取消', (tester) async {
      await pumpUi(
        tester,
        const SettingsPage(),
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), '字体');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('个结果'), findsOneWidget);
      // 路径「外观 › 字体」
      expect(find.text('外观 › 字体'), findsWidgets);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('个结果'), findsNothing);
      expect(find.text('显示与阅读'), findsOneWidget);
    });

    testUi('搜索无结果给一句人话', (tester) async {
      await pumpUi(
        tester,
        const SettingsPage(),
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), 'zzzzqq');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('未找到匹配的设置项'), findsOneWidget);
    });
  });

  group('外观', () {
    for (final variant in [
      ...UiVariant.portrait,
      ...UiVariant.landscape,
    ]) {
      testUi('预览卡固定在顶部，不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const AppearancePage(),
          variant: variant,
          overrides: await _overrides(),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        expect(find.text('实时预览'), findsOneWidget);
        // 滚到底，预览仍在
        final list = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(list).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 300));
        expectNoUiException(tester);
        expect(find.text('实时预览'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    // Figma 55:3077（393）：预览卡 351 宽、预设格高 57、强调色块 36
    testUi('393 宽：预览卡、预设格、强调色块尺寸对上 Figma', (tester) async {
      await pumpUi(
        tester,
        const AppearancePage(),
        variant: const UiVariant(Brightness.light, 1, UiDevice.pro),
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expectNoUiException(tester);
      // 外边距 8 + 卡 208.5；卡宽 = 393 − 2×20
      final card = tester.getSize(find.byType(AppearancePreviewCard));
      expect(card.height, closeTo(216.5, 1.5));
      final box = tester.getSize(
        find.descendant(
          of: find.byType(AppearancePreviewCard),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      expect(box.width, closeTo(353, 1));
      final grid = tester.getSize(find.byType(AppearancePresetGrid));
      expect(grid.height, closeTo(57, 1));
      final accent = tester.getSize(find.byType(AppearanceAccentRow));
      expect(accent.height, closeTo(77, 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testUi('预设：点「紧凑」套用档位，预览卡右上角跟着变', (tester) async {
      final container = ProviderContainer(overrides: await _overrides());
      addTearDown(container.dispose);
      await pumpUi(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const AppearancePage(),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('紧凑').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(appearanceProvider),
        AppearancePreset.compact.tiers,
      );
      expect(find.text('紧凑'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testUi('微调变成自定义，「恢复默认」回到标准', (tester) async {
      final container = ProviderContainer(overrides: await _overrides());
      addTearDown(container.dispose);
      await container
          .read(appearanceProvider.notifier)
          .setTiers(const AppearanceTiers(font: FontTier.large));
      await pumpUi(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const AppearancePage(),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('自定义'), findsWidgets);
      await tester.ensureVisible(find.text('恢复默认'));
      await tester.tap(find.text('恢复默认'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(appearanceProvider), const AppearanceTiers());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    test('预设与档位组合互相对得上', () {
      for (final preset in AppearancePreset.values) {
        expect(AppearancePreset.match(preset.tiers), preset);
      }
      expect(
        AppearancePreset.match(const AppearanceTiers(font: FontTier.large)),
        isNull,
      );
    });
  });

  group('字体导入', () {
    late Directory tmp;
    late PathProviderPlatform original;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('font_test_');
      original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      SharedPreferences.setMockInitialValues({});
      FontImportService.instance.resetForTest();
    });

    tearDown(() async {
      PathProviderPlatform.instance = original;
      FontImportService.instance.resetForTest();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('魔数：ttf / otf / ttc 通过，其他不通过', () {
      expect(FontImportService.hasFontMagic([0, 1, 0, 0]), isTrue);
      expect(FontImportService.hasFontMagic('OTTO'.codeUnits), isTrue);
      expect(FontImportService.hasFontMagic('ttcf'.codeUnits), isTrue);
      expect(FontImportService.hasFontMagic('true'.codeUnits), isTrue);
      expect(FontImportService.hasFontMagic('%PDF'.codeUnits), isFalse);
      expect(FontImportService.hasFontMagic([0, 1]), isFalse);
    });

    test('不是字体：扩展名不对、文件头不对都给 notAFont，不崩', () async {
      final pdf = File(p.join(tmp.path, 'readme.pdf'))
        ..writeAsBytesSync('%PDF-1.4'.codeUnits);
      final fake = File(p.join(tmp.path, 'fake.ttf'))
        ..writeAsBytesSync('this is not a font'.codeUnits);
      for (final f in [pdf, fake]) {
        await expectLater(
          FontImportService.instance.import(f.path),
          throwsA(
            isA<FontImportException>().having(
              (e) => e.failure,
              'failure',
              FontImportFailure.notAFont,
            ),
          ),
        );
      }
      expect(FontImportService.instance.fonts.value, isEmpty);
    });

    test('导入真字体：复制、注册、记入索引；删除后文件和索引都没了', () async {
      final source = File('assets/fonts/MiSansVF.ttf');
      final progress = <int>[];
      final font = await FontImportService.instance.import(
        source.path,
        onProgress: (done, total) => progress.add(done),
      );
      expect(font.fileName, 'MiSansVF.ttf');
      expect(font.size, source.lengthSync());
      expect(font.isCollection, isFalse);
      expect(progress, isNotEmpty);
      expect(progress.last, source.lengthSync());
      expect(FontImportService.instance.fonts.value, [font]);
      final copied = await FontImportService.instance.fileOf(font);
      expect(copied.existsSync(), isTrue);

      await FontImportService.instance.delete(font.id);
      expect(copied.existsSync(), isFalse);
      expect(FontImportService.instance.fonts.value, isEmpty);
    });

    test('取消：不留下半截文件', () async {
      final token = FontImportCancelToken()..cancel();
      await expectLater(
        FontImportService.instance.import(
          'assets/fonts/MiSansVF.ttf',
          cancel: token,
        ),
        throwsA(
          isA<FontImportException>().having(
            (e) => e.failure,
            'failure',
            FontImportFailure.cancelled,
          ),
        ),
      );
      final dir = Directory(p.join(tmp.path, 'fonts'));
      expect(dir.existsSync() ? dir.listSync() : [], isEmpty);
    });

    testUi('字体页：坏文件给 Toast 句子，不崩；导入后出现在列表并可删除', (tester) async {
      final bad = File(p.join(tmp.path, 'readme.pdf'))
        ..writeAsBytesSync('%PDF'.codeUnits);
      var next = bad.path;
      await pumpUi(
        tester,
        FontSettingsPage(pickFile: () async => next),
        overrides: await _overrides(),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('导入字体文件'));
      await tester.pump(const Duration(milliseconds: 500));
      expectNoUiException(tester);
      expect(FontImportService.instance.fonts.value, isEmpty);
      await tester.pump(const Duration(seconds: 5));

      next = File('assets/fonts/MiSansVF.ttf').absolute.path;
      await tester.runAsync(() async {
        await tester.tap(find.text('导入字体文件'));
        await Future<void>.delayed(const Duration(milliseconds: 3000));
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(FontImportService.instance.fonts.value, hasLength(1));
      expect(find.text('已导入的字体'), findsOneWidget);
      expect(find.textContaining('MiSansVF.ttf'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('标签栏 · 诊断', () {
    for (final variant in [
      UiVariant.lightDefault,
      const UiVariant(Brightness.dark, 1.3, UiDevice.pro),
      ...UiVariant.landscape,
    ]) {
      testUi('标签栏设置不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const BottomNavSettingsPage(),
          variant: variant,
          overrides: await _overrides(),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        expect(find.textContaining('按住拖动排序', skipOffstage: false), findsOneWidget);
        expect(find.textContaining('最多 4 个标签', skipOffstage: false), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testUi('诊断页不溢出（${variant.label}）', (tester) async {
        await pumpUi(
          tester,
          const DiagnosticsPage(),
          variant: variant,
          overrides: await _overrides(),
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expectNoUiException(tester);
        expect(find.text('发给开发者', skipOffstage: false), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  group('设置搜索索引', () {
    testUi('覆盖各设置页，路径是「页 › 组」，id 唯一', (tester) async {
      late List<SettingsSearchResult> index;
      await pumpUi(
        tester,
        Builder(
          builder: (context) {
            index = buildSearchIndex(context);
            return const SizedBox();
          },
        ),
        overrides: await _overrides(),
      );
      expect(index, isNotEmpty);
      final categories = {for (final r in index) r.categoryName};
      expect(
        categories,
        containsAll(['外观', '阅读', '功能', '标签栏', '网络与代理', '数据管理', '诊断']),
      );
      for (final r in index) {
        expect(r.model.id, isNotEmpty);
        expect(r.path, startsWith(r.categoryName), reason: r.model.id);
      }
      // 同一页内 id 不重复（搜索定位靠 id）
      final seen = <String>{};
      for (final r in index) {
        expect(
          seen.add('${r.categoryName}/${r.model.id}'),
          isTrue,
          reason: '${r.categoryName}/${r.model.id}',
        );
      }
      // 「字体」能搜到，路径含外观
      final fonts = index.where((r) => r.model.matchesQuery('字体'));
      expect(fonts.any((r) => r.path.startsWith('外观')), isTrue);
      // 副标题也参与匹配（索引用的是原声明，不是收进页脚后的版本）
      expect(
        index.any(
          (r) =>
              r.model.subtitle != null &&
              r.model.matchesQuery(r.model.subtitle!.substring(0, 2)),
        ),
        isTrue,
      );
      // 搜索跳转：目标页能带 highlightId 构建
      final target = index.firstWhere((r) => r.model.id == 'tuneFont');
      expect(target.pageBuilder(highlightId: 'tuneFont'), isA<AppearancePage>());
    });
  });

  group('字体 token', () {
    test('正文字体只进 body，其他字号档不受影响', () {
      final t = AppTokens.resolve(
        brightness: Brightness.light,
        bodyFontFamily: 'imported_1',
      );
      expect(t.text.body.fontFamily, 'imported_1');
      expect(t.text.headline.fontFamily, isNull);
      expect(t.text.meta.fontFamily, isNull);
      final d = AppTokens.resolve(brightness: Brightness.light);
      expect(d.text.body.fontFamily, isNull);
    });

    test('主题状态：导入字体做界面字体，选内置字体时清掉', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = ThemeNotifier(prefs);
      await notifier.setImportedUiFamily('imported_9');
      expect(notifier.state.fontFamilyName, 'imported_9');
      await notifier.setBodyFontFamily('MiSans');
      expect(notifier.state.bodyFontFamilyName, 'MiSans');
      await notifier.setFontFamily(AppFontFamily.miSans);
      expect(notifier.state.fontFamilyName, 'MiSans');
      expect(notifier.state.importedUiFamily, isNull);
      // 重启后读回来
      final reloaded = ThemeNotifier(prefs);
      expect(reloaded.state.bodyFontFamilyName, 'MiSans');
      expect(reloaded.state.importedUiFamily, isNull);
    });
  });

  group('副标题收进页脚', () {
    test('有副标题的行去掉副标题，说明逐行进页脚；搜索仍用原声明', () {
      final groups = [
        SettingsGroup(
          title: '组',
          icon: Icons.add,
          items: [
            SwitchModel(
              id: 'a',
              title: '开关',
              subtitle: '一段很长的说明',
              icon: Icons.add,
              getValue: (_) => true,
              onChanged: (_, _) {},
            ),
            ActionModel(
              id: 'b',
              title: '动作',
              icon: Icons.add,
              onTap: (_, _) {},
            ),
          ],
        ),
      ];
      final out = footerizeSubtitles(groups);
      expect(out.single.footer, '开关：一段很长的说明');
      expect(out.single.items.first.subtitle, isNull);
      expect(out.single.items.last.id, 'b');
      expect(groups.single.items.first.subtitle, '一段很长的说明');
    });

    test('已有页脚的组不动', () {
      final g = SettingsGroup(
        title: 't',
        icon: Icons.add,
        footer: '原页脚',
        items: [
          SwitchModel(
            id: 'a',
            title: '开关',
            subtitle: 's',
            icon: Icons.add,
            getValue: (_) => true,
            onChanged: (_, _) {},
          ),
        ],
      );
      expect(footerizeSubtitles([g]).single, same(g));
    });
  });
}
