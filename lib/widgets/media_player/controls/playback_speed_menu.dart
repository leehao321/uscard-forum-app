import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';

import '../../../l10n/s.dart';

/// 可选倍速档位(视频/音频共用)。
const kPlaybackSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// 倍速数值展示:整数档去零(1x/2x),小数档保留(0.5x/1.25x)。
String formatPlaybackSpeed(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toInt().toString()
      : speed.toString();
  return '${text}x';
}

/// 弹出倍速选择菜单(锚定在 [context] 对应的控件上),返回用户选择的
/// 倍速;取消返回 null。回调式设计,不绑任何播放器类型 —— 视频
/// (VideoPlayerController.setPlaybackSpeed)与音频(AudioPlayer.setSpeed)
/// 拿到返回值后各自应用。
Future<double?> showPlaybackSpeedMenu(
  BuildContext context, {
  required double current,
  bool darkOverlay = false,
}) {
  // 倍速菜单统一走 v2 AppMenu：当前档位打勾，不再区分媒体覆盖层的深色玻璃样式
  final anchor = globalRectOf(context);
  return showAppMenu<double>(
    context: context,
    anchor: anchor,
    sections: [
      [
        for (final speed in kPlaybackSpeedOptions)
          AppMenuItem<double>(
            label: speed == 1.0
                ? '${formatPlaybackSpeed(speed)} '
                      '(${S.current.mediaPlayer_speedNormal})'
                : formatPlaybackSpeed(speed),
            value: speed,
            checked: speed == current,
          ),
      ],
    ],
  );
}
