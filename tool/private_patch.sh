#!/usr/bin/env bash
# 私有补丁：私有代码只在本地分支，不以明文进入 GitHub；这里负责把它加密成补丁文件。
#
# 用法（在仓库根目录的 Git Bash 里）：
#   tool/private_patch.sh keygen --force-new-key   生成新密钥（会让现有补丁和 CI Secret 失效，平时不要运行）
#   tool/private_patch.sh export        把私有分支（PRIVATE_BRANCH 指定）相对 uscard 的改动加密成 private/extras.patch.enc
#   tool/private_patch.sh check         在临时工作区里解密并试合入，确认补丁能用
#   tool/private_patch.sh decrypt-ipa <文件.enc>   解密 Actions 下载的加密 IPA（或加密的构建日志 build.log.enc）
#
# 密钥也可以用环境变量 PRIVATE_PATCH_KEY 传入。GitHub Actions 里用同名 Secret。
# 导出时要用环境变量 PRIVATE_BRANCH 指定本地私有分支名。
set -euo pipefail

KEY_FILE="${PRIVATE_PATCH_KEY_FILE:-$HOME/.uscard-private/patch.key}"
BASE_BRANCH="${PRIVATE_BASE_BRANCH:-uscard}"
PRIVATE_BRANCH="${PRIVATE_BRANCH:-}"
OUT="private/extras.patch.enc"
# 与 .github/workflows/ios-unsigned.yaml 保持一致
ENC_ARGS=(-aes-256-cbc -pbkdf2 -iter 200000 -md sha256)

die() { echo "错误：$*" >&2; exit 1; }

load_key() {
  if [ -n "${PRIVATE_PATCH_KEY:-}" ]; then return; fi
  [ -f "$KEY_FILE" ] || die "没有密钥：先运行 tool/private_patch.sh keygen"
  PRIVATE_PATCH_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
  export PRIVATE_PATCH_KEY
}

case "${1:-}" in
  keygen)
    [ -f "$KEY_FILE" ] && die "密钥已存在：$KEY_FILE（要换密钥请先手动删掉它）"
    # 换密钥后，CI 的 Secret 和现有的加密补丁都会解不开，所以要显式确认
    if [ "${2:-}" != "--force-new-key" ]; then
      die "生成新密钥会让现有的加密补丁和 CI Secret 全部失效。确实要换：tool/private_patch.sh keygen --force-new-key；换完必须同步更新 CI Secret 并重新导出补丁"
    fi
    mkdir -p "$(dirname "$KEY_FILE")"
    openssl rand -base64 48 | tr -d '\r\n' > "$KEY_FILE"
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    echo "已生成密钥：$KEY_FILE"
    echo "把它设置成仓库的 Actions Secret（名字 PRIVATE_PATCH_KEY）后，构建时才能解密。"
    ;;

  export)
    load_key
    [ -n "$PRIVATE_BRANCH" ] || die "先用环境变量 PRIVATE_BRANCH 指定本地私有分支名"
    git rev-parse --verify -q "$PRIVATE_BRANCH" >/dev/null || die "没有本地分支 $PRIVATE_BRANCH"
    base="$(git merge-base "$BASE_BRANCH" "$PRIVATE_BRANCH")"
    if [ "$base" != "$(git rev-parse "$BASE_BRANCH")" ]; then
      die "$PRIVATE_BRANCH 不是基于最新的 $BASE_BRANCH，先运行：git rebase $BASE_BRANCH $PRIVATE_BRANCH"
    fi
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    # 固定成 git apply 认得的格式：不套本机的 textconv / 外部 diff / 颜色 / 前缀配置
    git -C "$(git rev-parse --show-toplevel)" diff --binary --no-textconv --no-ext-diff \
      --no-color --src-prefix=a/ --dst-prefix=b/ \
      "$BASE_BRANCH" "$PRIVATE_BRANCH" -- . ":(exclude)$OUT" > "$tmp"
    [ -s "$tmp" ] || die "$PRIVATE_BRANCH 和 $BASE_BRANCH 没有差别"
    mkdir -p "$(dirname "$OUT")"
    openssl enc "${ENC_ARGS[@]}" -salt -in "$tmp" -out "$OUT" -pass env:PRIVATE_PATCH_KEY
    echo "已生成 $OUT（$(wc -c < "$OUT") 字节，对应 $BASE_BRANCH $(git rev-parse --short "$BASE_BRANCH")）"
    echo "下一步：在 $BASE_BRANCH 上提交 $OUT，push 后手动触发 iOS 构建并勾选「带私有补丁」。"
    ;;

  check)
    load_key
    [ -f "$OUT" ] || die "没有 $OUT，先运行 export"
    wt="$(mktemp -d)"
    trap 'git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"' EXIT
    git worktree add --detach -q "$wt" "$BASE_BRANCH"
    openssl enc -d "${ENC_ARGS[@]}" -in "$OUT" -pass env:PRIVATE_PATCH_KEY \
      | git -C "$wt" apply --whitespace=nowarn
    echo "补丁可以解密，并能干净地合入 $BASE_BRANCH。"
    ;;

  decrypt-ipa)
    load_key
    in="${2:-}"
    [ -f "$in" ] || die "用法：tool/private_patch.sh decrypt-ipa <文件.ipa.enc>"
    out="${in%.enc}"
    [ "$out" = "$in" ] && out="$in.ipa"
    openssl enc -d "${ENC_ARGS[@]}" -in "$in" -out "$out" -pass env:PRIVATE_PATCH_KEY
    echo "已解密：$out"
    ;;

  *)
    sed -n '2,11p' "$0"
    exit 1
    ;;
esac
