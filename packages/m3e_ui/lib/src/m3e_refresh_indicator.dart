import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 下拉刷新。
///
/// 架构:状态机整体移植自 Flutter SDK 的 refresh_indicator.dart
/// (与 pub 上 expressive_refresh 的做法相同,MIT),只替换展示层 ——
/// 拖拽/armed/snap/refresh/done 的全部状态转移、位移(SizeTransition
/// 裁剪式滑出)、退场(缩放消失)都在同一个 State 里闭环。此前
/// 「RefreshIndicator.noSpinner + onStatusChange 外挂表现层」两版
/// 均翻车:SDK 的 onStatusChange 不通知 snap→refresh 与收尾→null
/// 两个转移,外挂层必然漏状态(卡半截/闪现),该路线已废弃。
///
/// 展示层(Figma「首页 · 下拉刷新中」,全平台同一个):24pt 直径、线宽 2 的
/// 圆环,放在内容区顶部一条 48 高的悬停带里居中;下拉时随进度画出圆弧,
/// 松手刷新后转动,完成后缩放收没。刷新期间列表内容整体下移一条悬停带的高度,
/// 刷新完成后回位,指示器不压在列表行上。
class M3eRefreshIndicator extends StatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  /// 指示器顶部偏移(overlay 悬浮头部下方的列表用)。
  final double edgeOffset;

  final ScrollNotificationPredicate notificationPredicate;

  const M3eRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.edgeOffset = 0.0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  @override
  State<M3eRefreshIndicator> createState() => M3eRefreshIndicatorState();
}

/// 对外状态:`GlobalKey<M3eRefreshIndicatorState>` + [show] 编程式触发。
class M3eRefreshIndicatorState extends State<M3eRefreshIndicator> {
  final GlobalKey<_M3eRefreshCoreState> _coreKey =
      GlobalKey<_M3eRefreshCoreState>();

  /// 编程式触发刷新(桌面端快捷键等)。
  Future<void> show({bool atTop = true}) {
    final core = _coreKey.currentState;
    if (core != null) return core.show(atTop: atTop);
    return widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    // 全平台走同一套自绘状态机和展示层,不随平台或 M3E 开关切换。
    return _M3eRefreshCore(
      key: _coreKey,
      onRefresh: widget.onRefresh,
      edgeOffset: widget.edgeOffset,
      notificationPredicate: widget.notificationPredicate,
      child: widget.child,
    );
  }
}

// ---- 以下为 SDK refresh_indicator.dart 的状态机移植(展示层已替换)----

/// 拖满(positionController=1)所需下拉距离占视口比例,同 SDK。
const double _kDragContainerExtentPercentage = 0.25;

/// 位移因子上限:拖到 1/1.5 即达到 armed 阈值、悬停带完全露出,同 SDK。
const double _kDragSizeFactorLimit = 1.5;

const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);

/// 指示器直径（Figma「首页 · 下拉刷新中」：24pt 圆环）。
const double _kSpinnerSize = 24;

/// 刷新中指示器所在的悬停带高度：列表内容整体下移这么多，指示器居中放在带里
/// （设计稿里指示器在分类条下方一条 48 高的带中，列表从带下面开始）。
const double _kHoverExtent = 48;

/// 圆环线宽
const double _kSpinnerStroke = 2;

/// 悬停位出现 / 收起时列表内容下移的动画时长
const Duration _kShiftInDuration = Duration(milliseconds: 150);
const Duration _kShiftOutDuration = Duration(milliseconds: 200);

class _M3eRefreshCore extends StatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;
  final double edgeOffset;
  final ScrollNotificationPredicate notificationPredicate;

  const _M3eRefreshCore({
    super.key,
    required this.child,
    required this.onRefresh,
    required this.edgeOffset,
    required this.notificationPredicate,
  });

  @override
  State<_M3eRefreshCore> createState() => _M3eRefreshCoreState();
}

