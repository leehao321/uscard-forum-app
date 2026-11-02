/// 站点专属功能包：决定哪些依赖站方自建服务或社区插件的功能可用。
enum SiteFeaturePack { generic, linuxdo, uscard }

/// 一个已注册的 Discourse 站点。
class SiteProfile {
  /// 规范化后的 `https://host[:port][/子路径]`，不带尾斜杠。
  final String baseUrl;

  /// 站点标题（来自 /about.json、/site/basic-info.json，预置站为内置值）。
  final String title;

  final String? logoUrl;
  final String? faviconUrl;

  /// 由 [baseUrl] 决定，不持久化：只有预置站能拿到专属功能包。
  final SiteFeaturePack featurePack;

  const SiteProfile._({
    required this.baseUrl,
    required this.title,
    required this.featurePack,
    this.logoUrl,
    this.faviconUrl,
  });

  /// [baseUrl] 必须已经过 [normalizeSiteBaseUrl]；命中预置站时沿用预置的功能包。
  factory SiteProfile({
    required String baseUrl,
    required String title,
    String? logoUrl,
    String? faviconUrl,
  }) {
    return SiteProfile._(
      baseUrl: baseUrl,
      title: title,
      logoUrl: logoUrl,
      faviconUrl: faviconUrl,
      featurePack:
          SitePresets.match(baseUrl)?.featurePack ?? SiteFeaturePack.generic,
    );
  }

  /// 站点标识：同一 host 下不同子路径算不同站点。
  String get id => baseUrl.substring('https://'.length);

  String get host => Uri.parse(baseUrl).host;

  /// `https://host[:port]`，不含子路径。Origin 头、WebView origin 校验用它。
  String get origin => Uri.parse(baseUrl).origin;

  /// 子路径前缀（如 `/forum`），根部署时为空串。
  String get basePath => Uri.parse(baseUrl).path;

  /// 是否允许后台轮询、预取等非用户触发的访问。
  bool get allowBackgroundAccess => featurePack != SiteFeaturePack.uscard;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'title': title,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (faviconUrl != null) 'faviconUrl': faviconUrl,
  };

  /// 数据损坏时返回 null，由调用方跳过。
  static SiteProfile? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final rawBaseUrl = json['baseUrl'];
    if (rawBaseUrl is! String) return null;
    final baseUrl = normalizeSiteBaseUrl(rawBaseUrl);
    if (baseUrl == null) return null;
    final title = json['title'];
    final logoUrl = json['logoUrl'];
    final faviconUrl = json['faviconUrl'];
    return SiteProfile(
      baseUrl: baseUrl,
      title: title is String && title.isNotEmpty ? title : Uri.parse(baseUrl).host,
      logoUrl: logoUrl is String ? logoUrl : null,
      faviconUrl: faviconUrl is String ? faviconUrl : null,
    );
  }
}

/// 内置的预置站点。
class SitePresets {
  SitePresets._();

  static const uscard = SiteProfile._(
    baseUrl: 'https://www.uscardforum.com',
    title: 'USCard Forum',
    featurePack: SiteFeaturePack.uscard,
  );

  static const linuxdo = SiteProfile._(
    baseUrl: 'https://linux.do',
    title: 'LINUX DO',
    featurePack: SiteFeaturePack.linuxdo,
  );

  /// 显示顺序即加站页卡片顺序，首项默认选中。
  static const all = [uscard, linuxdo];

  static const _aliases = {
    'www.uscardforum.com': uscard,
    'uscardforum.com': uscard,
    'linux.do': linuxdo,
    'www.linux.do': linuxdo,
  };

  /// [baseUrl] 指向某个预置站时返回它（裸域和 www 算同一站）。
  static SiteProfile? match(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.path.isNotEmpty || uri.hasPort) return null;
    return _aliases[uri.host];
  }
}

/// 粘贴帖子链接时，从这些路径段开始都不属于站点地址。
const _discourseRouteSegments = {
  'about',
  'admin',
  'badges',
  'c',
  'categories',
  'faq',
  'g',
  'groups',
  'guidelines',
  'latest',
  'login',
  'my',
  'new',
  'privacy',
  'search',
  'session',
  'tag',
  'tags',
  't',
  'top',
  'tos',
  'u',
  'unread',
};

/// 把用户输入规范化成 `https://host[:port][/子路径]`；不是合法站点地址时返回 null。
///
/// 补 https、去尾斜杠与查询串、host 转小写。显式写 http:// 也升级成 https。
String? normalizeSiteBaseUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(text);
  if (scheme != null) {
    final name = scheme.group(1)!.toLowerCase();
    if (name != 'http' && name != 'https') return null;
    text = text.substring(scheme.end);
  }

  final uri = Uri.tryParse('https://$text');
  if (uri == null || uri.userInfo.isNotEmpty) return null;

  final host = uri.host.toLowerCase();
  if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
      .hasMatch(host)) {
    return null;
  }

  final segments = <String>[];
  for (final segment in uri.pathSegments) {
    if (segment.isEmpty) continue;
    if (_discourseRouteSegments.contains(segment.toLowerCase()) ||
        segment.toLowerCase().endsWith('.json')) {
      break;
    }
    segments.add(segment);
  }

  return Uri(
    scheme: 'https',
    host: host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments.isEmpty ? null : segments,
  ).toString();
}
