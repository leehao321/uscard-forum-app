import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 导入字体的失败原因（界面只给一句人话，不弹详细错误）
enum FontImportFailure {
  /// 扩展名不对，或文件头不是字体
  notAFont,

  /// 用户取消
  cancelled,

  /// 复制 / 注册失败
  failed,
}

class FontImportException implements Exception {
  const FontImportException(this.failure);

  final FontImportFailure failure;

  @override
  String toString() => 'FontImportException($failure)';
}

/// 已导入的字体
@immutable
class ImportedFont {
  const ImportedFont({
    required this.id,
    required this.family,
    required this.displayName,
    required this.fileName,
    required this.size,
    required this.ext,
  });

  final String id;

  /// 注册给 [FontLoader] 的 family 名
  final String family;

  /// 列表里显示的名字（文件名去扩展名）
  final String displayName;

  /// 原始文件名
  final String fileName;

  /// 字节数
  final int size;

  /// 小写扩展名，含点：`.ttf` `.otf` `.ttc`
  final String ext;

  /// .ttc 是字体集合，只读第一个字重
  bool get isCollection => ext == '.ttc';

  Map<String, Object?> toJson() => {
    'id': id,
    'family': family,
    'displayName': displayName,
    'fileName': fileName,
    'size': size,
    'ext': ext,
  };

  static ImportedFont? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final family = json['family'];
    final ext = json['ext'];
    if (id is! String || family is! String || ext is! String) return null;
    return ImportedFont(
      id: id,
      family: family,
      displayName: (json['displayName'] as String?) ?? id,
      fileName: (json['fileName'] as String?) ?? '$id$ext',
      size: (json['size'] as num?)?.toInt() ?? 0,
      ext: ext,
    );
  }
}

/// 导入取消令牌
class FontImportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 字体导入（0.4.0 计划 §M8 字体页）
///
/// 只收 .ttf / .otf / .ttc，先查扩展名再查文件头魔数；复制到应用支持目录，
/// 用 [FontLoader] 注册；大文件放后台 isolate 读；.ttc 只读第一个字重
/// （Flutter 的引擎取集合里的第 0 个字体）；可删除。
class FontImportService {
  FontImportService._();

  static final FontImportService instance = FontImportService._();

  static const String _indexKey = 'imported_fonts_v1';
  static const Set<String> allowedExtensions = {'.ttf', '.otf', '.ttc'};

  /// 单个字体文件上限，防止误选超大文件
  static const int maxBytes = 120 * 1024 * 1024;

  /// 字体变化时通知（导入、删除）
  final ValueNotifier<List<ImportedFont>> fonts =
      ValueNotifier<List<ImportedFont>>(const []);

  bool _loaded = false;

  /// 魔数：`00 01 00 00` / `true`（TrueType）、`OTTO`（OpenType CFF）、`ttcf`（集合）
  @visibleForTesting
  static bool hasFontMagic(List<int> head) {
    if (head.length < 4) return false;
    final a = head[0], b = head[1], c = head[2], d = head[3];
    if (a == 0x00 && b == 0x01 && c == 0x00 && d == 0x00) return true;
    final tag = String.fromCharCodes([a, b, c, d]);
    return tag == 'true' || tag == 'OTTO' || tag == 'ttcf';
  }

  Future<Directory> _fontDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'fonts'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> fileOf(ImportedFont font) async =>
      File(p.join((await _fontDir()).path, '${font.id}${font.ext}'));

  Future<void> _saveIndex(SharedPreferences prefs) => prefs.setString(
    _indexKey,
    jsonEncode([for (final f in fonts.value) f.toJson()]),
  );

  /// 读取已导入的字体并向引擎注册。启动时调用一次，之后可重复调用。
  Future<List<ImportedFont>> ensureLoaded() async {
    if (_loaded) return fonts.value;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    final list = <ImportedFont>[];
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final font = ImportedFont.fromJson(item);
          if (font != null) list.add(font);
        }
      } catch (_) {
        // 索引损坏当作没有导入过
      }
    }
    final ok = <ImportedFont>[];
    for (final font in list) {
      try {
        await _register(font, await fileOf(font));
        ok.add(font);
      } catch (_) {
        // 文件丢了或损坏：从索引里去掉，不崩
      }
    }
    fonts.value = ok;
    if (ok.length != list.length) await _saveIndex(prefs);
    _loaded = true;
    return ok;
  }

  Future<void> _register(ImportedFont font, File file) async {
    // 大文件放后台 isolate 读，避免卡住 UI 线程
    final bytes = await Isolate.run(() => file.readAsBytesSync());
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  /// 导入 [path] 指向的字体文件。[onProgress] 回调已复制 / 总字节数。
  Future<ImportedFont> import(
    String path, {
    void Function(int done, int total)? onProgress,
    FontImportCancelToken? cancel,
  }) async {
    await ensureLoaded();
    final fileName = p.basename(path);
    final ext = p.extension(path).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw const FontImportException(FontImportFailure.notAFont);
    }
    final source = File(path);
    final RandomAccessFile raf;
    final int total;
    try {
      raf = await source.open();
      total = await raf.length();
    } on FileSystemException {
      throw const FontImportException(FontImportFailure.failed);
    }
    try {
      final head = await raf.read(4);
      if (!hasFontMagic(head) || total > maxBytes) {
        throw const FontImportException(FontImportFailure.notAFont);
      }
    } finally {
      await raf.close();
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final font = ImportedFont(
      id: id,
      family: 'imported_$id',
      displayName: p.basenameWithoutExtension(fileName),
      fileName: fileName,
      size: total,
      ext: ext,
    );
    final target = await fileOf(font);
    final sink = target.openWrite();
    try {
      var done = 0;
      await for (final chunk in source.openRead()) {
        if (cancel?.isCancelled ?? false) {
          await sink.close();
          if (target.existsSync()) await target.delete();
          throw const FontImportException(FontImportFailure.cancelled);
        }
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
      await sink.flush();
      await sink.close();
      await _register(font, target);
    } on FontImportException {
      rethrow;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (target.existsSync()) await target.delete();
      throw const FontImportException(FontImportFailure.notAFont);
    }
    fonts.value = [...fonts.value, font];
    await _saveIndex(await SharedPreferences.getInstance());
    return font;
  }

  /// 删除一个字体：文件和索引，并刷新引擎的字体缓存。调用方负责把正在
  /// 用它的选择换回默认。
  Future<void> delete(String id) async {
    await ensureLoaded();
    final font = fonts.value.where((f) => f.id == id).firstOrNull;
    if (font == null) return;
    final file = await fileOf(font);
    if (file.existsSync()) await file.delete();
    fonts.value = [
      for (final f in fonts.value)
        if (f.id != id) f,
    ];
    await _saveIndex(await SharedPreferences.getInstance());
    _releaseFromEngine();
  }

  /// Flutter 没有卸载字体的接口：已注册的 family 会留在引擎里直到下次启动。
  /// 调用方已把选择换走，没有文字再引用它；这里通知引擎刷新一次字体缓存，
  /// 让正在显示的文字按新的选择重新排版，「当场」生效。
  void _releaseFromEngine() {
    try {
      PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
        'type': 'fontsChange',
      });
    } catch (_) {
      // 没有绑定（纯单元测试）时忽略
    }
  }

  /// 测试用：重置内存状态
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    fonts.value = const [];
  }
}
