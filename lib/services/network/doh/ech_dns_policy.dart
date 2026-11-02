import '../../../models/site_profile.dart';
import '../../site_context.dart';

/// 公共 ECH 入口策略；仅替换 DNS 查询名，保留真实 Host、SNI 和缓存键。
class EchDnsPolicy {
  const EchDnsPolicy({this.enabled = true, this.customDomains = const []});

  static const cloudflareQueryName = 'cloudflare-ech.com';

  /// Rust 代理（core/doh_proxy 子模块）里写死的内置域名，改不到。
  static const _rustBuiltinDomains = ['linux.do', 'ldstatic.com'];

  /// 当前站内置走 Cloudflare ECH 入口的域名。
  ///
  /// 查询名会被换成 Cloudflare 的入口，对不在 Cloudflare 后面的站会直接连不上，
  /// 所以只放确认在 Cloudflare 后面的预置站；用户自加的站需要时手动加到自定义域名。
  static List<String> get builtinDomains =>
      switch (SiteContext.current.featurePack) {
        SiteFeaturePack.linuxdo => _rustBuiltinDomains,
        SiteFeaturePack.uscard => [SiteContext.current.rootHost],
        SiteFeaturePack.generic => const [],
      };

  final bool enabled;
  final List<String> customDomains;

  EchDnsPolicy copyWith({bool? enabled, List<String>? customDomains}) =>
      EchDnsPolicy(
        enabled: enabled ?? this.enabled,
        customDomains: List.unmodifiable(customDomains ?? this.customDomains),
      );

  static String normalizeDomain(String value) =>
      value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');

  /// 只接收完整主机名，不接受 URL、端口、IP 或通配符。
  static bool isValidDomain(String value) {
    final host = normalizeDomain(value);
    if (host.length > 253 ||
        !host.contains('.') ||
        RegExp(r'^[0-9.]+$').hasMatch(host)) {
      return false;
    }
    return host
        .split('.')
        .every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        );
  }

  static bool covers(String domain, String host) =>
      host == domain || host.endsWith('.$domain');

  String queryName(String host) {
    if (!enabled) return host;
    final normalized = normalizeDomain(host);
    for (final domain in [...builtinDomains, ...customDomains]) {
      if (covers(domain, normalized)) return cloudflareQueryName;
    }
    return host;
  }

  /// 下发给 Rust 和本地保存都用这份。Rust 不认识的内置域名放进 custom_domains；
  /// [fromJson] 会把被内置规则覆盖的条目滤掉，读回来不会混进用户的自定义域名。
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'custom_domains': [
      ...builtinDomains.where((d) => !_rustBuiltinDomains.contains(d)),
      ...customDomains,
    ],
  };

  factory EchDnsPolicy.fromJson(Map<String, dynamic> json) {
    final domains = <String>{};
    for (final value in json['custom_domains'] as List? ?? const []) {
      if (value is! String || !isValidDomain(value)) continue;
      final domain = normalizeDomain(value);
      if (!builtinDomains.any((builtin) => covers(builtin, domain))) {
        domains.add(domain);
      }
    }
    return EchDnsPolicy(
      enabled: json['enabled'] as bool? ?? true,
      customDomains: List.unmodifiable(domains),
    );
  }
}
