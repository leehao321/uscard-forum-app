# USCard Forum

> 美卡论坛（[uscardforum.com](https://www.uscardforum.com)）的**非官方**第三方客户端，基于 Flutter 开发。
>
> 本项目基于开源项目 [FluxDO](https://github.com/Lingyan000/fluxdo) 修改，与美卡论坛官方及 FluxDO 原作者无关。
> 遵循 GPL-3.0 协议开源；`LICENSE` 与原作者版权声明原样保留。

## 下载

安装包发布在本仓库的 [GitHub Releases](https://github.com/leehao321/uscard-forum-app/releases)；也可以按下方「快速开始」自行构建。

## 特性

### 核心功能
- **跨平台支持**：Android、iOS、Windows、macOS、Linux
- **Material Design 3**：现代化 UI 设计，支持动态取色
- **深色模式**：自动适配系统主题
- **完整论坛功能**：浏览话题、发帖回复、搜索、通知
- **内容管理**：书签、浏览历史、关注列表
- **徽章系统**：查看和展示社区徽章
- **Markdown 编辑器**：支持富文本编辑和预览
- **图片支持**：图片上传、查看、保存
- **投票功能**：参与社区投票

### 技术特性
- **安全连接**：集成 Rust 实现的 DOH (DNS over HTTPS) 代理
- **性能优化**：图片缓存、懒加载、代码高亮
- **实时通知**：MessageBus 实时消息推送
- **智能渲染**：HTML 内容分块渲染，流畅滚动

## 快速开始

### 前置要求

- Flutter SDK（Dart ^3.13.0）
- Rust 工具链（用于编译 DOH 代理）
- Android Studio / Xcode（移动端开发）

### 安装步骤

1. **克隆仓库（含子模块）**
   ```bash
   git clone --recurse-submodules https://github.com/leehao321/uscard-forum-app.git
   cd uscard-forum-app
   ```

2. **初始化工作区**
   ```bash
   melos bootstrap
   ```
   如果没有安装全局 `melos`，可改用 `dart run melos bootstrap`。
   这一步只负责 workspace 依赖和链接初始化。

3. **安装 `just`**
   - Windows：`winget install --id Casey.Just --exact`
   - Windows：`scoop install just`
   - Windows：`choco install just`
   - 通用：`cargo install just`

4. **同步项目状态**
   ```bash
   just sync
   ```
   这一步会统一完成 `flutter pub get`、l10n 生成和代理证书资源同步。

5. **运行应用**
   ```bash
   just run -- -d windows
   just run -- -d macos
   just run -- --dart-define=cronetHttpNoPlay=true
   ```

   如果你不想安装 `just`，也可以直接调用 Dart 入口：
   ```bash
   dart run tool/project_prep.dart app
   dart run tool/flutterw.dart run -d windows
   ```

## 开发

开发相关的工程化细节已经拆到独立文档，根 README 只保留最短路径。

- [开发环境与日常命令](docs/development.md)
- [发版与 iOS IPA](docs/release.md)
- [Flatpak 打包说明](docs/flatpak.md)

## 项目结构

```
uscard-forum-app/
├── lib/
│   ├── config/              # 应用配置（站点定制见 config/sites/）
│   ├── models/              # 数据模型（话题、用户、通知等）
│   ├── pages/               # 页面组件
│   ├── providers/           # Riverpod 状态管理
│   ├── services/            # 业务逻辑服务
│   │   ├── network/         # 网络层（DOH、代理、适配器）
│   │   └── ...
│   ├── utils/               # 工具类
│   ├── widgets/             # 可复用组件
│   └── main.dart
├── core/
│   └── doh_proxy/           # Rust DOH 代理实现（子模块）
├── packages/                # 本地依赖包
├── scripts/
│   └── ci/                  # CI / 打包链路内部脚本
└── pubspec.yaml
```

## 技术栈

- **前端框架**：Flutter
- **状态管理**：Riverpod
- **网络请求**：Dio（Native Dio Adapter / rhttp 适配器）
- **HTML 渲染**：fluxdo_render（子模块 `packages/fluxdo_render`）
- **代码高亮**：re_highlight + google_fonts (FiraCode)
- **图片处理**：extended_image_lite（本地包 `packages/extended_image_lite`）+ flutter_cache_manager
- **本地存储**：shared_preferences + flutter_secure_storage
- **网络代理**：Rust (DOH + ECH)

## DOH 代理功能

应用集成了基于 Rust 的 DOH (DNS over HTTPS) 代理（沿用上游 FluxDO 的实现），提供：

- **DNS 加密查询**：防止 DNS 污染和劫持
- **多服务器支持**：DNSPod、腾讯 DNS、阿里 DNS、Cloudflare、Canadian Shield、Google、Quad9
- **ECH 支持**：加密 TLS 握手中的 SNI 字段（用户无感知）
- **跨平台实现**：
  - Android/iOS：FFI 调用
  - Windows/macOS/Linux：独立进程

详细文档请参考 [core/doh_proxy/README.md](https://github.com/Lingyan000/fluxdo_doh)

## 关于美卡论坛

[美卡论坛](https://www.uscardforum.com)（USCard Forum）是讨论美国信用卡、银行与积分里程等话题的中文社区。

**注意**：本项目为非官方客户端，与美卡论坛官方无关。

## 问题反馈

如果您在使用过程中遇到问题或有建议，欢迎提交 [Issue](https://github.com/leehao321/uscard-forum-app/issues)。

## 开源协议

本项目基于 [GPL-3.0](LICENSE) 协议开源。

## 致谢

感谢 [FluxDO](https://github.com/Lingyan000/fluxdo) 的作者与贡献者，本项目在其基础上修改而来。

## 相关文档

- [开发环境与日常命令](docs/development.md)
- [Flatpak 打包说明](docs/flatpak.md)
- [发版与 iOS IPA](docs/release.md)
