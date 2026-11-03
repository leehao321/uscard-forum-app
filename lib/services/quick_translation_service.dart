import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'ai_translation_service.dart';
import 'network/adapters/platform_adapter.dart';
import 'translation_engine.dart';

/// 一次翻译的结果。
class QuickTranslation {
  const QuickTranslation({
    required this.text,
    required this.sourceLanguage,
    required this.truncated,
  });

  final String text;

  /// 接口识别出的原文语言，如 `en`、`zh-CN`；识别不出时为 null。
  final String? sourceLanguage;

  /// 帖子超过 [AiTranslationService.maxTranslateChars]，只翻译了开头。
  final bool truncated;

  bool isSameLanguageAs(String target) {
    final source = sourceLanguage?.toLowerCase();
    return source != null && source == target.toLowerCase();
  }
}

/// 楼层翻译：调 Google 网页翻译用的接口，不需要 Key，也不用配模型。
///
/// 这个接口不是公开 API，随时可能限流或改格式，调用方要能处理失败。帖子原文会发给
/// Google，所以只在用户点「翻译」时才调用，不预取。用独立的 Dio，不带论坛的 Cookie。
class QuickTranslationService implements TranslationEngine {
  QuickTranslationService({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static const _endpoint = 'https://translate.googleapis.com/translate_a/single';

  /// 单次请求的字符上限，超过的按段落拆成几次并发。
  static const maxChunkChars = 4000;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.plain,
      ),
    );
    dio.httpClientAdapter = createExternalHttpAdapter();
    return dio;
  }

  @override
  Future<QuickTranslation> translatePost({
    required String cookedHtml,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) async {
    final clamped = AiTranslationService.clampForTranslation(
      translatableText(cookedHtml),
    );
    if (clamped.text.isEmpty) {
      return const QuickTranslation(
        text: '',
        sourceLanguage: null,
        truncated: false,
      );
    }
    final parts = await Future.wait([
      for (final chunk in splitChunks(clamped.text))
        _translateChunk(chunk, targetLanguage, cancelToken),
    ]);
    return QuickTranslation(
      text: parts.map((p) => p.text).join().trim(),
      sourceLanguage: parts.first.source,
      truncated: clamped.truncated,
    );
  }

  Future<({String text, String? source})> _translateChunk(
    String chunk,
    String targetLanguage,
    CancelToken? cancelToken,
  ) async {
    final response = await _dio.post<String>(
      _endpoint,
      queryParameters: {
        'client': 'gtx',
        'sl': 'auto',
        'tl': targetLanguage,
        'dt': 't',
      },
      data: {'q': chunk},
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return parseResponse(response.data ?? '');
  }

  /// 响应是嵌套数组：`[[[译文, 原文, ...], ...], null, 原文语言, ...]`。
  static ({String text, String? source}) parseResponse(String body) {
    final data = jsonDecode(body);
    if (data is! List || data.isEmpty || data[0] is! List) {
      throw const FormatException('翻译接口返回格式变了');
    }
    final text = StringBuffer();
    for (final segment in data[0] as List) {
      if (segment is List && segment.isNotEmpty && segment[0] is String) {
        text.write(segment[0]);
      }
    }
    if (text.isEmpty) throw const FormatException('翻译接口没有返回译文');
    final source = data.length > 2 && data[2] is String
        ? data[2] as String
        : null;
    return (text: text.toString(), source: source);
  }

  /// 帖子里值得翻译的文字：去掉代码块、链接预览和图片信息。
  static String translatableText(String cookedHtml) {
    final document = html_parser.parse(cookedHtml);
    for (final element in document.querySelectorAll(
      'pre, aside.onebox, .lightbox-wrapper .meta, svg',
    )) {
      element.remove();
    }
    return AiTranslationService.extractPlainText(
      document.body?.innerHtml ?? '',
    );
  }

  /// 按段落把长文拆开，保留段落之间的换行；单段超长时才硬切。
  static List<String> splitChunks(String text) {
    final chunks = <String>[];
    var rest = text;
    while (rest.length > maxChunkChars) {
      var cut = rest.lastIndexOf('\n', maxChunkChars);
      if (cut <= 0) cut = maxChunkChars;
      chunks.add(rest.substring(0, cut + (rest[cut] == '\n' ? 1 : 0)));
      rest = rest.substring(chunks.last.length);
    }
    if (rest.isNotEmpty) chunks.add(rest);
    return chunks;
  }
}
