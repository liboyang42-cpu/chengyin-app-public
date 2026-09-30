// R10 收款模型(2026-09-15 定稿 §3 / 09-16 用户拍板):平台不打款,提现入口 =
// 客服微信号弹窗(「返回」「复制」)。App 侧**故意不接**这 5 条资金端点。
//
// ★ 为什么值得一条测试:登记成「App 侧不接」如果在裁判里是空的,它就退化成
//   静默 allowlist —— 而它减少缺口的方向恰好是假绿的方向。所以两条都钉住:
//   ① 5 条资金端点必须登记着,且每条都带 App 侧替代实现的证据与理由;
//   ② 证据缺失时必须判红(负控,注入参数跑,不联网、不读后端仓)。
//
// 判据真源仍是一个:tool/endpoint_parity.py。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('★★ R10 五条资金端点:登记为「App 侧不接」,且带证据与理由', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
FUND = (
    '/api/fund/preflight/bank-withdrawal',
    '/api/fund/preflight/{challengeId}/confirm',
    '/api/fund/preflight/{challengeId}/reject',
    '/api/withdrawal/create',
    '/api/club/settlement/withdraw',
)
by_mini = {spec.mini: spec for spec in E.DOCUMENTED_EQUIVALENTS}
missing = [e for e in FUND if e not in by_mini]
assert not missing, f'没登记:{missing}'
for e in FUND:
    spec = by_mini[e]
    assert not spec.app, f'{e} 不该填 App 端点 —— 它没有等价端点'
    assert spec.app_evidence, f'{e} 缺 App 侧替代实现的证据'
    assert spec.reason.strip(), f'{e} 缺理由'
    mini = [p for p, _ in spec.backend_evidence if p.startswith('chengyinhub-')]
    assert mini, f'{e} 缺小程序侧同口径证据'
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('★★ 负控:空 app 又没有 App 侧证据的条目必须判为缺口', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
spec = E.EndpointEquivalent(
    mini='/api/negative/absence',
    app=(),
    reason='没写证据的空条目',
    backend_evidence=(),
)
report = E.classify_endpoints(
    {'/api/negative/absence'}, '', '/api/negative/absence', equivalents=(spec,))
assert report.gaps == ['/api/negative/absence'], report
assert len(report.invalid) == 1, report
assert 'absence without App-side evidence' in report.invalid[0][1], report.invalid
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('★★ 负控:App 侧替代实现被删(证据 token 丢失)时必须判为缺口', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
spec = E.EndpointEquivalent(
    mini='/api/negative/absence2',
    app=(),
    reason='证据 token 不在文件里',
    backend_evidence=(),
    app_evidence=((
        'lib/feature/withdrawal/withdrawal_contact_dialog.dart',
        ('showWithdrawalContactDialog', '这个 token 不存在'),
    ),),
)
report = E.classify_endpoints(
    {'/api/negative/absence2'}, '', '/api/negative/absence2', equivalents=(spec,))
assert report.gaps == ['/api/negative/absence2'], report
assert len(report.invalid) == 1, report
assert 'App evidence missing:这个 token 不存在' in report.invalid[0][1], report.invalid
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });
}
