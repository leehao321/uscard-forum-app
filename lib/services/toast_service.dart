import 'dart:async';
import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'local_notification_service.dart';

/// Toast 类型
enum ToastType { success, error, info }

/// 徽章与配色语义；download 只由下载句柄使用，完成时原位切到 success
enum _ToastKind { success, error, info, download }

@immutable
class _ToastData {
  const _ToastData({
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final _ToastKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  _ToastData withMessage(String message) => _ToastData(
    kind: kind,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// [ToastType] 与内部语义的映射
_ToastKind _kindOf(ToastType type) => switch (type) {
  ToastType.success => _ToastKind.success,
  ToastType.error => _ToastKind.error,
  ToastType.info => _ToastKind.info,
};

/// 挂在 Overlay 上的一次 Toast。下载完成时只替换 [data]，外壳、位置和
/// 入场状态都不动，才能表现为"原位变身"而不是先收起再弹出一个新的。
class _ToastSession {
  _ToastSession(_ToastData data, {this.isProgress = false})
    : data = ValueNotifier(data);

  final ValueNotifier<_ToastData> data;
  final progress = ValueNotifier<double>(-1.0); // -1 = 不确定进度

  /// 轻脉冲计数：同一件事重复触发时，给徽章一次"又生效了"的反馈
  final pulseTick = ValueNotifier<int>(0);

  /// 来自下载/同步这类带进度的提示：长期占住主槽位，普通提示不顶掉它，
  /// 而是下移让位（见 ToastService._stacked）
  final bool isProgress;

  OverlayEntry? _entry;
  AnimationController? _controller;
  Timer? _timer;
  bool _closed = false; // 逻辑关闭：不再接受进度与文案更新
  bool _released = false; // 资源已释放：收尾可能被打断，必须幂等

  bool get isClosed => _closed;

  void scheduleDismiss(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, () => close(animate: true));
  }

  /// 同一件事又发生了一次：不重播入场，只让徽章弹一下
  void pulse() {
    if (!_closed) pulseTick.value++;
  }

  void close({required bool animate}) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    final entry = _entry;

    // 退场直接倒放入场：文字先淡出，胶囊收回圆点，最后消失。
    // 倒放期间 entry 还留在 Overlay 上，此刻若插入新 Toast，两条会同时可见，
    // 所以要登记成 outgoing，由下一次 _present 提前收尾。
    if (animate && controller != null && entry != null) {
      ToastService._outgoing.add(this);
      controller.reverse().whenCompleteOrCancel(_release);
    } else {
      // 这里不能先清 _entry：_release 还要靠它把 entry 从 Overlay 摘掉
      _release();
    }
  }

  /// 幂等收尾：倒放正常结束、或被新 Toast 提前打断，都走这里。
  void _release() {
    if (_released) return;
    _released = true;
    ToastService._outgoing.remove(this);
    // 仍在倒放时 Ticker 是 active，直接卸树会在 dispose 中断言失败
    _controller?.stop();
    _controller = null;
    _entry?.remove();
    _entry = null;
    // 释放放在移除 entry 之后：State 卸载要等下一帧，期间 build 仍会读值
    data.dispose();
    progress.dispose();
    pulseTick.dispose();
    ToastService._onSessionReleased(this);
  }

  /// 视图被卸载：entry 与 controller 已随视图一起消失，此时再 stop/remove
  /// 只会打到已 dispose 的对象。整棵树被替换（登出、换 navigator）时，
  /// 收尾回调会晚于卸载到达，必须靠这里先标记掉。
  void _onViewDisposed() {
    _closed = true;
    _released = true;
    _timer?.cancel();
    _timer = null;
    _controller = null;
    _entry = null;
    ToastService._outgoing.remove(this);
    ToastService._onSessionReleased(this);
  }
}

/// 下载进度 Toast 句柄
class DownloadToastHandle {
  DownloadToastHandle._(this._session);

  final _ToastSession? _session;
  bool _finished = false;

  bool get isActive => !_finished && _session != null && !_session.isClosed;

  /// 更新下载进度（0.0~1.0，-1 为不确定进度）
  void updateProgress(double value) {
    if (isActive) _session!.progress.value = value;
  }

  /// 更新显示的文件名（HEAD 请求获取到更好的文件名时调用）
  void updateFileName(String name) {
    if (!isActive) return;
    final data = _session!.data;
    data.value = data.value.withMessage(name);
  }

  /// 在原位置变成结果提示：默认成功，失败传 [ToastType.error] 原位变色。
  /// 之后按普通 Toast 计时消失；若 Toast 已被划走或关闭，退化为新弹一条。
  /// [duration] 不传时用错误 5s、其余 3s 的默认值。
  void complete(
    String message, {
    ToastType type = ToastType.success,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final effective = duration ?? ToastService._defaultDuration(type);
    if (!isActive) {
      _detach();
      ToastService.show(
        message,
        type: type,
        duration: effective,
        actionLabel: actionLabel,
        onAction: onAction,
      );
      return;
    }
    final session = _session!;
    _detach();
    session.data.value = _ToastData(
      kind: _kindOf(type),
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    session.scheduleDismiss(effective);
  }

  /// 关闭 Toast
  void dismiss() {
    if (_finished) return;
    _detach();
    _session?.close(animate: true);
  }

  void _detach() {
    _finished = true;
    if (identical(ToastService._downloadHandle, this)) {
      ToastService._downloadHandle = null;
    }
  }
}

/// 全局 Toast 服务（基于 Overlay，v2 起显示在屏幕下方、工具栏上方）
///
/// 两个槽位：主槽位放下载/同步这类带进度的提示，或一条普通提示。进度提示
/// 占着主槽位时，普通提示落到次槽位（主槽位上方一点），互不打断；进度提示
/// 收尾后，次槽位的那条会落下来接替主槽位。
class ToastService {
  static _ToastSession? _current; // 主槽位
  static _ToastSession? _stacked; // 次槽位：让位中的普通提示
  /// 正在播退场动画的 Toast：新的出现前必须先把它收掉，否则同屏两条
  static final List<_ToastSession> _outgoing = [];
  static DownloadToastHandle? _downloadHandle;

  /// 主槽位是否被带进度的提示占着：普通提示据此下移让位
  static final ValueNotifier<bool> _progressOnTop = ValueNotifier<bool>(false);

  /// 错误提示默认停留更久，够看清出了什么问题
  static Duration _defaultDuration(ToastType type) => type == ToastType.error
      ? const Duration(seconds: 5)
      : const Duration(seconds: 3);

  /// 显示 Toast
  static void show(
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final data = _ToastData(
      kind: _kindOf(type),
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    final effective = duration ?? _defaultDuration(type);

    // 同一件事重复触发（连点复制、连续点赞）：不重播入场，只重置计时并让
    // 徽章弹一下——否则每次都从头展开，观感很抖
    final repeat = _findRepeat(data);
    if (repeat != null) {
      repeat.scheduleDismiss(effective);
      repeat.pulse();
      return;
    }

    final session = _present(data);
    session?.scheduleDismiss(effective);
  }

  /// 显示下载进度 Toast（持久，不自动消失）
  static DownloadToastHandle showDownload(String fileName) {
    // 旧的下载 Toast 由下面的替换直接移除，这里只让旧句柄失效
    _downloadHandle?._detach();

    // 主槽位上的普通提示不丢：挪到次槽位，随进度胶囊出现一起下移让位
    final notice = _current;
    if (notice != null && !notice.isProgress && !notice.isClosed) {
      _stacked?._release();
      _stacked = notice;
      _current = null;
    }

    final handle = DownloadToastHandle._(
      _present(_ToastData(kind: _ToastKind.download, message: fileName)),
    );
    if (handle._session == null) {
      // 没有 Overlay 可用：把刚挪走的提示放回主槽位
      _current ??= _stacked;
      _stacked = null;
      _refreshProgressOnTop();
    } else {
      _downloadHandle = handle;
    }
    return handle;
  }

  /// 显示成功提示
  static void showSuccess(String message) {
    show(message, type: ToastType.success);
  }

  /// 显示错误提示
  static void showError(String message) {
    show(message, type: ToastType.error);
  }

  /// 显示信息提示
  static void showInfo(String message) {
    show(message, type: ToastType.info);
  }

  /// 找到可以合并的同类提示（同类型、同文案、同操作）
  static _ToastSession? _findRepeat(_ToastData data) {
    for (final session in [_current, _stacked]) {
      if (session == null || session.isClosed || session.isProgress) continue;
      final current = session.data.value;
      if (current.kind == data.kind &&
          current.message == data.message &&
          current.actionLabel == data.actionLabel) {
        return session;
      }
    }
    return null;
  }

  /// 挂上一条新的 Toast：进度提示占主槽位；主槽位被进度提示占着时，普通
  /// 提示落次槽位下移让位，而不是把它顶掉。
  static _ToastSession? _present(_ToastData data) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return null;

    final toStack =
        data.kind != _ToastKind.download && _current?.isProgress == true;
    final replaced = toStack ? _stacked : _current;
    if (toStack) {
      _stacked = null;
    } else {
      // 先摘掉主槽位的记录：否则 _onSessionReleased 会误把次槽位里的提示
      // 提升上来，挤掉马上要插入的这条
      _current = null;
      for (final session in List.of(_outgoing)) {
        session._release();
      }
    }
    replaced?.close(animate: false);

    final session = _ToastSession(
      data,
      isProgress: data.kind == _ToastKind.download,
    );
    final entry = OverlayEntry(builder: (_) => _ToastView(session: session));
    session._entry = entry;
    if (toStack) {
      _stacked = session;
    } else {
      _current = session;
    }
    _refreshProgressOnTop();
    overlay.insert(entry);
    return session;
  }

  /// 一条 Toast 彻底收尾：腾出槽位，必要时把下方那条提升上来
  static void _onSessionReleased(_ToastSession session) {
    if (identical(_current, session)) {
      _current = null;
      final promoted = _stacked;
      if (promoted != null && !promoted.isClosed) {
        _stacked = null;
        _current = promoted;
      }
    } else if (identical(_stacked, session)) {
      _stacked = null;
    }
    _refreshProgressOnTop();
  }

  /// 主槽位只要还是进度来源的提示就算"占着顶部"——包括正在退场、entry 还
  /// 没摘掉的那条：它仍在屏幕上，普通提示就得待在它下面。
  static void _refreshProgressOnTop() {
    final top = _current;
    final value = top != null && top.isProgress;
    if (_progressOnTop.value != value) _progressOnTop.value = value;
  }
}

/// v2 Toast（设计说明 §4）：44 高胶囊、pad 0 16、间距 8，胶囊材质；
/// 图标 16 + 13 字。位于工具栏或 Tab 胶囊上方 16（默认按「64 高工具栏 +
/// 底部安全区」估算，键盘弹出时贴键盘上方）。出现和变身时用
/// VoiceOver 播报，不抢焦点。向下轻扫可提前关掉。
class _ToastView extends StatefulWidget {
  const _ToastView({required this.session});

  final _ToastSession session;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 220);
  static const _exitDuration = Duration(milliseconds: 180);

  /// 默认锚点：工具栏（64）上方 16
  static const double _anchorAboveToolbar = AppSize.toolbar + AppSpace.l;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: _enterDuration,
    reverseDuration: _exitDuration,
  );
  late final Listenable _repaint = Listenable.merge([
    _enter,
    widget.session.data,
    widget.session.progress,
  ]);
  late _ToastKind _kind = widget.session.data.value.kind;
  double _dragOffset = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    widget.session._controller = _enter;
    widget.session.data.addListener(_onDataChanged);
    _enter.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void dispose() {
    // 先让 session 忘掉 entry/controller：卸载会取消 Ticker，收尾回调可能
    // 晚一步到达，那时这两个对象已经不存在了
    widget.session._onViewDisposed();
    widget.session.data.removeListener(_onDataChanged);
    _enter.dispose();
    super.dispose();
  }

  void _announce() {
    if (!mounted) return;
    final data = widget.session.data.value;
    if (data.kind == _ToastKind.download) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      data.message,
      Directionality.of(context),
    );
  }

  void _onDataChanged() {
    final kind = widget.session.data.value.kind;
    if (kind == _kind) return;
    _kind = kind;
    // 下载完成原位变成结果提示：再播报一次
    _announce();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    // 只允许向下拖动
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0, double.infinity);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dismissing) return;
    if (_dragOffset > 24 || details.velocity.pixelsPerSecond.dy > 200) {
      _dismissing = true;
      widget.session.close(animate: true);
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottom = math.max(
      mediaQuery.viewPadding.bottom + _anchorAboveToolbar,
      mediaQuery.viewInsets.bottom + AppSpace.l,
    );
    return Positioned(
      bottom: bottom,
      left: AppSpace.pageMargin,
      right: AppSpace.pageMargin,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _StackSlot(
              // 进度提示自己就是让位的锚点，不需要上移
              active: !widget.session.isProgress,
              child: GestureDetector(
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: ListenableBuilder(
                  listenable: _repaint,
                  builder: (context, _) => _buildToast(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final t = Curves.easeOutCubic.transform(_enter.value);
    final dragFade = (1.0 - _dragOffset / 80).clamp(0.0, 1.0);
    return Opacity(
      opacity: t * dragFade,
      child: Transform.translate(
        offset: Offset(0, (reduceMotion ? 0 : (1 - t) * 8) + _dragOffset),
        child: Semantics(
          container: true,
          child: CapsuleSurface(
            child: Material(
              type: MaterialType.transparency,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: kChromeMaxTextScale,
                child: _buildContent(context, widget.session.data.value),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, _ToastData data) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final textStyle = Theme.of(context).textTheme.bodySmall!
        .merge(tokens.text.meta)
        .copyWith(color: colors.textPrimary);
    final progress = widget.session.progress.value;
    final isDownload = data.kind == _ToastKind.download;
    final hasAction = data.actionLabel != null;

    final icon = switch (data.kind) {
      _ToastKind.success => Icon(
        AppIcons.check,
        size: AppSize.iconS,
        color: colors.textPrimary,
      ),
      _ToastKind.error => Icon(
        AppIcons.error,
        size: AppSize.iconS,
        color: colors.textDestructive,
      ),
      _ToastKind.info => Icon(
        AppIcons.info,
        size: AppSize.iconS,
        color: colors.textMeta,
      ),
      _ToastKind.download =>
        progress >= 0
            ? SizedBox.square(
                dimension: AppSize.iconS,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: colors.brandPrimary,
                  backgroundColor: colors.avatarFill,
                ),
              )
            : const CupertinoActivityIndicator(radius: AppSize.iconS / 2),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.hit),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.l,
          right: hasAction ? AppSpace.xs : AppSpace.l,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: icon),
            const SizedBox(width: AppSpace.s),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
                child: Text(
                  data.message,
                  style: textStyle,
                  maxLines: isDownload ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (isDownload && progress >= 0) ...[
              const SizedBox(width: AppSpace.s),
              Text(
                '${(progress * 100).toInt()}%',
                style: textStyle.copyWith(
                  color: colors.textMeta,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (hasAction)
              AppPressable(
                onTap: () {
                  data.onAction?.call();
                  widget.session.close(animate: true);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSize.hit,
                    minHeight: AppSize.hit,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.m),
                    child: Center(
                      child: Text(
                        data.actionLabel!,
                        style: textStyle.copyWith(color: colors.brandPrimary),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 进度胶囊占着底部槽位时，普通提示整体上移让位；进度提示收尾后落回
/// 原位。进度提示自己不参与，免得把自己推走。
class _StackSlot extends StatelessWidget {
  const _StackSlot({required this.active, required this.child});

  final bool active;
  final Widget child;

  /// Toast 高 44 + 间距 8
  static const double _slotHeight = AppSize.hit + AppSpace.s;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: ToastService._progressOnTop,
      // begin 只在第一次构建时生效：出生在让位槽的提示直接落在那里，
      // 不从主槽位滑过去（否则开头会和进度胶囊叠在一起）；之后槽位变化
      // 才从当前位置动画过去
      builder: (context, shown, child) => TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: shown ? _slotHeight : 0,
          end: shown ? _slotHeight : 0,
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, offset, child) =>
            Transform.translate(offset: Offset(0, -offset), child: child),
        child: child,
      ),
      child: child,
    );
  }
}
