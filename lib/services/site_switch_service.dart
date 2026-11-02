import '../models/site_profile.dart';
import 'site_registry_service.dart';

/// 无重启切站时各步骤的编排顺序（清单阶段 8），顺序不能乱。
///
/// 全 App 是单例架构，切站是一次有序的拆卸重装。偷懒只改 baseUrl 不清缓存，A 站的
/// 分类、头像、登录态就会串到 B 站。现在换站走持久化加重启，这些步骤都由进程重启
/// 自然完成；以后要做无重启切换时按这里的顺序实现各步。
enum SiteSwitchStep {
  /// 停 MessageBus 长轮询，旧站不再推送。
  stopMessageBus,

  /// 清当前用户状态，取消 auth 相关订阅。
  clearCurrentUser,

  /// CookieJar 切到新站目录并重载，CSRF token 失效重取。
  switchCookieJar,

  /// 重建 DioHttpClient 的主域 Dio 和 DiscourseService 的 Dio：它们创建时固定了 baseUrl。
  rebuildMainDio,

  /// 清空 PreloadedDataService 的全部缓存（含站点级的 cdn、baseUri），对新站重跑 preload。
  resetPreloadedData,

  /// Riverpod 层整体失效：分类、话题列表、当前用户等。
  invalidateProviders,

  /// 路由重置回新站首页或登录页。
  resetNavigation,
}

class SiteSwitchService {
  SiteSwitchService({SiteRegistryService? registry})
    : _registry = registry ?? SiteRegistryService.instance;

  final SiteRegistryService _registry;

  /// 换站：持久化新的当前站，重启 App 后生效。
  Future<void> switchSite(SiteProfile site) async {
    await _registry.addOrUpdate(site);
    await _registry.setCurrent(site.id);
  }

  /// 无重启切换的骨架：按 [SiteSwitchStep] 的顺序依次执行，缺任何一步都拒绝运行。
  /// 目前没有调用方，留给以后实现。
  static Future<void> runNoRestartSteps(
    Map<SiteSwitchStep, Future<void> Function()> handlers,
  ) async {
    final missing = SiteSwitchStep.values.where((s) => !handlers.containsKey(s));
    if (missing.isNotEmpty) {
      throw ArgumentError('缺少切站步骤: ${missing.join(', ')}');
    }
    for (final step in SiteSwitchStep.values) {
      await handlers[step]!();
    }
  }
}
