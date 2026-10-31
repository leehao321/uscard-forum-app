import 'package:flutter/material.dart';

/// 长按浮起菜单里调用方追加的操作项
class PreviewAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const PreviewAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });
}