class _M3eRefreshCoreState extends State<_M3eRefreshCore>
    with TickerProviderStateMixin {
  late final AnimationController _positionController;
  late final AnimationController _scaleController;

  /// 刷新期间列表内容下移的进度(0 = 原位,1 = 下移一条悬停带)
  late final AnimationController _shiftController;
  late final Animation<double> _scaleFactor;

  /// 悬停带的揭示进度:拖到 armed 阈值(1/1.5)时完全露出并不透明
  late final Animation<double> _reveal;

  RefreshIndicatorStatus? _status;
  late Future<void> _pendingRefreshFuture;
  bool? _isIndicatorAtTop;
  double? _dragOffset;

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    // 入场揭示 + 淡入:position 到达 armed 阈值(1/1.5)时拉满,
    // 对应 SDK 的 sizeFactor 与 valueColor alpha 渐变。
    _reveal = _positionController.drive(
      CurveTween(curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit)),
    );
    _shiftController = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);
    _scaleFactor = _scaleController.drive(
      Tween<double>(begin: 1.0, end: 0.0),
    );
  }

  @override
  void dispose() {
    _positionController.dispose();
    _shiftController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  bool _shouldStart(ScrollNotification notification) {
    // 仅边缘触发(SDK triggerMode.onEdge):手指驱动的 ScrollStart,
    // 且列表已贴相应边缘,且当前空闲。
    return notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        ((notification.metrics.axisDirection == AxisDirection.up &&
                notification.metrics.extentAfter == 0.0) ||
            (notification.metrics.axisDirection == AxisDirection.down &&
                notification.metrics.extentBefore == 0.0)) &&
        _status == null &&
        _start(notification.metrics.axisDirection);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;
    if (_shouldStart(notification)) {
      setState(() => _status = RefreshIndicatorStatus.drag);
      return false;
    }
    final bool? indicatorAtTopNow = switch (notification.metrics.axisDirection) {
      AxisDirection.down || AxisDirection.up => true,
      AxisDirection.left || AxisDirection.right => null,
    };
    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        _dismiss(RefreshIndicatorStatus.canceled);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.scrollDelta!;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.scrollDelta!;
        }
        _checkDragOffset(notification.metrics.viewportDimension);
      }
      if (_status == RefreshIndicatorStatus.armed &&
          notification.dragDetails == null) {
        // 手指已离开但滚动还在 ballistic:直接进入刷新。
        _show();
      }
    } else if (notification is OverscrollNotification) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.overscroll;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.overscroll;
        }
        _checkDragOffset(notification.metrics.viewportDimension);
      }
    } else if (notification is ScrollEndNotification) {
      switch (_status) {
        case RefreshIndicatorStatus.armed:
          if (_positionController.value < 1.0) {
            _dismiss(RefreshIndicatorStatus.canceled);
          } else {
            _show();
          }
        case RefreshIndicatorStatus.drag:
          _dismiss(RefreshIndicatorStatus.canceled);
        case RefreshIndicatorStatus.canceled:
        case RefreshIndicatorStatus.done:
        case RefreshIndicatorStatus.refresh:
        case RefreshIndicatorStatus.snap:
        case null:
          break;
      }
    }
    return false;
  }

  bool _handleIndicatorNotification(
    OverscrollIndicatorNotification notification,
  ) {
    if (notification.depth != 0 || !notification.leading) return false;
    if (_status == RefreshIndicatorStatus.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  bool _start(AxisDirection direction) {
    assert(_status == null);
    assert(_isIndicatorAtTop == null);
    assert(_dragOffset == null);
    switch (direction) {
      case AxisDirection.down:
      case AxisDirection.up:
        _isIndicatorAtTop = true;
      case AxisDirection.left:
      case AxisDirection.right:
        _isIndicatorAtTop = null;
        return false;
    }
    _dragOffset = 0.0;
    _scaleController.value = 0.0;
    _positionController.value = 0.0;
    return true;
  }

  void _checkDragOffset(double containerExtent) {
    assert(_status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed);
    double newValue =
        _dragOffset! / (containerExtent * _kDragContainerExtentPercentage);
    if (_status == RefreshIndicatorStatus.armed) {
      newValue = newValue.clamp(1.0 / _kDragSizeFactorLimit, double.infinity);
    }
    _positionController.value = newValue.clamp(0.0, 1.0);
    if (_status == RefreshIndicatorStatus.drag &&
        _positionController.value >= 1.0 / _kDragSizeFactorLimit) {
      _status = RefreshIndicatorStatus.armed;
      // 过阈值的"武装"时刻给一次轻触感:松手即刷新的信号。
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(newMode == RefreshIndicatorStatus.canceled ||
        newMode == RefreshIndicatorStatus.done);
    setState(() => _status = newMode);
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        // 圆环缩没和列表回位同时进行
        unawaited(
          _shiftController.animateTo(0.0, duration: _kShiftOutDuration),
        );
        await _scaleController.animateTo(
          1.0,
          duration: _kIndicatorScaleDuration,
        );
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(
          0.0,
          duration: _kIndicatorScaleDuration,
        );
      case RefreshIndicatorStatus.armed:
      case RefreshIndicatorStatus.drag:
      case RefreshIndicatorStatus.refresh:
      case RefreshIndicatorStatus.snap:
        assert(false);
    }
    if (mounted && _status == newMode) {
      _dragOffset = null;
      _isIndicatorAtTop = null;
      setState(() => _status = null);
    }
  }

  void _show() {
    assert(_status != RefreshIndicatorStatus.refresh);
    assert(_status != RefreshIndicatorStatus.snap);
    final completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    // 列表内容下移一条悬停带，给指示器让出位置
    unawaited(_shiftController.animateTo(1.0, duration: _kShiftInDuration));
    _positionController
        .animateTo(
      1.0 / _kDragSizeFactorLimit,
      duration: _kIndicatorSnapDuration,
    )
        .then<void>((void value) {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() => _status = RefreshIndicatorStatus.refresh);
        final refreshResult = widget.onRefresh();
        refreshResult.whenComplete(() {
          if (mounted && _status == RefreshIndicatorStatus.refresh) {
            completer.complete();
            _dismiss(RefreshIndicatorStatus.done);
          }
        });
      }
    });
  }

  Future<void> show({bool atTop = true}) {
    if (_status != RefreshIndicatorStatus.refresh &&
        _status != RefreshIndicatorStatus.snap) {
      if (_status == null) {
        _start(atTop ? AxisDirection.down : AxisDirection.up);
      }
      _show();
    }
    return _pendingRefreshFuture;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );
    assert(() {
      if (_status == null) {
        assert(_dragOffset == null);
        assert(_isIndicatorAtTop == null);
      } else {
        assert(_dragOffset != null);
        assert(_isIndicatorAtTop != null);
      }
      return true;
    }());

    // 与 SDK 同构:**永远**返回 Stack,指示器只是条件加入的第二个
    // child。绝不能在 _status==null 时裸返回 child —— drag 状态在
    // "列表在顶+手指拖动"就会翻转,树根形状随之改变会把整个列表
    // 子树拆掉重建(滚动位置归零、KeepAlive/GlobalKey 重挂报错)。
    // 列表内容的下移同理:Transform 永远在树里,只是位移为 0。
    final atTop = _isIndicatorAtTop ?? true;
    return Stack(
      children: <Widget>[
        AnimatedBuilder(
          animation: _shiftController,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              (atTop ? 1 : -1) * _kHoverExtent * _shiftController.value,
            ),
            child: child,
          ),
        ),
        if (_status != null)
          Positioned(
            top: atTop ? widget.edgeOffset : null,
            bottom: !atTop ? widget.edgeOffset : null,
            left: 0.0,
            right: 0.0,
            // SizeTransition 裁剪式揭示:轻拉只露悬停带的一条边,与原生同款。
            child: SizeTransition(
              alignment: AlignmentDirectional(-1.0, atTop ? 1.0 : -1.0),
              sizeFactor: _reveal,
              child: SizedBox(
                height: _kHoverExtent,
                child: Center(
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: FadeTransition(
                      opacity: _reveal,
                      child: _RefreshSpinner(
                        position: _positionController,
                        // 拖拽/取消回缩中随位移画出圆弧;松手进入 snap/refresh 后转动
                        revealing:
                            _status == RefreshIndicatorStatus.drag ||
                            _status == RefreshIndicatorStatus.armed ||
                            _status == RefreshIndicatorStatus.canceled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 24pt 圆环指示器(无托底)。
///
/// 下拉中([revealing])按位移进度画出圆弧,拉到 armed 阈值时画满;
/// 松手进入刷新后转动。
class _RefreshSpinner extends StatelessWidget {
  final Animation<double> position;
  final bool revealing;

  const _RefreshSpinner({required this.position, required this.revealing});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: _kSpinnerSize,
      height: _kSpinnerSize,
      child: revealing
          ? AnimatedBuilder(
              animation: position,
              builder: (context, _) => CircularProgressIndicator(
                key: const ValueKey('refresh-spinner-revealing'),
                // 至少留一小段弧，轻拉时也能看到
                value: (position.value * _kDragSizeFactorLimit).clamp(
                  0.05,
                  1.0,
                ),
                strokeWidth: _kSpinnerStroke,
                color: color,
              ),
            )
          : CircularProgressIndicator(
              key: const ValueKey('refresh-spinner-spinning'),
              strokeWidth: _kSpinnerStroke,
              color: color,
            ),
    );
  }
}
