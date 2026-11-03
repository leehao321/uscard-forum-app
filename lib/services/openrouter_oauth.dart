import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'network/adapters/platform_adapter.dart';

/// OpenRouter 一键登录：OAuth PKCE，换回一个属于用户自己账号的 API Key。
///
/// 流程见 https://openrouter.ai/docs/guides/overview/auth/oauth 。App 碰不到用户的
/// OpenRouter 密码，费用记在用户自己的额度上。Key 只返回给调用方，不在这里保存和打印。
class OpenRouterOAuth {
  OpenRouterOAuth({
    Dio? dio,
    Future<String> Function(String url, String callbackScheme)? authenticate,
    String Function()? newVerifier,
  }) : _dio = dio ?? _createDio(),
       _authenticate = authenticate ?? _systemAuthenticate,
       _newVerifier = newVerifier ?? createVerifier;

  static const callbackScheme = 'pulseflow';
  static const callbackUrl = 'pulseflow://openrouter-auth';
  static const baseUrl = 'https://openrouter.ai/api/v1';
  static const _keyLabel = 'Pulse Flow';

  final Dio _dio;
  final Future<String> Function(String url, String callbackScheme) _authenticate;
  final String Function() _newVerifier;

  static Dio _createDio() {
    // 独立的 Dio，不带论坛的 Cookie
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.httpClientAdapter = createExternalHttpAdapter();
    return dio;
  }

  static Future<String> _systemAuthenticate(String url, String scheme) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: scheme);

  /// PKCE 的 code_verifier：48 字节随机数，base64url 后 64 个字符。
  static String createVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// S256：sha256 后 base64url，不带填充。
  static String challengeFor(String verifier) => base64UrlEncode(
    sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');

  static Uri authorizeUrl(String verifier) =>
      Uri.https('openrouter.ai', '/auth', {
        'callback_url': callbackUrl,
        'code_challenge': challengeFor(verifier),
        'code_challenge_method': 'S256',
        'key_label': _keyLabel,
      });

  /// 打开授权页，换回 API Key。用户关掉授权页时返回 null，其他失败抛异常。
  Future<String?> login() async {
    final verifier = _newVerifier();
    final String callback;
    try {
      callback = await _authenticate(
        authorizeUrl(verifier).toString(),
        callbackScheme,
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
    final code = Uri.parse(callback).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const FormatException('授权回调里没有 code');
    }
    return _exchange(code, verifier);
  }

  Future<String> _exchange(String code, String verifier) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/auth/keys',
      data: {
        'code': code,
        'code_verifier': verifier,
        'code_challenge_method': 'S256',
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final key = response.data?['key'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('换取 API Key 的响应里没有 key');
    }
    debugPrint('[OpenRouterOAuth] 已换取 API Key');
    return key;
  }
}
