#!/usr/bin/env bash
# 镜像功能的加密补丁：镜像代码只在本地分支 uscard-mirror，不以明文进入 GitHub。
#
# 用法（在仓库根目录的 Git Bash 里）：
#   tool/mirror_patch.sh keygen        生成密钥，保存到仓库外的 ~/.uscard-mirror/patch.key
#   tool/mirror_patch.sh export        把 uscard-mirror 相对 uscard 的改动加密成 private/mirror.patch.enc
#   tool/mirror_patch.sh check         在临时工作区里解密并试合入，确认补丁能用
#   tool/mirror_patch.sh decrypt-ipa <文件.enc>   解密 Actions 下载的加密 IPA（或加密的构建日志 build.log.enc）
#
# 密钥也可以用环境变量 MIRROR_PATCH_KEY 传入。GitHub Actions 里用同名 Secret。
set -euo pipefail

KEY_FILE="${MIRROR_PATCH_KEY_FILE:-$HOME/.uscard-mirror/patch.key}"
BASE_BRANCH="${MIRROR_BASE_BRANCH:-uscard}"
MIRROR_BRANCH="${MIRROR_BRANCH:-uscard-mirror}"
OUT="private/mirror.patch.enc"
# 与 .github/workflows/ios-unsigned.yaml 保持一致
ENC_ARGS=(-aes-256-cbc -pbkdf2 -iter 200000 -md sha256)

die() { echo "错误：$*" >&2; exit 1; }

load_key() {
  if [ -n "${MIRROR_PATCH_KEY:-}" ]; then return; fi
  [ -f "$KEY_FILE" ] || die "没有密钥：先运行 tool/mirror_patch.sh keygen"
  MIRROR_PATCH_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
  export MIRROR_PATCH_KEY
}

case "${1:-}" in
  keygen)
    [ -f "$KEY_FILE" ] && die "密钥已存在：$KEY_FILE（要换密钥请先手动删掉它）"
    mkdir -p "$(dirname "$KEY_FILE")"
    openssl rand -base64 48 | tr -d '\r\n' > "$KEY_FILE"
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    echo "已生成密钥：$KEY_FILE"
    echo "把它设置成仓库的 Actions Secret（名字 MIRROR_PATCH_KEY）后，构建时才能解密。"
    ;;

  export)
    load_key
    git rev-parse --verify -q "$MIRROR_BRANCH" >/dev/null || die "没有本地分支 $MIRROR_BRANCH"
    base="$(git merge-base "$BASE_BRANCH" "$MIRROR_BRANCH")"
    if [ "$base" != "$(git rev-parse "$BASE_BRANCH")" ]; then
      die "$MIRROR_BRANCH 不是基于最新的 $BASE_BRANCH，先运行：git rebase $BASE_BRANCH $MIRROR_BRANCH"
    fi
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    # 固定成 git apply 认得的格式：不套本机的 textconv / 外部 diff / 颜色 / 前缀配置
    git -C "$(git rev-parse --show-toplevel)" diff --binary --no-textconv --no-ext-diff \
      --no-color --src-prefix=a/ --dst-prefix=b/ \
      "$BASE_BRANCH" "$MIRROR_BRANCH" -- . ":(exclude)$OUT" > "$tmp"
    [ -s "$tmp" ] || die "$MIRROR_BRANCH 和 $BASE_BRANCH 没有差别"
    mkdir -p "$(dirname "$OUT")"
    openssl enc "${ENC_ARGS[@]}" -salt -in "$tmp" -out "$OUT" -pass env:MIRROR_PATCH_KEY
    echo "已生成 $OUT（$(wc -c < "$OUT") 字节，对应 $BASE_BRANCH $(git rev-parse --short "$BASE_BRANCH")）"
    echo "下一步：在 $BASE_BRANCH 上提交 $OUT，push 后手动触发 iOS 构建并勾选「带镜像功能」。"
    ;;

  check)
    load_key
    [ -f "$OUT" ] || die "没有 $OUT，先运行 export"
    wt="$(mktemp -d)"
    trap 'git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"' EXIT
    git worktree add --detach -q "$wt" "$BASE_BRANCH"
    openssl enc -d "${ENC_ARGS[@]}" -in "$OUT" -pass env:MIRROR_PATCH_KEY \
      | git -C "$wt" apply --whitespace=nowarn
    [ -d "$wt/lib/mirror" ] || die "解密合入后没有 lib/mirror"
    echo "补丁可以解密，并能干净地合入 $BASE_BRANCH。"
    ;;

  decrypt-ipa)
    load_key
    in="${2:-}"
    [ -f "$in" ] || die "用法：tool/mirror_patch.sh decrypt-ipa <文件.ipa.enc>"
    out="${in%.enc}"
    [ "$out" = "$in" ] && out="$in.ipa"
    openssl enc -d "${ENC_ARGS[@]}" -in "$in" -out "$out" -pass env:MIRROR_PATCH_KEY
    echo "已解密：$out"
    ;;

  *)
    sed -n '2,11p' "$0"
    exit 1
    ;;
esac
