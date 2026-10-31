import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import 'common/app_mark.dart';

/// 应用锁遮罩：上锁时盖住整个界面，并自动弹一次系统认证；离开前台时只盖
/// 隐私遮罩（不弹认证），多任务缩略图里看不到内容。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  final _service = AppLockService.instance;
  bool _wasLocked = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _onChanged();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final locked = _service.locked;
    if (locked && !_wasLocked) {
      // 上锁的那一刻收起键盘：否则键盘浮在锁屏上，打的字会进到被盖住的输入框。
      // 只盖隐私遮罩时不收：iOS 拉通知中心、钥匙串自动填充的 Face ID 确认都会
      // 短暂 inactive，收了键盘会打断正在写的回复、让密码填不进去
      FocusManager.instance.primaryFocus?.unfocus();
      // 刚上锁：等这一帧画完再弹系统认证
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _service.locked) _service.unlock();
      });
    }
    _wasLocked = locked;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.covering) return const SizedBox.shrink();
    final tokens = context.tokens;
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final locked = _service.locked;
    // v2 锁屏（设计说明 §5.3）：静态 96 图标 + 标题 17 Semibold + 说明 13 meta +
    // 主按钮 48「解锁」；隐私遮罩 = 同一页去掉文字和按钮
    return Positioned.fill(
      // BlockSemantics：底下页面的语义树整个屏蔽，VoiceOver 读不到、也点不到被盖住的内容
      child: BlockSemantics(
        child: Material(
          color: colors.surfacePage,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.pageMargin,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppMark(size: 96),
                    if (locked) ...[
                      const SizedBox(height: AppSpace.xl),
                      Text(
                        '美卡论坛已锁定',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium
                            ?.merge(tokens.text.control)
                            .copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: AppSpace.s),
                      Text(
                        '用 Face ID / Touch ID 或设备密码解锁',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.merge(tokens.text.meta)
                            .copyWith(color: colors.textMeta),
                      ),
                      const SizedBox(height: AppSpace.xxl),
                      FilledButton.icon(
                        onPressed: _service.authenticating
                            ? null
                            : _service.unlock,
                        style: AppButtonStyles.large.merge(
                          FilledButton.styleFrom(
                            minimumSize: const Size(160, AppSize.replyButton),
                          ),
                        ),
                        icon: const Icon(
                          AppIcons.lockOpen,
                          size: AppSize.iconM,
                        ),
                        label: const Text('解锁'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
