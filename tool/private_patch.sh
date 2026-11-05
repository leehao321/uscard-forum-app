#!/usr/bin/env bash
# 私有补丁：私有代码只在本地分支，不以明文进入 GitHub；这里负责把它加密成补丁文件，并在构建时合回来。
#
# 用法（在仓库根目录的 Git Bash 里；发版请优先用 tool/private_release.py，它会按顺序调这里的命令）：
#   tool/private_patch.sh keygen --force-new-key   生成新密钥（会让现有补丁和 CI Secret 失效，平时不要运行）
#   tool/private_patch.sh export        把私有分支相对基线分支的改动加密成 private/ 下的文件
#   tool/private_patch.sh check         在临时工作区里解密并合入，核对结果和私有分支的树逐字节一致
#   tool/private_patch.sh apply         把 private/ 下的补丁合入当前工作区（CI 构建用，失败时不在日志里露出路径）
#   tool/private_patch.sh decrypt-ipa <文件.enc>   解密 Actions 下载的加密 IPA（或加密的构建日志 build.log.enc）
#
# 文件布局（都在 private/ 下）：
#   code.patch.gz.enc   文本改动：git diff → gzip → 加密
#   assets.tar.gz.enc   二进制文件（字体、图片等）：tar → gzip → 加密。内容没变就不重写，不会往历史里再堆一份
#   assets.id           上一个包的内容指纹（一串哈希，明文）
#
# 环境变量：PRIVATE_BASE_BRANCH（默认 fluxdo-shell）、PRIVATE_BRANCH（默认 fluxdo-shell-private）、
#   PRIVATE_PATCH_KEY 或 PRIVATE_PATCH_KEY_FILE（密钥）、OPENSSL（指定 openssl 3 的路径）、
#   PRIVATE_OUT_DIR（export 写到哪里，默认 private）、PRIVATE_PATCH_VERBOSE=1（apply 失败时显示详细错误）
#
# 注意：apply 要在 macOS 自带的 bash 3.2 上跑，所以这里避免用 bash 4 才有的写法。
set -euo pipefail

KEY_FILE="${PRIVATE_PATCH_KEY_FILE:-$HOME/.uscard-private/patch.key}"
BASE_BRANCH="${PRIVATE_BASE_BRANCH:-fluxdo-shell}"
PRIVATE_BRANCH="${PRIVATE_BRANCH:-fluxdo-shell-private}"
OPENSSL_BIN="${OPENSSL:-openssl}"
DIR="${PRIVATE_OUT_DIR:-private}"
PATCH_FILE="code.patch.gz.enc"
ASSET_FILE="assets.tar.gz.enc"
ASSET_ID_FILE="assets.id"
OLD_PATCH_FILE="extras.patch.enc"
# 与 .github/workflows/ios-unsigned.yaml 里加密 IPA 的参数保持一致
ENC_ARGS=(-aes-256-cbc -pbkdf2 -iter 200000 -md sha256)

CLEAN_FILES=""
CLEAN_WT=""

die() { echo "错误：$*" >&2; exit 1; }

cleanup() {
  local f
  for f in $CLEAN_FILES; do rm -rf "$f"; done
  if [ -n "$CLEAN_WT" ]; then
    git worktree remove --force "$CLEAN_WT" >/dev/null 2>&1 || rm -rf "$CLEAN_WT"
  fi
}
trap cleanup EXIT

# 建一个临时文件并登记到退出时清理；结果写进名为 $1 的变量（用 $(...) 取值会在子进程里丢掉登记）
mktmp() {
  local t
  t="$(mktemp "${TMPDIR:-/tmp}/pp.XXXXXX")"
  CLEAN_FILES="$CLEAN_FILES $t"
  printf -v "$1" '%s' "$t"
}

load_key() {
  if [ -n "${PRIVATE_PATCH_KEY:-}" ]; then return; fi
  [ -f "$KEY_FILE" ] || die "没有密钥：先运行 tool/private_patch.sh keygen"
  PRIVATE_PATCH_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
  export PRIVATE_PATCH_KEY
}

