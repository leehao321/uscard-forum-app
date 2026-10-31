import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// 未读点：8×8 brand/primary 圆。装饰性的，不朗读（「未读」由所在行读出）。
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.size = AppSize.unreadDot, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? context.tokens.colors.brandPrimary,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

/// 字母头像：avatar/fill 圆 + 首字母（34 / 40 为 17 Semibold，64 为
/// 22 Semibold），字母是 text/meta。
///
/// 字母是图形不是正文，不跟系统字号缩放（计划 §8）。有图片时显示图片，
/// 加载失败回退到字母。默认不朗读（头像旁边一般就是名字）。
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({
    super.key,
    required this.name,
    this.size = AppSize.avatarS,
    this.image,
    this.semanticLabel,
  });

  final String name;
  final double size;
  final ImageProvider? image;

  /// 需要单独朗读时传（例如只有头像没有名字的入口）
  final String? semanticLabel;

  static String letterOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final large = size >= AppSize.avatarL;
    final style = Theme.of(context).textTheme.bodyMedium!
        .merge(large ? tokens.text.title : tokens.text.headline)
        .copyWith(color: tokens.colors.textMeta);
    final letter = Center(
      child: Text(
        letterOf(name),
        style: style,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      ),
    );
    final image = this.image;
    final child = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.avatarFill,
          shape: BoxShape.circle,
        ),
        child: image == null
            ? letter
            : ClipOval(
                child: Image(
                  image: image,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => letter,
                ),
              ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: child);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: child),
    );
  }
}
