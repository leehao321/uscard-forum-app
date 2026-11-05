# 私有补丁发版流程

私有代码只在本机的私有分支里，不以明文进 GitHub。发版时把它加密成补丁放进公开分支，CI 用 Secret 解开合进去再构建。
这份文档只讲流程，不含任何私有内容。

## 一次发版，三条命令

在 Git Bash 里，从 `fluxdo-shell` 的检出目录运行（要先装好 `gh` 并登录，密钥在 `~/.uscard-private/patch.key`）：

```bash
python tool/private_release.py prepare --version 1.4.4   # 本地准备，不推送
python tool/private_release.py push                       # 推送并触发构建
python tool/private_release.py fetch                      # 等构建结束，下载、解密、验包
```

`prepare` 先加 `--dry-run` 可以只检查、不改任何东西。`push --check-only` 只在 Linux 上验补丁能不能解开合入，不构建，几十秒。

`prepare` 按顺序做，任何一步不对就停下并说明原因：

1. 查环境：在 `fluxdo-shell` 上、工作区干净、密钥和私有词清单都在、私有工作区干净。
2. 版本号：`--version` 必须比现在大；和上一次补丁相同的版本会拒绝（`--allow-same-version` 才放行）。
3. 把私有分支变基到公开壳最新提交；冲突就中止，列出冲突文件，私有分支不动。
4. 私有分支的 `pubspec.yaml` 版本号必须等于公开壳的。补丁是整棵树的差异，版本号落后会把新版本号盖回去。
5. 导出补丁，再在临时工作区里解密合入，核对结果和私有分支的树逐字节一致（不含 `private/`）。
6. 扫"还没推送的提交"的提交信息、文件名、新增行，以及新提交的信息。清单在 `~/.uscard-private/private_words.txt`，不在仓库里；没有清单就不往下走。
7. 提交 `private/` 下的补丁文件。

`push` 再核对一遍（补丁版本、与私有分支一致、扫描），然后推送、触发构建、找到这次运行的编号。
`fetch` 轮询到结束，下载加密 IPA 到 `~/Downloads/pulse-flow-run-<编号>/`，解密，静态检查（应用名、包名、版本号、构建号、链接方案、后台模式、旧包名、指定的界面文字），并在公开日志里扫私有词。
界面文字用 `--expect 词1,词2` 或 `--expect-file` 指定；私有词不要写进仓库里的文件。

## 补丁文件

都在 `private/` 下：

| 文件 | 内容 | 什么时候变 |
|---|---|---|
| `code.patch.gz.enc` | 文本改动：`git diff` → gzip → 加密 | 每个版本（约 0.4 MB） |
| `assets.tar.gz.enc` | 二进制文件（字体、图片等）：tar → gzip → 加密 | 只有这些文件变了才重写 |
| `assets.id` | 上一个包的内容指纹（一串哈希） | 同上 |

二进制文件不会变，所以不会每次发版都往历史里再堆几 MB。旧的 `extras.patch.enc`（整棵树差异，不压缩，约 5.5 MB）已经停用，历史里留着的那些不会再增加。

低一层的命令在 `tool/private_patch.sh`：`export`、`check`、`apply`、`decrypt-ipa`。CI 用的 `apply` 和本机核对用的是同一段代码。

## CI

- 带私有补丁时先跑 `verify-private`（Linux，几十秒）：解密、合入；失败了不用等 macOS 机器。
- `apply` 失败时只说哪一步失败，不打印 git / tar 的原始报错，因为公开仓库的日志谁都能看，报错里有路径。本机排查加 `PRIVATE_PATCH_VERBOSE=1`。
- `check_only` 打钩：只跑 `verify-private`，不构建。

## 私有分支约定

- 只留一条私有分支（默认 `fluxdo-shell-private`），不要另开并行的副本，否则两条线各有各的历史，早晚有一条的版本号盖回另一条。
- 私有部分的笔记写在私有分支的 `docs/uscard/private-notes.md`，不要往 `fluxdo-shell-notes.md` 里追加。公开壳也会往那份文档末尾追加，两边追加同一个位置，每次变基都冲突。
- 私有分支已经基于某个公开壳提交之后，不要改写（amend / rebase）那个公开壳提交。真改写了，变基会在旧提交上冲突，用 `git rebase --onto 新提交 旧提交 私有分支` 只重放私有提交。
- 提交公开壳时，提交信息里不要出现私有功能的名字。`prepare` 和 `push` 会扫，但最好一开始就不写。