encrypt() { "$OPENSSL_BIN" enc "${ENC_ARGS[@]}" -salt -pass env:PRIVATE_PATCH_KEY "$@"; }
decrypt() { "$OPENSSL_BIN" enc -d "${ENC_ARGS[@]}" -pass env:PRIVATE_PATCH_KEY "$@"; }

# 合入 $1 目录里的补丁和二进制资源，到当前目录。
# 公开仓库的 Actions 日志谁都能看，所以失败时只说哪一步失败，不打印 git / tar 的原始报错（里面有路径）。
do_apply() {
  local src="$1" have=0 errlog
  mktmp errlog
  fail_apply() {
    echo "错误：$1 合入失败。为避免在公开日志里露出路径，详细错误已隐藏；在本机加 PRIVATE_PATCH_VERBOSE=1 重新运行可以看到。" >&2
    if [ "${PRIVATE_PATCH_VERBOSE:-}" = "1" ]; then cat "$errlog" >&2; fi
    rm -f "$errlog"
    exit 1
  }
  if [ -f "$src/$PATCH_FILE" ]; then
    have=1
    if ! { decrypt -in "$src/$PATCH_FILE" | gzip -dc | git -c core.autocrlf=false apply --whitespace=nowarn; } 2>"$errlog"; then
      fail_apply "文本补丁"
    fi
  fi
  if [ -f "$src/$ASSET_FILE" ]; then
    have=1
    if ! { decrypt -in "$src/$ASSET_FILE" | gzip -dc | tar -xf -; } 2>"$errlog"; then
      fail_apply "二进制资源"
    fi
  fi
  rm -f "$errlog"
  [ "$have" = "1" ] || die "$src 里没有 $PATCH_FILE，也没有 $ASSET_FILE"
}

# 私有分支相对基线分支，新增或修改的二进制文件（git 的 numstat 对二进制文件显示 "-"）。
# 输出以 NUL 分隔的路径。重命名按"删除 + 新增"处理，这样新增的二进制文件一定落在这个清单里。
list_binary_changes() {
  git diff --no-renames --diff-filter=AM --numstat -z "$BASE_BRANCH" "$PRIVATE_BRANCH" -- . ':(exclude)private' \
    | while IFS= read -r -d '' rec; do
        case "$rec" in
          $'-\t-\t'*) printf '%s\0' "${rec#$'-\t-\t'}" ;;
        esac
      done
}

# 去掉 private/ 目录后的树：补丁文件本身不算内容差异，比较两棵树时要先排除。
tree_without_private() {
  local rev="$1" idx tree
  idx="${TMPDIR:-/tmp}/pp-idx.$$.$RANDOM"
  GIT_INDEX_FILE="$idx" git read-tree "$rev"
  GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch private >/dev/null
  tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
  rm -f "$idx"
  echo "$tree"
}

