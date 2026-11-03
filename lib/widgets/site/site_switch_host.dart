import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../services/site_switch_service.dart';

/// 根界面树外面的一层：切站时先卸载 [builder] 建的整棵树，切完再挂新的。
class SiteSwitchHost extends StatefulWidget {
  const SiteSwitchHost({super.key, required this.builder, this.controller});

  /// 挂在这里的树要带当前站的 key，切站后是全新的树。
  final WidgetBuilder builder;

  /// 测试时替换。
  final SiteSwitchController? controller;

  @override
  State<SiteSwitchHost> createState() => _SiteSwitchHostState();
}

class _SiteSwitchHostState extends State<SiteSwitchHost> {
  SiteSwitchController get _controller =>
      widget.controller ?? SiteSwitchController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return switch (_controller.phase) {
      SiteSwitchPhase.idle => widget.builder(context),
      SiteSwitchPhase.switching => ColoredBox(
        color: _background(context),
        child: const SizedBox.expand(),
      ),
      SiteSwitchPhase.failed => _SwitchFailedView(background: _background(context)),
    };
  }

  /// 这一层在 MaterialApp 外面，拿不到主题。
  Color _background(BuildContext context) {
    final color = _controller.placeholderColor;
    if (color != null) return color;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFFFFFFF);
  }
}

/// 切站失败时唯一显示的东西：不挂界面树，也就不会发出请求。
class _SwitchFailedView extends StatelessWidget {
  const _SwitchFailedView({required this.background});

  final Color background;

  @override
  Widget build(BuildContext context) {
    final foreground = background.computeLuminance() > 0.5
        ? const Color(0xFF1F1F1F)
        : const Color(0xFFE6E6E6);
    return ColoredBox(
      color: background,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              // 这里已经没有 MaterialApp，S.current 靠 navigatorKey 取不到 context
              t.auth.site_switch_failed,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
