@Tags(<String>['needs-local-env'])
// 同上:页面绑定对账要读后端仓的现码与远端 SHA,只有开发机上有;
// 仓根由 test/support/backend_repo.dart 解析(env CHENGYIN_BACKEND → $HOME/Downloads/chengyin
// → /tmp/be-master),不绑死某一台机器的家目录。
// 见 .github/workflows/ci.yml:CI 上按 tag 排除。
library;

// 128 页一致性门禁。每页必须在 manifest 显式绑定 App
// route + source/class，或 sheet/component 承载；不再用全局 API
// 语料替代页面落点。独有接口也必须逐条可达或显式等价。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_repo.dart';

String _routeBlockProbe(String routerFixture, String route) {
  final ProcessResult result = Process.runSync(
    'python3',
    <String>[
      '-c',
      """
import os
import sys
sys.path.insert(0, 'tool')
import page_parity
block = page_parity._route_block(os.environ['ROUTER_FIXTURE'], os.environ['ROUTE'])
print(block or '')
""",
    ],
    environment: <String, String>{
      'ROUTER_FIXTURE': routerFixture,
      'ROUTE': route,
    },
    stdoutEncoding: const Utf8Codec(),
    stderrEncoding: const Utf8Codec(),
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString().trim();
}

void main() {
  test('page parity 解析父绝对 path 与嵌套相对子路由，且负控仍会红', () {
    const String fixture = '''
GoRoute(
  path: '/settings',
  builder: (_, _) => const SettingsPage(),
  routes: <RouteBase>[
    GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
  ],
)
''';

    expect(_routeBlockProbe(fixture, '/settings/about'), contains('AboutPage'));
    expect(_routeBlockProbe(fixture, '/settings/privacy'), isEmpty);
  });

  test('页面门禁也必须拒绝过期 github/master', () {
    final String local = backendMasterSha();
    final String stale = local == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/page_parity.py'],
      environment: backendEnvironment(<String, String>{
        'CHENGYIN_BACKEND_REMOTE_SHA': stale,
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, isNot(0), reason: r.stdout.toString());
    expect(r.stderr.toString(), contains('本地 github/master 已过期'));
  });

  test('页面绑定门禁负控：抽掉任一真实页绑定必须变红', () {
    final ProcessResult r = Process.runSync(
      'python3',
      <String>[
        'tool/page_parity.py',
        '--negative-binding-control',
        'pages/index/index',
      ],
      environment: backendEnvironment(),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, isNot(0), reason: '抽掉真绑定没有让门禁变红:\n${r.stdout}');
    expect(r.stdout.toString(), contains('pages/index/index'));
    // 验证数不写死(写死过 112,页数一动这条负控就红着指错方向):
    // 基线减掉被抽走的那一页,就是抽页后必须看到的已验证数。
    final RegExpMatch baseline = RegExp(
      r'EXPECTED_XCX_PAGE_COUNT = (\d+)',
    ).firstMatch(File('tool/page_parity.py').readAsStringSync())!;
    final String verified = (int.parse(baseline.group(1)!) - 1).toString();
    expect(r.stdout.toString(), contains('页面绑定:已验证 $verified · 缺失 1'));
  });

  test('独有接口门禁负控：同页两条独有接口只接一条不能放行', () {
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/page_parity.py', '--negative-endpoint-control'],
      environment: backendEnvironment(),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, isNot(0), reason: '独有接口仍用 any() 放行:\n${r.stdout}');
    expect(r.stdout.toString(), contains('/api/__page_parity_missing__'));
  });

  test('页面绑定与保证金 App 端点等价均已齐', () {
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/page_parity.py'],
      environment: backendEnvironment(),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, 0, reason: '页面与端点对账应全绿:\n${r.stdout}');

    final RegExpMatch? summary = RegExp(
      r'小程序 (\d+) 页 · 页面绑定:已验证 (\d+) · 缺失 (\d+) '
      r'· 独有接口未逐条等价 (\d+) 页',
    ).firstMatch(r.stdout.toString());
    expect(summary, isNotNull, reason: '脚本摘要格式变了:\n${r.stdout}');
    final RegExpMatch match = summary!;
    // 页数不写死:真源是 tool/page_parity.py 的 EXPECTED_XCX_PAGE_COUNT。
    // 写死过一次(113),小程序涨到 120 时门禁红了却指着保证金的端点。
    expect(
      match.group(2),
      match.group(1),
      reason: '有页面没绑定 App 落点:\n${r.stdout}',
    );
    final RegExpMatch baseline = RegExp(
      r'EXPECTED_XCX_PAGE_COUNT = (\d+)',
    ).firstMatch(File('tool/page_parity.py').readAsStringSync())!;
    expect(
      int.parse(match.group(1)!),
      int.parse(baseline.group(1)!),
      reason: 'manifest 页数与脚本基线常量脱节',
    );
    expect(match.group(3), '0');
    expect(match.group(4), '0');
    expect(r.stdout.toString(), isNot(contains('\n  pages/coop/list/index')));
  });

  test('page parity 不再维护第二套纯字符串等价 allowlist', () {
    final String source = File('tool/page_parity.py').readAsStringSync();
    expect(source, isNot(contains('_ENDPOINT_EQUIVALENTS')));
    expect(source, contains('E.classify_endpoints'));
  });

  test('商家公开主页与结算详情绑定真实游客路由', () {
    final entries =
        (jsonDecode(File('tool/page_parity_manifest.json').readAsStringSync())
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    Map<String, dynamic> entry(String page) =>
        entries.singleWhere((e) => e['miniPage'] == page);
    expect(
      entry('pages/merchant/profile/index')['route'],
      '/merchant/public-home/:id',
    );
    expect(
      entry('pages/merchant/profile/index')['marker'],
      'class MerchantPublicHomePage',
    );
    expect(
      entry('pages/coop/settlement-detail/index')['route'],
      '/coop/settlement-detail',
    );
    expect(
      entry('pages/coop/settlement-detail/index')['marker'],
      'class CoopSettlementDetailPage',
    );
  });
}
