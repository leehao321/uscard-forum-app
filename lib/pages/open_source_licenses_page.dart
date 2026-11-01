import 'package:app_icons/app_icons.dart';
import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/s.dart';

/// 一个包的全部许可：每个元素是一份许可（一组段落）。
@immutable
class PackageLicenses {
  const PackageLicenses(this.name, this.licenses);

  final String name;
  final List<List<LicenseParagraph>> licenses;

  /// 许可数量（列表副标题、详情页标题区都显示它）
  int get count => licenses.length;
}

/// 把许可条目按包名归并：一条许可里列了几个包，就给这几个包各记一份
/// （和 Flutter 自带的许可页一样）。结果按包名排序，不分大小写。
///
/// [source] 默认是 [LicenseRegistry.licenses]，测试里传假数据。
Future<List<PackageLicenses>> loadPackageLicenses({
  Stream<LicenseEntry>? source,
}) async {
  final byPackage = <String, List<List<LicenseParagraph>>>{};
  await for (final entry in source ?? LicenseRegistry.licenses) {
    final paragraphs = entry.paragraphs.toList(growable: false);
    for (final name in entry.packages) {
      byPackage.putIfAbsent(name, () => []).add(paragraphs);
    }
  }
  final names = byPackage.keys.toList()
    ..sort((a, b) {
      final c = a.toLowerCase().compareTo(b.toLowerCase());
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final n in names) PackageLicenses(n, byPackage[n]!)];
}

/// 开源许可（补充稿 54）：顶部应用名 22 + 版本 + 说明，下面是按包名排序的分组列表，
/// 每行包名 17 + 「N 份许可」13 meta + chevron；点进去看这个包的全部许可。
class OpenSourceLicensesPage extends StatefulWidget {
  const OpenSourceLicensesPage({
    super.key,
    required this.appName,
    required this.appVersion,
    this.loader,
  });

  final String appName;
  final String appVersion;

  /// 读取许可的方法；默认读 [LicenseRegistry]，测试里换成假数据
  final Future<List<PackageLicenses>> Function()? loader;

  @override
  State<OpenSourceLicensesPage> createState() => _OpenSourceLicensesPageState();
}

class _OpenSourceLicensesPageState extends State<OpenSourceLicensesPage> {
  late final Future<List<PackageLicenses>> _future =
      (widget.loader ?? loadPackageLicenses)();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(title: context.l10n.about_openSourceLicense),
      body: ReadableBody(
        child: FutureBuilder<List<PackageLicenses>>(
          future: _future,
          builder: (context, snapshot) {
            final packages = snapshot.data;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.pageMargin,
                0,
                AppSpace.pageMargin,
                bottom + AppSpace.x32,
              ),
              children: [
                // 应用信息：名称 22 Semibold、版本和说明 13 meta，居中
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Column(
                    children: [
                      Text(
                        widget.appName,
                        textAlign: TextAlign.center,
                        style: base
                            .merge(tokens.text.title)
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        context.l10n.about_licensesVersion(widget.appVersion),
                        style: meta,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(context.l10n.about_licensesTagline, style: meta),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpace.xxl,
                    bottom: AppSpace.s,
                  ),
                  child: Text(
                    context.l10n.about_licensesThirdParty,
                    style: meta,
                  ),
                ),
                if (packages == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.x40),
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else
                  _PackageList(
                    packages: packages,
                    onOpen: (p) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PackageLicensePage(package: p),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 包列表：一张分组卡片，行 64 高，行间发丝线
class _PackageList extends StatelessWidget {
  const _PackageList({required this.packages, required this.onOpen});

  final List<PackageLicenses> packages;
  final ValueChanged<PackageLicenses> onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceGrouped,
        borderRadius: BorderRadius.circular(tokens.radius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.card),
        child: Column(
          children: [
            for (var i = 0; i < packages.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpace.m),
                  child: AppHairline(),
                ),
              AppPressable(
                highlight: true,
                onTap: () => onOpen(packages[i]),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.m,
                      vertical: AppSpace.m,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                packages[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: base
                                    .merge(tokens.text.control)
                                    .copyWith(color: colors.textPrimary),
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                context.l10n.about_licensesCount(
                                  packages[i].count,
                                ),
                                style: base
                                    .merge(tokens.text.meta)
                                    .copyWith(color: colors.textMeta),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcons.chevronRight,
                          size: AppSize.iconS,
                          color: colors.textMeta,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个包的许可（补充稿 55）：标题区是包名 22 + 「N 份许可」，每份许可一张卡片，
/// 卡片上方是「许可 n / N」组页眉，正文 13，可滚动。
class PackageLicensePage extends StatelessWidget {
  const PackageLicensePage({super.key, required this.package});

  final PackageLicenses package;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.colors;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final meta = base.merge(tokens.text.meta).copyWith(color: colors.textMeta);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final total = package.count;

    return Scaffold(
      backgroundColor: colors.surfacePage,
      appBar: AppNavBar(title: package.name),
      body: ReadableBody(
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            AppSpace.pageMargin,
            0,
            AppSpace.pageMargin,
            bottom + AppSpace.x32,
          ),
          // 第 0 项是标题区，后面每份许可一项（组页眉 + 卡片）
          itemCount: total + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.s),
                child: Column(
                  children: [
                    Text(
                      package.name,
                      textAlign: TextAlign.center,
                      style: base
                          .merge(tokens.text.title)
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(context.l10n.about_licensesCount(total), style: meta),
                  ],
                ),
              );
            }
            final n = index;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpace.xxl,
                    bottom: AppSpace.s,
                  ),
                  child: Text(
                    context.l10n.about_licenseIndex(n, total),
                    style: meta,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceGrouped,
                    borderRadius: BorderRadius.circular(tokens.radius.card),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.l),
                    child: _LicenseText(paragraphs: package.licenses[n - 1]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 一份许可的正文：每段 13/16，缩进按 [LicenseParagraph.indent]，标题段居中
class _LicenseText extends StatelessWidget {
  const _LicenseText({required this.paragraphs});

  final List<LicenseParagraph> paragraphs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.bodyMedium!
        .merge(tokens.text.meta)
        .copyWith(color: tokens.colors.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: i == 0 ? 0 : AppSpace.s,
              start: paragraphs[i].indent > 0
                  ? AppSpace.l * paragraphs[i].indent
                  : 0,
            ),
            child: Text(
              paragraphs[i].text,
              textAlign: paragraphs[i].indent == LicenseParagraph.centeredIndent
                  ? TextAlign.center
                  : TextAlign.start,
              style: style,
            ),
          ),
      ],
    );
  }
}
