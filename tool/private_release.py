#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""私有补丁发版助手：把"变基、导出、核对、扫私有词、提交、推送、触发构建、下载、验包"串成几条命令。

在 Git Bash 里，从 fluxdo-shell 的检出目录运行：

  python tool/private_release.py prepare [--version 1.4.4] [--dry-run]   本地准备，不推送
  python tool/private_release.py push [--check-only]                    推送并触发构建（--check-only 只验补丁，不构建）
  python tool/private_release.py fetch [RUN_ID] [--expect 词1,词2]       等构建结束，下载、解密、验包
  python tool/private_release.py push --walk [--only shell]            推送并只跑模拟器走查（不打包）
  python tool/private_release.py walk [--only shell]                   不推送，用远端现在的补丁再跑一次模拟器走查
  python tool/private_release.py fetch-walk [RUN_ID]                   等走查结束，下载、解密、解开截图和报告
  python tool/private_release.py self-test                              自测里面的小函数

前提：
  - 当前在 fluxdo-shell 分支，工作区干净；私有分支（默认 fluxdo-shell-private）在某个工作区里检出着。
  - 密钥在 ~/.uscard-private/patch.key。
  - 私有词清单在 ~/.uscard-private/private_words.txt（一行一个正则，# 开头是注释）。清单故意不放进仓库：
    清单本身就含私有词。没有它，prepare 和 push 都会直接停下，不会"没扫就推"。

prepare 做的事，任何一步不对就停下并说明原因：
  1. 查环境：分支、工作区、密钥、私有词清单、私有分支的工作区是否干净
  2. 版本号：给了 --version 就升（必须比现在大）并提交；没给就用现在的；和上一次补丁的版本相同会拒绝
  3. 把私有分支变基到公开壳最新提交（冲突就中止并列出冲突文件）
  4. 私有分支的 pubspec 版本号必须等于公开壳的（防止旧版本号盖回去）
  5. 导出补丁，再在临时工作区里解密合入，核对结果和私有分支的树逐字节一致
  6. 扫"还没推送的提交"的提交信息、文件名、新增行，以及新提交的信息，命中私有词就停
  7. 提交 private/ 下的补丁文件

