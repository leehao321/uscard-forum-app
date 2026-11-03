import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/site_profile.dart';
import 'site_context.dart';
import 'site_registry_service.dart';
import 'site_switch_work.dart';

/// 切站各步骤的顺序，不能乱。
///
/// 全 App 是单例架构，切站是一次有序的拆卸重装。偷懒只改 baseUrl 不清缓存，A 站的
/// 分类、头像、登录态就会串到 B 站。
enum SiteSwitchStep {
  /// 切断在途请求，停长轮询：它们的响应不能再落到任何一个站上。
  stopWork,

  /// 卸载旧的界面树，页面和 Riverpod 状态随之销毁。
  ///
  /// 必须真的卸载完（下一帧）才能往下走。根 ProviderScope 只换 key 不行：
  /// navigatorKey 是 GlobalKey，同一帧里换 key 时框架会把旧 Navigator 连页面栈一起
  /// 搬到新树上，A 站的页面继续活着。
  unmountUi,

  /// 等收尾：保存本地统计、停 WebView。还属于旧站，所以在换站之前。
  drainWork,

  /// 打开新站的 Cookie 存储，持久化新的当前站。要 await 的都放在这里。
  prepareSite,

  /// 换站本身：激活新站、换 Cookie 存储、清旧站的内存状态。
  ///
  /// 全程同步，中间没有 await，别的代码插不进来，不会有请求带着 A 的凭证发到 B。
  commitSite,

  /// 对新站重新做启动时的初始化，然后挂上新的界面树。
  restartWork,
}

enum SiteSwitchPhase { idle, switching, failed }

/// 切站时每一步具体做什么。真实实现在 [DeviceSiteSwitchWork]，测试时替换。
abstract class SiteSwitchWork {
  void stopWork();

  /// 等旧的界面树真正卸载。
  Future<void> waitForUnmount();

  Future<void> drainWork();

  /// 返回值原样交给 [commitSite]。
  Future<Object?> prepareSite(SiteProfile site);

  void commitSite(SiteProfile site, Object? prepared);

  Future<void> restartWork();
}

/// 不重启切站。[SiteSwitchHost] 听它决定显示什么。
class SiteSwitchController extends ChangeNotifier {
  SiteSwitchController({SiteSwitchWork? work, SiteRegistryService? registry})
    : _work = work,
      _registry = registry;

  static final SiteSwitchController instance = SiteSwitchController();

  final SiteSwitchWork? _work;
  final SiteRegistryService? _registry;

  SiteSwitchPhase _phase = SiteSwitchPhase.idle;
  SiteSwitchPhase get phase => _phase;

  /// 切换期间铺满屏幕的颜色，由发起方传当前主题的背景色，避免闪一下别的颜色。
  Color? placeholderColor;

  /// 切到 [site]。已是当前站或正在切换时什么都不做，返回 false。
  ///
  /// 中途失败不回退：旧状态已经拆了，继续用不安全。[SiteSwitchHost] 不再挂界面，
  /// 提示重新打开 App，不会发出任何请求；此时新站可能已经持久化，重开后就是新站。
  Future<bool> switchTo(SiteProfile site, {Color? placeholderColor}) async {
    if (_phase != SiteSwitchPhase.idle || site.id == SiteContext.current.id) {
      return false;
    }
    this.placeholderColor = placeholderColor;
    final work =
        _work ??
        DeviceSiteSwitchWork(registry: _registry ?? SiteRegistryService.instance);
    _phase = SiteSwitchPhase.switching;
    Object? prepared;
    try {
      await SiteSwitchService.runNoRestartSteps({
        SiteSwitchStep.stopWork: () async => work.stopWork(),
        SiteSwitchStep.unmountUi: () async {
          notifyListeners();
          await work.waitForUnmount();
        },
        SiteSwitchStep.drainWork: work.drainWork,
        SiteSwitchStep.prepareSite: () async {
          prepared = await work.prepareSite(site);
        },
        SiteSwitchStep.commitSite: () async {
          work.commitSite(site, prepared);
        },
        SiteSwitchStep.restartWork: work.restartWork,
      });
    } catch (e, s) {
      debugPrint('[SiteSwitch] 切站失败: $e\n$s');
      _phase = SiteSwitchPhase.failed;
      notifyListeners();
      return false;
    }
    _phase = SiteSwitchPhase.idle;
    notifyListeners();
    return true;
  }
}

class SiteSwitchService {
  /// 按 [SiteSwitchStep] 的顺序依次执行，缺任何一步都拒绝运行。
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
