import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../models/site_profile.dart';

sealed class SiteProbeResult {
  const SiteProbeResult();
}

/// 确认是 Discourse，并拿到了站点信息。
class SiteProbeSuccess extends SiteProbeResult {
  /// 跟随重定向后的真实站点地址，可能和用户输入不同。
  final String baseUrl;
  final String title;
  final String? description;
  final String? version;
  final String? logoUrl;
  final String? faviconUrl;
  final bool loginRequired;

  const SiteProbeSuccess({
    required this.baseUrl,
    required this.title,
    this.description,
    this.version,
    this.logoUrl,
    this.faviconUrl,
    this.loginRequired = false,
  });

  SiteProfile toProfile() => SiteProfile(
    baseUrl: baseUrl,
    title: title,
    logoUrl: logoUrl,
    faviconUrl: faviconUrl,
  );
}

enum SiteProbeFailureReason {
  /// 能连上，但不是 Discourse（或论坛部署在其他路径）。
  notDiscourse,

  /// 连不上：断网、DNS、超时、站点 5xx。
  unreachable,

  /// HTTPS 证书校验失败。
  badCertificate,

  /// 被 Cloudflare 验证挡住，读不到站点信息，但不代表不是 Discourse。
  cloudflareChallenge,
}

class SiteProbeFailure extends SiteProbeResult {
  final SiteProbeFailureReason reason;
  const SiteProbeFailure(this.reason);
}

/// 加站前校验地址是不是 Discourse，并取站点信息。
///
/// 只用一个独立的 Dio：不带 cookie、不带 User API Key，避免把当前站的登录态
/// 发给用户刚输入的陌生地址。
class SiteProbeService {
  SiteProbeService({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  @visibleForTesting
  static Dio createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json',
        'User-Agent': AppConstants.userAgent,
      },
    ),
  );

  /// [baseUrl] 必须已经过 [normalizeSiteBaseUrl]。
  Future<SiteProbeResult> probe(String baseUrl) async {
    try {
      final site = await _dio.get<String>('$baseUrl/site.json');
      if (_isCloudflareChallenge(site)) {
        return const SiteProbeFailure(SiteProbeFailureReason.cloudflareChallenge);
      }

      final siteIsDiscourse =
          site.statusCode == 200 && _looksLikeSiteJson(_decodeMap(site.data));

      final info = await _getOptional('$baseUrl/site/basic-info.json');
      final infoMap = info?.statusCode == 200 ? _decodeMap(info!.data) : null;
      final infoIsDiscourse = _looksLikeBasicInfo(infoMap);

      if (!siteIsDiscourse && !infoIsDiscourse) {
        if (info != null && _isCloudflareChallenge(info)) {
          return const SiteProbeFailure(
            SiteProbeFailureReason.cloudflareChallenge,
          );
        }
        final status = site.statusCode ?? 0;
        return SiteProbeFailure(
          status >= 500
              ? SiteProbeFailureReason.unreachable
              : SiteProbeFailureReason.notDiscourse,
        );
      }

      final realBase = siteIsDiscourse
          ? _realBaseUrl(site, '/site.json')
          : _realBaseUrl(info!, '/site/basic-info.json');
      if (realBase == null) {
        return const SiteProbeFailure(SiteProbeFailureReason.notDiscourse);
      }

      final about = siteIsDiscourse
          ? await _getOptional('$realBase/about.json')
          : null;
      final aboutJson = about?.statusCode == 200
          ? _decodeMap(about!.data)
          : null;
      final aboutValue = aboutJson?['about'];
      final aboutFields = aboutValue is Map ? aboutValue : const {};

      return SiteProbeSuccess(
        baseUrl: realBase,
        title:
            _nonEmpty(aboutFields['title']) ??
            _nonEmpty(infoMap?['title']) ??
            Uri.parse(realBase).host,
        description:
            _nonEmpty(aboutFields['description']) ??
            _nonEmpty(infoMap?['description']),
        version: _nonEmpty(aboutFields['version']),
        logoUrl: _resolveAsset(realBase, infoMap?['logo_url']),
        faviconUrl: _resolveAsset(realBase, infoMap?['apple_touch_icon_url']),
        loginRequired: infoMap?['login_required'] == true || !siteIsDiscourse,
      );
    } on DioException catch (e) {
      return SiteProbeFailure(
        e.type == DioExceptionType.badCertificate
            ? SiteProbeFailureReason.badCertificate
            : SiteProbeFailureReason.unreachable,
      );
    }
  }

  /// 补充信息的请求，失败不影响校验结论。
  Future<Response<String>?> _getOptional(String url) async {
    try {
      return await _dio.get<String>(url);
    } on DioException {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeMap(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// /site.json 一定有分类列表和这几个站点级枚举。
  static bool _looksLikeSiteJson(Map<String, dynamic>? json) {
    if (json == null || json['categories'] is! List) return false;
    return json.containsKey('default_archetype') ||
        json.containsKey('post_action_types') ||
        json.containsKey('notification_types');
  }

  /// /site/basic-info.json 对需要登录的站也开放，是这类站唯一能确认身份的接口。
  static bool _looksLikeBasicInfo(Map<String, dynamic>? json) {
    return json != null &&
        json['title'] is String &&
        json.containsKey('login_required');
  }

  static bool _isCloudflareChallenge(Response<String> response) {
    final status = response.statusCode;
    if (status != 403 && status != 429 && status != 503) return false;
    if (response.headers.value('cf-mitigated') == 'challenge') return true;
    final server = response.headers.value('server') ?? '';
    if (!server.toLowerCase().contains('cloudflare')) return false;
    final body = response.data ?? '';
    return body.contains('challenge-platform') ||
        body.contains('_cf_chl_opt') ||
        body.contains('Just a moment');
  }

  /// 从最终请求地址反推站点地址；重定向到非 https 或别的路径时返回 null。
  static String? _realBaseUrl(Response<String> response, String apiPath) {
    final uri = response.realUri;
    if (uri.scheme != 'https' || !uri.path.endsWith(apiPath)) return null;
    final path = uri.path.substring(0, uri.path.length - apiPath.length);
    return normalizeSiteBaseUrl('${uri.origin}$path');
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _resolveAsset(String baseUrl, Object? value) {
    final url = _nonEmpty(value);
    if (url == null) return null;
    final resolved = Uri.parse(baseUrl).resolve(url);
    return resolved.scheme == 'https' ? resolved.toString() : null;
  }
}
