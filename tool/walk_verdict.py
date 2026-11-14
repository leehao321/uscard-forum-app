#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""模拟器走查的结论：过还是不过。CI 在加密上传结果之后用它决定这次运行红不红。

  python3 tool/walk_verdict.py <结果文件夹> <测试进程退出码>
  python3 tool/walk_verdict.py --self-test

不过（退出码 1）的情况，任何一条都算：
  - 测试进程退出码不是 0（编译失败、装不上、测试里 expect 失败、App 抛到测试框架的异常）
  - 没有 report.json（走查没跑到写报告那一步）
  - 报告里一步都没有
  - 有失败的步骤
  - App 报过错（appErrorCount > 0）

只打印一行：WALK-VERDICT pass|fail exit=… steps=… failed=… errors=… reason=…
（只有数字和固定的原因代号，公开日志里看得到也没关系）
"""
import json
import sys
import tempfile
from pathlib import Path


def verdict(out_dir, exit_code):
    """返回 (是否通过, 一行说明)"""
    out = Path(out_dir)
    report = out / 'report.json'
    steps = failed = errors = -1
    reason = 'ok'
    if not report.is_file():
        reason = 'no-report'
    else:
        try:
            data = json.loads(report.read_text(encoding='utf-8'))
            step_list = data.get('steps') or []
            steps = len(step_list)
            failed = sum(1 for s in step_list if not s.get('ok', False))
            errors = int(data.get('appErrorCount', len(data.get('appErrors') or [])))
        except Exception:
            reason = 'bad-report'
    if reason == 'ok':
        if exit_code != 0:
            reason = 'test-exit'
        elif steps <= 0:
            reason = 'no-steps'
        elif failed > 0:
            reason = 'steps-failed'
        elif errors > 0:
            reason = 'app-errors'
    elif exit_code != 0 and reason == 'no-report':
        reason = 'no-report'
    ok = reason == 'ok'
    line = 'WALK-VERDICT %s exit=%d steps=%d failed=%d errors=%d reason=%s' % (
        'pass' if ok else 'fail', exit_code, steps, failed, errors, reason)
    return ok, line


def _self_test():
    cases = []

    def case(name, exit_code, report, want_ok, want_reason):
        cases.append((name, exit_code, report, want_ok, want_reason))

    good = {'steps': [{'ok': True}, {'ok': True}], 'appErrorCount': 0}
    case('全部通过', 0, good, True, 'ok')
    case('测试进程失败', 1, good, False, 'test-exit')
    case('没有报告', 0, None, False, 'no-report')
    case('没有报告且进程失败', 1, None, False, 'no-report')
    case('报告坏了', 0, '{not json', False, 'bad-report')
    case('一步都没有', 0, {'steps': [], 'appErrorCount': 0}, False, 'no-steps')
    case('有失败步骤', 0, {'steps': [{'ok': True}, {'ok': False}], 'appErrorCount': 0}, False, 'steps-failed')
    case('App 报错', 0, {'steps': [{'ok': True}], 'appErrorCount': 2}, False, 'app-errors')
    case('旧报告只有 appErrors', 0, {'steps': [{'ok': True}], 'appErrors': ['x']}, False, 'app-errors')
    bad = 0
    for name, exit_code, report, want_ok, want_reason in cases:
        with tempfile.TemporaryDirectory() as d:
            if report is not None:
                text = report if isinstance(report, str) else json.dumps(report)
                (Path(d) / 'report.json').write_text(text, encoding='utf-8')
            ok, line = verdict(d, exit_code)
            got_reason = line.rsplit('reason=', 1)[1]
            good_case = ok == want_ok and got_reason == want_reason
            bad += 0 if good_case else 1
            print('%s %s：%s' % ('✓' if good_case else '✗', name, line))
    if bad:
        print('自测失败 %d 条' % bad)
        return 1
    print('自测通过')
    return 0


def main(argv):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    if len(argv) == 2 and argv[1] == '--self-test':
        return _self_test()
    if len(argv) != 3:
        print(__doc__)
        return 2
    try:
        exit_code = int(argv[2])
    except ValueError:
        exit_code = 1
    ok, line = verdict(argv[1], exit_code)
    print(line)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