--dry-run 只做检查，不改任何分支、不写 private/、不提交。
"""
import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

SECRET_DIR = Path.home() / '.uscard-private'
WORDS_FILE = SECRET_DIR / 'private_words.txt'
KEY_FILE = SECRET_DIR / 'patch.key'
BASE = os.environ.get('PRIVATE_BASE_BRANCH', 'fluxdo-shell')
PRIVATE = os.environ.get('PRIVATE_BRANCH', 'fluxdo-shell-private')
WORKFLOW = 'ios-unsigned.yaml'
ARTIFACT = 'pulse-flow-unsigned-ipa-encrypted'
LOG_ARTIFACT = 'pulse-flow-build-log-encrypted'
WALK_WORKFLOW = 'ios-walk.yaml'
WALK_ARTIFACT = 'pulse-flow-walk-encrypted'
APP_NAME = 'Pulse Flow'
BUNDLE_ID = 'com.hao.pulseflow'
OLD_BUNDLE_ID = b'com.hao.uscard'
SCHEMES = {'pulseflow', 'discourse'}
NL_INDENT = '\n    '


class Fail(Exception):
    pass


def die(msg):
    raise Fail(msg)


def step(msg):
    print('• ' + msg, flush=True)


def ok(msg):
    print('  ✓ ' + msg, flush=True)


def note(msg):
    print('  - ' + msg, flush=True)


def run(cmd, cwd=None, check=True, env=None, stream=False):
    if stream:
        r = subprocess.run(cmd, cwd=cwd, env=env)
        if check and r.returncode != 0:
            die('命令失败：' + ' '.join(str(c) for c in cmd[:4]))
        return r
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if check and r.returncode != 0:
        tail = ((r.stderr or '') + (r.stdout or '')).strip()[-800:]
        die('命令失败：' + ' '.join(str(c) for c in cmd[:5]) + '\n' + tail)
    return r


def git(*args, cwd=None, check=True):
    return run(['git', '-c', 'core.quotepath=off', *args], cwd=cwd, check=check).stdout.strip()


def gh(*args, check=True):
    return run(['gh', *args], check=check).stdout


def find_bash():
    if os.name != 'nt':
        return shutil.which('bash') or 'bash'
    cands = []
    g = shutil.which('git')
    if g:
        p = Path(g).resolve()
        cands += [p.parent.parent / 'bin' / 'bash.exe', p.parent.parent.parent / 'bin' / 'bash.exe']
    cands += [Path(r'C:\Program Files\Git\bin\bash.exe')]
    for c in cands:
        if c.exists():
            return str(c)
    return shutil.which('bash') or 'bash'


def repo_slug():
    url = git('remote', 'get-url', 'origin')
    m = re.search(r'github\.com[:/]+([^/]+/[^/.]+)', url)
    if not m:
        die('认不出 origin 的 GitHub 仓库：' + url)
    return m.group(1)


# ---------- 版本号 ----------

VER_RE = re.compile(r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)', re.M)


def read_version(text):
    m = VER_RE.search(text)
    if not m:
        die('pubspec.yaml 里找不到 version: X.Y.Z+N')
    return tuple(int(x) for x in m.groups())


def version_label(v):
    return '%d.%d.%d' % v[:3]


def bump_version_text(text, ver3, build):
    return VER_RE.sub('version: %d.%d.%d+%d' % (ver3[0], ver3[1], ver3[2], build), text, count=1)


def parse_ver3(s):
    m = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)', s.strip())
    if not m:
        die('版本号要写成 X.Y.Z：' + s)
    return tuple(int(x) for x in m.groups())


def last_patch_version():
    """上一次"更新私有补丁"提交信息里写的版本号。"""
    out = git('log', '-n', '1', '--format=%s', '--grep=更新私有补丁')
    m = re.search(r'v(\d+\.\d+\.\d+)', out)
    return m.group(1) if m else None


# ---------- 私有词 ----------

def load_words():
    if not WORDS_FILE.exists():
        die('没有私有词清单：%s\n    请先创建它（一行一个正则）。没有它就没法扫，所以这里直接停。' % WORDS_FILE)
    lines = [l.strip() for l in WORDS_FILE.read_text(encoding='utf-8').splitlines()
             if l.strip() and not l.lstrip().startswith('#')]
    if not lines:
        die('私有词清单是空的：' + str(WORDS_FILE))
    return re.compile('|'.join(lines))


def scan_text(rx, label, text):
    return [(label, m.group(0)) for m in rx.finditer(text or '')]


def scan_range(rx, rng):
    """扫一段提交：提交信息、改动的文件名、新增的行。private/ 下是密文，不扫。"""
    hits = []
    log = git('log', '--format=%h%x1f%B%x1e', rng)
    for rec in log.split('\x1e'):
        rec = rec.strip()
        if not rec:
            continue
        sha, _, body = rec.partition('\x1f')
        hits += scan_text(rx, '提交信息 ' + sha, body)
    names = git('diff', '--name-only', rng, '--', '.', ':(exclude)private')
    for n in names.splitlines():
        hits += scan_text(rx, '文件名 ' + n, n)
    diff = git('diff', '--no-color', '--no-ext-diff', rng, '--', '.', ':(exclude)private')
    for ln in diff.splitlines():
        if ln.startswith('+') and not ln.startswith('+++'):
            hits += scan_text(rx, '新增行', ln)
    return hits


def report_hits(hits):
    seen = set()
    for label, word in hits:
        if (label, word) in seen:
            continue
        seen.add((label, word))
        print('    命中：%s → %s' % (label, word))
        if len(seen) >= 20:
            print('    …（只列前 20 条）')
            break


# ---------- git 辅助 ----------

def top():
    return Path(git('rev-parse', '--show-toplevel'))


def worktree_of(branch):
    out = git('worktree', 'list', '--porcelain')
    path = None
    for line in out.splitlines():
        if line.startswith('worktree '):
            path = line[len('worktree '):]
        elif line.strip() == 'branch refs/heads/' + branch:
            return path
    return None


def need_rebase():
    return git('merge-base', BASE, PRIVATE) != git('rev-parse', BASE)


def private_script(sub, out_dir, branch=None, stream=True):
    env = dict(os.environ, PRIVATE_BASE_BRANCH=BASE, PRIVATE_BRANCH=branch or PRIVATE, PRIVATE_OUT_DIR=str(out_dir))
    return run([find_bash(), 'tool/private_patch.sh', sub], env=env, stream=stream)


def commit_msg(text, trailer):
    return text + ('\n\n' + trailer if trailer else '')


def check_env():
    step('检查环境')
    cur = git('rev-parse', '--abbrev-ref', 'HEAD')
    if cur != BASE:
        die('当前在 %s，要在 %s 上运行' % (cur, BASE))
    if git('status', '--porcelain'):
        die('工作区有未提交的改动，先处理掉')
    if not KEY_FILE.exists() and not os.environ.get('PRIVATE_PATCH_KEY'):
        die('没有密钥：' + str(KEY_FILE))
    rx = load_words()
    ok('分支 %s、工作区干净、密钥和私有词清单都在' % BASE)
    r = run(['git', 'fetch', 'origin', BASE], check=False)
    if r.returncode != 0:
        note('没能 fetch origin（离线？）。未推送范围按本地记录的 origin/%s 算。' % BASE)
    if run(['git', 'rev-parse', '--verify', '-q', 'origin/' + BASE], check=False).returncode != 0:
        die('没有 origin/%s，没法确定哪些提交还没推送' % BASE)
    wt = worktree_of(PRIVATE)
    if not wt:
        die('私有分支 %s 没有在任何工作区里检出，变基要有一个工作区。先 git worktree add 一个' % PRIVATE)
    if git('status', '--porcelain', cwd=wt):
        die('私有工作区 %s 有未提交的改动，先提交或存起来' % wt)
    ok('私有分支 %s 在 %s，干净' % (PRIVATE, wt))
    return rx, wt


def same_version_guard(label, allow):
    last = last_patch_version()
    if last == label and not allow:
        die('上一次补丁就是 v%s。要出新包请用 --version 升版本号；确实要重做同一版本，加 --allow-same-version' % label)
    return last


# ---------- prepare ----------

def cmd_prepare(a):
    dry = a.dry_run
    os.chdir(top())
    rx, privwt = check_env()

    step('版本号')
    cur = read_version(Path('pubspec.yaml').read_text(encoding='utf-8'))
    target = cur
    if a.version:
        v3 = parse_ver3(a.version)
        if v3 <= cur[:3]:
            die('新版本 %s 要比现在的 %s 大' % (a.version, version_label(cur)))
        build = a.build if a.build else cur[3] + 1
        target = v3 + (build,)
    label = version_label(target)
    last = same_version_guard(label, a.allow_same_version)
    ok('目标 v%s（构建号 %d）；上一次补丁是 %s' % (label, target[3], ('v' + last) if last else '无'))
    if a.version and target != cur:
        if dry:
            note('dry-run：不会真的改 pubspec.yaml')
        else:
            p = Path('pubspec.yaml')
            p.write_bytes(bump_version_text(p.read_text(encoding='utf-8'), target[:3], target[3]).encode('utf-8'))
            git('add', 'pubspec.yaml')
            git('commit', '-m', commit_msg('chore: 版本号升到 %s' % label, a.trailer))
            ok('已提交版本号 %s+%d' % (label, target[3]))

    step('私有分支变基')
    priv = PRIVATE          # 后面核对用的分支名；dry-run 需要变基时换成临时分支
    dry_branch = dry_wt = None
    if need_rebase():
        if dry:
            # 不动真正的私有分支：在临时分支上演练一遍变基，结束时删掉
            dry_branch = 'pp-dry-%d' % os.getpid()
            dry_wt = tempfile.mkdtemp(prefix='ppdrywt.')
            git('worktree', 'add', '-q', '-b', dry_branch, dry_wt, PRIVATE)
            r = run(['git', '-C', dry_wt, 'rebase', BASE], check=False)
            if r.returncode != 0:
                conflicts = git('diff', '--name-only', '--diff-filter=U', cwd=dry_wt, check=False)
                run(['git', '-C', dry_wt, 'rebase', '--abort'], check=False)
                cleanup_dry(dry_wt, dry_branch)
                die('变基会冲突（dry-run，私有分支没动）。冲突文件：' + fmt_files(conflicts))
            priv = dry_branch
            ok('dry-run：在临时分支上演练了变基到 %s %s，没有冲突（真实运行时会对 %s 做同样的事）'
               % (BASE, git('rev-parse', '--short', BASE), PRIVATE))
        else:
            r = run(['git', '-C', privwt, 'rebase', BASE], check=False)
            if r.returncode != 0:
                conflicts = git('diff', '--name-only', '--diff-filter=U', cwd=privwt, check=False)
                run(['git', '-C', privwt, 'rebase', '--abort'], check=False)
                die('变基冲突，已中止（私有分支没动）。冲突文件：' + fmt_files(conflicts)
                    + '\n    手动处理：cd %s && git rebase %s' % (privwt, BASE)
                    + '\n    如果是刚改写（amend / rebase）过公开壳的提交，私有分支还挂在旧提交上，'
                    + '要只重放私有提交：git rebase --onto %s <旧的公开壳提交> %s' % (BASE, PRIVATE))
            ok('%s 已变基到 %s %s' % (PRIVATE, BASE, git('rev-parse', '--short', BASE)))
    else:
        ok('%s 已经基于最新的 %s' % (PRIVATE, BASE))

    try:
        return prepare_rest(a, rx, label, priv, dry)
    finally:
        if dry_wt:
            cleanup_dry(dry_wt, dry_branch)


def fmt_files(text):
    return ''.join(NL_INDENT + f for f in text.splitlines())


def cleanup_dry(wt, branch):
    run(['git', 'worktree', 'remove', '--force', wt], check=False)
    shutil.rmtree(wt, ignore_errors=True)
    run(['git', 'branch', '-D', branch], check=False)


def prepare_rest(a, rx, label, priv, dry):
    step('版本号没被盖回去')
    pv = read_version(git('show', priv + ':pubspec.yaml'))
    bv = read_version(git('show', BASE + ':pubspec.yaml'))
    if pv != bv:
        die('私有分支的 pubspec 版本号是 %s+%d，公开壳是 %s+%d。补丁会把版本号盖回去，先在私有分支改回来'
            % (version_label(pv), pv[3], version_label(bv), bv[3]))
    ok('私有分支和公开壳的版本号一致：%s+%d' % (version_label(bv), bv[3]))

    step('导出补丁并核对')
    root = Path(os.getcwd())
    tmp = None
    if dry:
        tmp = Path(tempfile.mkdtemp(prefix='ppdry.'))
        for f in (root / 'private').glob('assets.*'):
            shutil.copy2(f, tmp / f.name)
        out_dir = tmp
    else:
        out_dir = root / 'private'
    try:
        private_script('export', out_dir, priv)
        private_script('check', out_dir, priv)
        sizes = {f.name: f.stat().st_size for f in Path(out_dir).glob('*.enc')}
        ok('核对通过：' + '，'.join('%s %d 字节' % (k, v) for k, v in sorted(sizes.items())))
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)

    step('扫私有词（还没推送的提交 + 新提交的信息）')
    msg = commit_msg('chore: 更新私有补丁（v%s）' % label, a.trailer)
    hits = scan_range(rx, 'origin/%s..%s' % (BASE, BASE)) + scan_text(rx, '新提交的信息', msg)
    if hits:
        report_hits(hits)
        die('发现私有词，已停下，没有提交补丁')
    ok('干净')

    if dry:
        step('dry-run 结束：没有改任何分支，没有写 private/')
        return 0
    step('提交补丁')
    git('add', '-A', 'private')
    git('commit', '-m', msg)
    ok('已提交 %s' % git('rev-parse', '--short', 'HEAD'))
    print('\n下一步：python tool/private_release.py push   （推送并触发构建；只想先验补丁加 --check-only）')
    return 0


# ---------- push ----------

STATE_FILE = 'private_release_last_run'


def state_path():
    return Path(git('rev-parse', '--absolute-git-dir')) / STATE_FILE


def cmd_push(a):
    os.chdir(top())
    rx, _ = check_env()
    slug = repo_slug()

    step('推送前最后核对')
    ahead = int(git('rev-list', '--count', 'origin/%s..%s' % (BASE, BASE)))
    if ahead == 0:
        die('没有待推送的提交（origin/%s 已经是最新）。要重新触发构建请直接用 gh workflow run' % BASE)
    cur = read_version(Path('pubspec.yaml').read_text(encoding='utf-8'))
    last = last_patch_version()
    if last != version_label(cur):
        die('补丁是为 v%s 做的，pubspec 是 v%s。先运行 prepare' % (last, version_label(cur)))
    private_script('check', Path('private'))
    hits = scan_range(rx, 'origin/%s..%s' % (BASE, BASE))
    if hits:
        report_hits(hits)
        die('发现私有词，没有推送')
    ok('%d 个提交待推送，补丁与私有分支一致，扫描干净' % ahead)

    step('推送 %s' % BASE)
    run(['git', 'push', 'origin', BASE], stream=True)
    head = git('rev-parse', 'HEAD')

    if a.walk:
        return start_walk(slug, head, a.only)

    step('触发构建')
    fields = ['with_private=true'] + (['check_only=true'] if a.check_only else [])
    run_id = trigger(slug, WORKFLOW, head, fields)
    state_path().write_text(str(run_id), encoding='utf-8')
    ok('运行 %s（%s）' % (run_id, '只验补丁' if a.check_only else '完整构建'))
    print('\n下一步：python tool/private_release.py fetch %s' % run_id)
    return 0


def trigger(slug, workflow, head, fields):
    """触发 workflow_dispatch，找到这次的运行编号"""
    t0 = time.time()
    args = ['workflow', 'run', workflow, '--repo', slug, '--ref', BASE]
    for f in fields:
        args += ['-f', f]
    gh(*args)
    for _ in range(30):
        time.sleep(3)
        rows = json.loads(gh('run', 'list', '--repo', slug, '--workflow', workflow, '--branch', BASE,
                             '--event', 'workflow_dispatch', '--limit', '5',
                             '--json', 'databaseId,headSha,createdAt'))
        for r in rows:
            created = time.mktime(time.strptime(r['createdAt'], '%Y-%m-%dT%H:%M:%SZ')) - time.timezone
            if r['headSha'] == head and created >= t0 - 60:
                return r['databaseId']
    die('触发了，但没找到对应的运行。到 Actions 页面看一下')


# ---------- 模拟器走查 ----------

def walk_state_path():
    return SECRET_DIR / 'last_walk_run.txt'


def start_walk(slug, head, only):
    step('触发模拟器走查')
    run_id = trigger(slug, WALK_WORKFLOW, head, ['only=%s' % (only or '')])
    walk_state_path().write_text(str(run_id), encoding='utf-8')
    ok('走查运行 %s%s' % (run_id, '（只走 %s）' % only if only else ''))
    print('\n下一步：python tool/private_release.py fetch-walk %s' % run_id)
    return 0


def cmd_walk(a):
    """不推送：远端分支上的补丁就是本地这一份时，再跑一次走查"""
    os.chdir(top())
    check_env()
    slug = repo_slug()
    git('fetch', 'origin', BASE)
    head = git('rev-parse', 'HEAD')
    if git('rev-parse', 'origin/%s' % BASE) != head:
        die('本地 %s 和 origin 不一样：先 push --walk，或者把本地对齐了再跑' % BASE)
    return start_walk(slug, head, a.only)


def wait_run(slug, run_id, minutes):
    step('等运行 %s 结束' % run_id)
    deadline = time.time() + minutes * 60
    last = None
    while True:
        info = json.loads(gh('run', 'view', str(run_id), '--repo', slug, '--json', 'status,conclusion,jobs'))
        line = '%s/%s' % (info['status'], info.get('conclusion') or '-')
        if line != last:
            print('  ' + time.strftime('%H:%M:%S') + ' ' + line, flush=True)
            last = line
        if info['status'] == 'completed':
            return info
        if time.time() > deadline:
            die('等了 %d 分钟还没结束，先停。稍后再运行一次同样的命令' % minutes)
        time.sleep(40)


def cmd_fetch_walk(a):
    import tarfile
    os.chdir(top())
    slug = repo_slug()
    rx = load_words()
    run_id = a.run_id
    if not run_id:
        if not walk_state_path().exists():
            die('没给运行编号，也没有上次走查留下的记录')
        run_id = walk_state_path().read_text(encoding='utf-8').strip()
    info = wait_run(slug, run_id, 100)
    for j in info['jobs']:
        for s in j['steps']:
            if s['conclusion'] == 'failure':
                print('  ✗ 失败的步骤：%s / %s' % (j['name'], s['name']))

    dl = Path.home() / 'Downloads' / ('pulse-flow-walk-%s' % run_id)
    if dl.exists() and any(dl.iterdir()):
        die('%s 已经有内容。下载的结果要放进新的空目录，先处理掉再重来' % dl)
    dl.mkdir(parents=True, exist_ok=True)
    step('下载并解密')
    gh('run', 'download', str(run_id), '--repo', slug, '-n', WALK_ARTIFACT, '-D', str(dl))
    enc = dl / 'walk-out.tgz.enc'
    if not enc.exists():
        die('下载的产物里没有 walk-out.tgz.enc（补丁可能没合入）：' + str(dl))
    run([find_bash(), 'tool/private_patch.sh', 'decrypt-ipa', str(enc)], stream=False)
    tgz = dl / 'walk-out.tgz'
    with tarfile.open(tgz) as t:
        t.extractall(dl, filter='data')
    out = dl / 'walk-out'
    report = out / 'report.md'
    ok('解开在 %s%s' % (out, '' if report.exists() else '（没有走查报告，看 walk.log）'))

    step('公开日志扫私有词')
    log = gh('run', 'view', str(run_id), '--repo', slug, '--log', check=False)
    hits = scan_text(rx, '公开日志', log)
    if hits:
        report_hits(hits)
    (ok if not hits else note)('公开日志命中 %d 处' % len(hits))
    summary = re.findall(r'WALK-SUMMARY steps=\d+ failed=\d+ shots=\d+', log)
    print('  ' + (summary[-1] if summary else '公开日志里没有走查汇总行'))
    if hits:
        die('公开日志里有私有词，先处理')
    return 0


# ---------- fetch / 验包 ----------

def check_ipa(ipa, want, expect_strings):
    """静态检查解密后的 IPA。返回 (全部通过, 结果行)。"""
    z = zipfile.ZipFile(ipa)
    names = z.namelist()
    info = [n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
    if not info:
        return False, [('找不到 Info.plist', False, '')]
    raw = z.read(info[0])
    pl = plistlib.loads(raw)
    rows = []

    def expect(label, cond, detail=''):
        rows.append((label, bool(cond), detail))

    expect('应用名', pl.get('CFBundleDisplayName') == APP_NAME, str(pl.get('CFBundleDisplayName')))
    expect('包名', pl.get('CFBundleIdentifier') == BUNDLE_ID, str(pl.get('CFBundleIdentifier')))
    expect('版本号', pl.get('CFBundleShortVersionString') == version_label(want),
           '%s（要 %s）' % (pl.get('CFBundleShortVersionString'), version_label(want)))
    expect('构建号', pl.get('CFBundleVersion') == str(want[3]),
           '%s（要 %s）' % (pl.get('CFBundleVersion'), want[3]))
    schemes = {s for u in pl.get('CFBundleURLTypes', []) for s in u.get('CFBundleURLSchemes', [])}
    expect('链接方案', schemes == SCHEMES, ','.join(sorted(schemes)))
    expect('没有后台模式', not pl.get('UIBackgroundModes'), str(pl.get('UIBackgroundModes')))
    expect('没有旧包名', OLD_BUNDLE_ID not in raw)
    aot = [n for n in names if n.endswith('Frameworks/App.framework/App')]
    if expect_strings:
        if not aot:
            expect('找得到 Dart 产物', False)
        else:
            data = z.read(aot[0])
            for s in expect_strings:
                # Dart AOT 里非 Latin-1 的字符串存成 UTF-16LE，纯 ASCII 的存成单字节
                found = s.encode('utf-16-le') in data or s.encode('utf-8') in data
                expect('包里有「%s」' % s, found)
    return all(r[1] for r in rows), rows


def cmd_fetch(a):
    os.chdir(top())
    slug = repo_slug()
    rx = load_words()
    run_id = a.run_id
    if not run_id:
        sp = state_path()
        if not sp.exists():
            die('没给运行编号，也没有上次 push 留下的记录')
        run_id = sp.read_text(encoding='utf-8').strip()

    step('等运行 %s 结束' % run_id)
    deadline = time.time() + 55 * 60
    last = None
    while True:
        info = json.loads(gh('run', 'view', str(run_id), '--repo', slug, '--json', 'status,conclusion,jobs'))
        line = '%s/%s' % (info['status'], info.get('conclusion') or '-')
        if line != last:
            print('  ' + time.strftime('%H:%M:%S') + ' ' + line, flush=True)
            last = line
        if info['status'] == 'completed':
            break
        if a.no_wait:
            return 0
        if time.time() > deadline:
            die('等了 55 分钟还没结束，先停。可以稍后再运行 fetch %s' % run_id)
        time.sleep(40)

    jobs = {j['name']: j for j in info['jobs']}
    if info['conclusion'] != 'success':
        for j in info['jobs']:
            for s in j['steps']:
                if s['conclusion'] == 'failure':
                    print('  ✗ 失败的步骤：%s / %s' % (j['name'], s['name']))
        die('运行没成功。带私有补丁的编译错误不在公开日志里；构建失败时会加密上传为 %s，用 gh run download -n %s 取回，再 decrypt-ipa 解密' % (LOG_ARTIFACT, LOG_ARTIFACT))
    if jobs.get('ios', {}).get('conclusion') == 'skipped':
        ok('只验补丁的运行：补丁在 Linux 上解密、合入成功，没有构建')
        return 0

    want = read_version(Path('pubspec.yaml').read_text(encoding='utf-8'))
    dl = Path.home() / 'Downloads' / ('pulse-flow-run-%s' % run_id)
    if dl.exists() and any(dl.iterdir()):
        die('%s 已经有内容。下载的包要放进新的空目录，先处理掉再重来' % dl)
    dl.mkdir(parents=True, exist_ok=True)
    step('下载并解密')
    gh('run', 'download', str(run_id), '--repo', slug, '-n', ARTIFACT, '-D', str(dl))
    enc = dl / 'pulse-flow-unsigned.ipa.enc'
    if not enc.exists():
        die('下载的产物里没有 pulse-flow-unsigned.ipa.enc：' + str(dl))
    run([find_bash(), 'tool/private_patch.sh', 'decrypt-ipa', str(enc)], stream=False)
    ipa = dl / 'pulse-flow-unsigned.ipa'
    ok('%s（%d 字节）' % (ipa, ipa.stat().st_size))

    step('静态检查')
    strings = []
    if a.expect:
        strings += [s for s in a.expect.split(',') if s]
    if a.expect_file:
        strings += [l.strip() for l in Path(a.expect_file).read_text(encoding='utf-8').splitlines() if l.strip()]
    passed, rows = check_ipa(ipa, want, strings)
    for label, good, detail in rows:
        print('  %s %s%s' % ('✓' if good else '✗', label, ('：' + detail) if detail else ''))

    step('公开日志扫私有词')
    log = gh('run', 'view', str(run_id), '--repo', slug, '--log', check=False)
    hits = scan_text(rx, '公开日志', log)
    if hits:
        report_hits(hits)
    (ok if not hits else note)('公开日志命中 %d 处' % len(hits))

    if not passed or hits:
        die('检查没有全部通过，包先别用')
    print('\n全部通过。还没有在真机上跑过。')
    return 0


# ---------- 自测 ----------

def cmd_self_test(_):
    assert read_version('name: x\nversion: 1.4.3+2026110417\n') == (1, 4, 3, 2026110417)
    assert read_version('version: 1.4.3+2026110417\r\nfoo: 1\r\n') == (1, 4, 3, 2026110417)
    assert version_label((1, 4, 3, 5)) == '1.4.3'
    assert bump_version_text('a: 1\r\nversion: 1.4.3+9\r\nb: 2\r\n', (1, 4, 4), 10) == 'a: 1\r\nversion: 1.4.4+10\r\nb: 2\r\n'
    assert parse_ver3('1.10.2') == (1, 10, 2) and parse_ver3('1.10.2') > parse_ver3('1.9.9')
    try:
        parse_ver3('1.4')
        raise AssertionError('应该拒绝 1.4')
    except Fail:
        pass
    rx = re.compile('foo|[Bb]ar')
    assert scan_text(rx, 'x', 'a foo b Bar') == [('x', 'foo'), ('x', 'Bar')]
    assert scan_text(rx, 'x', 'clean') == []
    assert dict((r[0], r[1]) for r in check_ipa_rows_for_test())['版本号'] is True
    print('自测通过')
    return 0


def check_ipa_rows_for_test():
    """造一个最小的 IPA 走一遍 check_ipa。"""
    d = tempfile.mkdtemp(prefix='ppipa.')
    try:
        p = Path(d) / 't.ipa'
        pl = {'CFBundleDisplayName': APP_NAME, 'CFBundleIdentifier': BUNDLE_ID,
              'CFBundleShortVersionString': '1.4.3', 'CFBundleVersion': '7',
              'CFBundleURLTypes': [{'CFBundleURLSchemes': ['pulseflow', 'discourse']}]}
        with zipfile.ZipFile(p, 'w') as z:
            z.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(pl))
            z.writestr('Payload/Runner.app/Frameworks/App.framework/App', '你好'.encode('utf-16-le') + b'abc')
        passed, rows = check_ipa(p, (1, 4, 3, 7), ['你好', 'abc', '没有的词'])
        got = {r[0]: r[1] for r in rows}
        assert got['包里有「你好」'] and got['包里有「abc」'] and not got['包里有「没有的词」']
        assert not passed
        return rows
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass
    ap = argparse.ArgumentParser(description='私有补丁发版助手', formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('prepare', help='本地准备：变基、导出、核对、扫私有词、提交补丁')
    p.add_argument('--version', help='新版本号 X.Y.Z；不给就用 pubspec 里现在的')
    p.add_argument('--build', type=int, help='构建号；不给就是现在的 +1')
    p.add_argument('--dry-run', action='store_true', help='只检查，不改分支、不写 private/')
    p.add_argument('--allow-same-version', action='store_true', help='允许重做和上一次补丁相同的版本')
    p.add_argument('--trailer', default='', help='追加到提交信息末尾的一行（如 Co-Authored-By）')
    p.set_defaults(fn=cmd_prepare)
    p = sub.add_parser('push', help='推送并触发构建')
    p.add_argument('--check-only', action='store_true', help='只验补丁，不构建')
    p.add_argument('--walk', action='store_true', help='推送后只跑模拟器走查，不打包')
    p.add_argument('--only', default='', help='走查只走一段：shell / m170 / r169')
    p.set_defaults(fn=cmd_push)
    p = sub.add_parser('walk', help='不推送，用远端现在的补丁再跑一次模拟器走查')
    p.add_argument('--only', default='', help='只走一段：shell / m170 / r169')
    p.set_defaults(fn=cmd_walk)
    p = sub.add_parser('fetch-walk', help='等走查结束，下载、解密、解开截图和报告')
    p.add_argument('run_id', nargs='?')
    p.set_defaults(fn=cmd_fetch_walk)
    p = sub.add_parser('fetch', help='等构建结束，下载、解密、验包')
    p.add_argument('run_id', nargs='?')
    p.add_argument('--expect', default='', help='包里必须出现的字符串，逗号分隔')
    p.add_argument('--expect-file', help='同上，一行一个，从文件读（私有词不要写进仓库）')
    p.add_argument('--no-wait', action='store_true', help='没结束就直接返回')
    p.set_defaults(fn=cmd_fetch)
    p = sub.add_parser('self-test', help='自测')
    p.set_defaults(fn=cmd_self_test)
    a = ap.parse_args()
    try:
        sys.exit(a.fn(a) or 0)
    except Fail as e:
        print('\n错误：%s' % e, file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
