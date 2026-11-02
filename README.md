# Pulse Flow

Pulse Flow 是一个可以连接任意 Discourse 论坛的非官方第三方客户端，基于 Flutter 开发。
和各论坛官方没有关联。

- 首次启动时选择或填写论坛地址，每个论坛的登录状态和本机数据互相独立
- 本机笔记与摘录、阅读统计、应用锁、看过就存
- AI 总结与对话，可接入外部 MCP 工具（使用你自己的 API Key）

## 构建

需要 Flutter（版本见 `.fvmrc`）和 Rust。

```bash
git submodule update --init --recursive
dart tool/flutterw.dart build windows --debug
```

iOS 未签名包见 `.github/workflows/ios-unsigned.yaml`。

## 来源与许可

本项目基于开源项目 [FluxDO](https://github.com/Lingyan000/fluxdo)（作者 Lingyan000）修改，
遵循 GPL-3.0 协议开源，修改内容记录在 Git 历史中；`LICENSE` 和原作者的版权声明原样保留。
