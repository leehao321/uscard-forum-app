import '../../models/site_profile.dart';
import '../../services/site_context.dart';
import '../site_customization.dart';
import 'generic.dart';
import 'linuxdo.dart';

String? _resolvedFor;
SiteCustomization? _resolved;

/// 当前站点的自定义配置。
///
/// 放在这里而不是 `AppConstants`，插件层才能避开 `constants.dart` 的 WebView 依赖。
SiteCustomization get currentSiteCustomization {
  final site = SiteContext.current;
  if (_resolvedFor != site.id) {
    _resolvedFor = site.id;
    _resolved = switch (site.featurePack) {
      SiteFeaturePack.linuxdo => linuxdoCustomization,
      // 榜单：徽章 #20「精彩的话题」、#115「难绷的话题」（美卡自定义徽章）
      SiteFeaturePack.uscard => genericCustomization(
        site.rootHost,
        greatTopicBadgeId: 20,
        funnyTopicBadgeId: 115,
      ),
      SiteFeaturePack.generic => genericCustomization(site.rootHost),
    };
  }
  return _resolved!;
}