cmd_export() {
  load_key
  git rev-parse --verify -q "$PRIVATE_BRANCH" >/dev/null || die "没有本地分支 $PRIVATE_BRANCH"
  git rev-parse --verify -q "$BASE_BRANCH" >/dev/null || die "没有本地分支 $BASE_BRANCH"
  local base
  base="$(git merge-base "$BASE_BRANCH" "$PRIVATE_BRANCH")"
  if [ "$base" != "$(git rev-parse "$BASE_BRANCH")" ]; then
    die "$PRIVATE_BRANCH 不是基于最新的 $BASE_BRANCH，先变基：git rebase $BASE_BRANCH $PRIVATE_BRANCH（补丁是整棵树的差异，基线落后会把公开壳的改动盖回去）"
  fi
  cd "$(git rev-parse --show-toplevel)"

  # 1. 二进制文件单独打包
  local assets=() excludes=() p
  while IFS= read -r -d '' p; do
    assets+=("$p")
    excludes+=(":(exclude,literal)$p")
  done < <(list_binary_changes)

  # 2. 其余改动做成文本补丁。-- 之后必须带 pathspec，所以排除项放最后
  local patch_tmp
  mktmp patch_tmp
  git diff --binary --no-renames --no-textconv --no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/ \
    "$BASE_BRANCH" "$PRIVATE_BRANCH" -- . ':(exclude)private' ${excludes[@]+"${excludes[@]}"} > "$patch_tmp"

  mkdir -p "$DIR"
  rm -f "$DIR/$OLD_PATCH_FILE"
  if [ -s "$patch_tmp" ]; then
    gzip -n -9 -c "$patch_tmp" | encrypt -out "$DIR/$PATCH_FILE"
  else
    rm -f "$DIR/$PATCH_FILE"
  fi

  if [ "${#assets[@]}" -gt 0 ]; then
    local id
    id="$(git ls-tree -r "$PRIVATE_BRANCH" -- "${assets[@]}" | sha256sum | cut -d' ' -f1)"
    if [ -f "$DIR/$ASSET_FILE" ] && [ "$(cat "$DIR/$ASSET_ID_FILE" 2>/dev/null || true)" = "$id" ]; then
      echo "二进制资源没变（${#assets[@]} 个文件），沿用现有的 $ASSET_FILE，不重写。"
    else
      local stage
      mktmp stage; rm -f "$stage"; mkdir -p "$stage"
      for p in "${assets[@]}"; do
        mkdir -p "$stage/$(dirname "$p")"
        git cat-file blob "$PRIVATE_BRANCH:$p" > "$stage/$p"
      done
      tar -cf - -C "$stage" . | gzip -n -9 | encrypt -out "$DIR/$ASSET_FILE"
      printf '%s\n' "$id" > "$DIR/$ASSET_ID_FILE"
      echo "二进制资源已重新打包（${#assets[@]} 个文件）。"
    fi
  else
    rm -f "$DIR/$ASSET_FILE" "$DIR/$ASSET_ID_FILE"
  fi

  [ -f "$DIR/$PATCH_FILE" ] || [ -f "$DIR/$ASSET_FILE" ] || die "$PRIVATE_BRANCH 和 $BASE_BRANCH 没有差别"
  local f
  for f in "$PATCH_FILE" "$ASSET_FILE"; do
    [ -f "$DIR/$f" ] && echo "已生成 $DIR/$f（$(wc -c < "$DIR/$f") 字节）"
  done
  echo "对应 $BASE_BRANCH $(git rev-parse --short "$BASE_BRANCH")。"
  return 0
}

cmd_check() {
  load_key
  git rev-parse --verify -q "$PRIVATE_BRANCH" >/dev/null || die "没有本地分支 $PRIVATE_BRANCH"
  cd "$(git rev-parse --show-toplevel)"
  local src wt
  src="$(cd "$DIR" && pwd)"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/pp-check.XXXXXX")"
  CLEAN_WT="$wt"
  # 临时工作区一律不转换换行（本机的 core.autocrlf=true 会让树对不上）
  git -c core.autocrlf=false worktree add --detach -q "$wt" "$BASE_BRANCH"
  ( cd "$wt" && do_apply "$src" )
  git -c core.autocrlf=false -C "$wt" add -A
  git -C "$wt" rm -r -q --cached --ignore-unmatch private >/dev/null
  local got want
  got="$(git -C "$wt" write-tree)"
  want="$(tree_without_private "$PRIVATE_BRANCH")"
  if [ "$got" != "$want" ]; then
    echo "合入后的树 $got" >&2
    echo "私有分支的树 $want" >&2
    git diff --stat "$got" "$want" | tail -8 >&2 || true
    die "补丁合入后和 $PRIVATE_BRANCH 不一致：多半是 $PRIVATE_BRANCH 没有基于最新的 $BASE_BRANCH，或者补丁是旧的，重新 export。"
  fi
  echo "补丁通过：能解密、能合入 $BASE_BRANCH，合入后的树与 $PRIVATE_BRANCH 完全一致（$got，不含 private/）。"
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

  export) cmd_export ;;
  check) cmd_check ;;

  apply)
    load_key
    do_apply "${2:-$DIR}"
    echo "私有补丁已合入。"
    ;;

  decrypt-ipa)
    load_key
    in="${2:-}"
    [ -f "$in" ] || die "用法：tool/private_patch.sh decrypt-ipa <文件.ipa.enc>"
    out="${in%.enc}"
    [ "$out" = "$in" ] && out="$in.ipa"
    decrypt -in "$in" -out "$out"
    echo "已解密：$out"
    ;;

  *)
    sed -n '2,24p' "$0"
    exit 1
    ;;
esac
