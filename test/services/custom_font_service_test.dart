import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/custom_font_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 能过文件头检查的最小内容
Uint8List _fakeFont({int seed = 1, String magic = 'OTTO'}) => Uint8List.fromList([
  ...magic.codeUnits,
  0,
  3,
  seed,
  ...List.filled(40, 7),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late SharedPreferences prefs;
  late List<String> registered;

  CustomFontService service({Future<void> Function(String, Uint8List)? register}) =>
      CustomFontService(
        prefs: prefs,
        documents: () async => temp,
        register: register ??
            (family, bytes) async {
              registered.add(family);
            },
      );

  Future<String> source(String name, List<int> bytes) async {
    final file = File('${temp.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('custom-font-');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    registered = [];
    CustomFontService.current = null;
  });

  tearDown(() async {
    CustomFontService.current = null;
    await temp.delete(recursive: true);
  });

  group('文件头', () {
    test('认 TrueType 和 OpenType', () {
      expect(CustomFontService.looksLikeFont(_fakeFont()), isTrue);
      expect(CustomFontService.looksLikeFont(_fakeFont(magic: 'true')), isTrue);
      expect(
        CustomFontService.looksLikeFont(
          Uint8List.fromList([0, 1, 0, 0, 0, 5, ...List.filled(20, 0)]),
        ),
        isTrue,
      );
    });

    test('改了扩展名的文件、空文件、表数量为 0 的都不算', () {
      expect(CustomFontService.looksLikeFont(Uint8List(0)), isFalse);
      expect(
        CustomFontService.looksLikeFont(
          Uint8List.fromList('<html>not a font</html>'.codeUnits),
        ),
        isFalse,
      );
      expect(
        CustomFontService.looksLikeFont(
          Uint8List.fromList([...'OTTO'.codeUnits, 0, 0, ...List.filled(10, 0)]),
        ),
        isFalse,
      );
    });

    test('真实字体文件能过', () async {
      final bytes = await File('assets/fonts/MiSansVF.ttf').readAsBytes();
      expect(CustomFontService.looksLikeFont(bytes), isTrue);
    });
  });

  group('导入', () {
    test('复制到 documents/fonts，注册，记下文件名和显示名', () async {
      final path = await source('思源黑体.otf', _fakeFont());
      final font = await service().importFile(path);

      expect(font.displayName, '思源黑体');
      expect(registered, [font.family]);
      expect(CustomFontService.current?.family, font.family);
      final fileName = prefs.getString(CustomFontService.fileKey)!;
      expect(fileName, endsWith('.otf'));
      expect(fileName, isNot(contains(temp.path)), reason: 'iOS 升级后沙盒路径会变，只存文件名');
      expect(File('${temp.path}/fonts/$fileName').existsSync(), isTrue);
    });

    test('不是字体：拒绝，什么都不留下', () async {
      final path = await source('fake.ttf', '<html></html>'.codeUnits);
      await expectLater(
        service().importFile(path),
        throwsA(
          isA<CustomFontException>().having((e) => e.error, 'error', CustomFontError.notAFont),
        ),
      );
      expect(registered, isEmpty);
      expect(prefs.getString(CustomFontService.fileKey), isNull);
      expect(Directory('${temp.path}/fonts').existsSync(), isFalse);
    });

    test('文件读不到：报读取失败', () async {
      await expectLater(
        service().importFile('${temp.path}/missing.ttf'),
        throwsA(
          isA<CustomFontException>().having((e) => e.error, 'error', CustomFontError.readFailed),
        ),
      );
    });

    test('换一个字体：族名不同才能生效，旧文件删掉', () async {
      final first = await service().importFile(await source('a.ttf', _fakeFont(seed: 1)));
      final firstFile = prefs.getString(CustomFontService.fileKey)!;
      final second = await service().importFile(await source('b.ttf', _fakeFont(seed: 2)));

      expect(second.family, isNot(first.family));
      expect(File('${temp.path}/fonts/$firstFile').existsSync(), isFalse);
      expect(
        File('${temp.path}/fonts/${prefs.getString(CustomFontService.fileKey)}').existsSync(),
        isTrue,
      );
    });

    test('重新导入同一个字体：文件还在', () async {
      final path = await source('a.ttf', _fakeFont());
      await service().importFile(path);
      await service().importFile(path);
      final file = prefs.getString(CustomFontService.fileKey)!;
      expect(File('${temp.path}/fonts/$file').existsSync(), isTrue);
    });
  });

  group('启动时加载', () {
    test('重新注册上次导入的字体', () async {
      final font = await service().importFile(await source('a.ttf', _fakeFont()));
      CustomFontService.current = null;
      registered.clear();

      final loaded = await service().loadSaved();
      expect(loaded?.family, font.family);
      expect(loaded?.displayName, 'a');
      expect(registered, [font.family]);
    });

    test('没导入过：什么都不做', () async {
      expect(await service().loadSaved(), isNull);
      expect(registered, isEmpty);
    });

    test('文件没了（备份恢复到新设备）：当没有，不影响启动', () async {
      await prefs.setString(CustomFontService.fileKey, 'gone.ttf');
      expect(await service().loadSaved(), isNull);
      expect(CustomFontService.current, isNull);
    });

    test('注册失败：当没有，不影响启动', () async {
      await service().importFile(await source('a.ttf', _fakeFont()));
      CustomFontService.current = null;
      final loaded = await service(
        register: (_, _) async => throw StateError('engine'),
      ).loadSaved();
      expect(loaded, isNull);
      expect(CustomFontService.current, isNull);
    });
  });

  group('主题', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('选自定义字体：写进 fontFamilyName，无需重启', () async {
      final font = await service().importFile(await source('a.ttf', _fakeFont()));
      final c = container();
      await c.read(themeProvider.notifier).setFontFamily(AppFontFamily.custom);
      expect(c.read(themeProvider).fontFamilyName, font.family);
    });

    test('恢复系统默认', () async {
      await service().importFile(await source('a.ttf', _fakeFont()));
      final c = container();
      await c.read(themeProvider.notifier).setFontFamily(AppFontFamily.custom);
      await c.read(themeProvider.notifier).setFontFamily(AppFontFamily.system);
      expect(c.read(themeProvider).fontFamilyName, isNull);
    });

    test('重启后保持：设置和字体都在', () async {
      final font = await service().importFile(await source('a.ttf', _fakeFont()));
      await prefs.setString('font_family', 'custom');
      await service().loadSaved();
      expect(container().read(themeProvider).fontFamilyName, font.family);
    });

    test('字体文件丢了：回到系统默认，不会用一个不存在的字体', () async {
      await prefs.setString('font_family', 'custom');
      CustomFontService.current = null;
      final state = container().read(themeProvider);
      expect(state.fontFamily, AppFontFamily.system);
      expect(state.fontFamilyName, isNull);
    });
  });
}
