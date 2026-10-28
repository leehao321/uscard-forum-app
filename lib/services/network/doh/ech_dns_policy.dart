/// 公共 ECH 入口策略；仅替换 DNS 查询名，保留真实 Host、SNI 和缓存键。
class EchDnsPolicy {
  const EchDnsPolicy({this.enabled = true, this.customDomains = const []});

  static const cloudflareQueryName = 'cloudflare-ech.com';

  /// 当前站点（美卡论坛，在 Cloudflare 后面）的主域，含 www 等子域。
  ///
  /// Rust 代理（core/doh_proxy 子模块）里写死的内置规则仍是上游的
  /// linux.do / ldstatic.com，这里改不到；所以 [toJson] 把这些域名随自定义
  /// 域名一起下发给 Rust，两侧对美卡的判定保持一致。
  static const builtinDomains = ['uscardforum.com'];

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

  /// 下发给 Rust 和本地保存都用这份。站点内置域名放在 custom_domains 前面
  /// （Rust 侧内置规则不含美卡，见 [builtinDomains]）；[fromJson] 会把被内置
  /// 规则覆盖的条目滤掉，读回来不会混进用户的自定义域名。
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'custom_domains': [...builtinDomains, ...customDomains],
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
