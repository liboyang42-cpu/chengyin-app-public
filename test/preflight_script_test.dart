@Tags(<String>['needs-local-env'])
// 跑 tool/preflight.sh,依赖本机工具链与注入的高德 Key。
// 见 .github/workflows/ci.yml:CI 上按 tag 排除。
library;

// 上线预检脚本必须跑得起来。
//
// ★ 它是一堆 grep/awk 拼的,重构目录或改常量名会让它**静默退化**成
//   「什么都检查不出来但 exit 0」—— 那比没有更坏。
//   这里只保证两件事:能跑、且**认得出当前这个已知的阻塞态**。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_repo.dart';

/// 预检脚本第 4 节要跑 tool/*.py 对账,所以环境里必须钉住后端仓根与远端 SHA。
Map<String, String> _preflightEnvironment([Map<String, String>? extra]) =>
    backendEnvironment(extra);

void main() {
  test('★★ 预检脚本能跑,且当前状态下必须报出阻塞', () {
    final ProcessResult r = Process.runSync(
      'bash',
      <String>['tool/preflight.sh'],
      environment: _preflightEnvironment(),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    final String out = r.stdout.toString();

    // shell 自身出错(命令找不到/语法错)会写 stderr —— 那不是「检查出问题」,
    // 是「检查本身坏了」,必须分开判。
    expect(
      r.stderr.toString().trim(),
      isEmpty,
      reason: '脚本自身报错了:\n${r.stderr}',
    );

    // 五个小节都要在。少一节说明有段被 grep 静默吃掉了。
    for (final String s in <String>[
      'Android 签名',
      '微信开放平台',
      '高德地图',
      'App 内隐私政策',
      '一致性对账',
      '本机看不到',
    ]) {
      expect(out.contains(s), isTrue, reason: '预检少了「$s」这一节');
    }

    // ★ 现在**确实**有阻塞(appid 是占位;keystore 已于 2026-08-20 配好)。
    //   这时 exit 0 = 脚本瞎了。等真配好了这条会红,那时把它改成 0 —— 那是好事。
    expect(r.exitCode, 1, reason: '当前明明还差微信 appid,预检却说全过了:\n$out');
    expect(out.contains('wxYOURAPPID'), isTrue, reason: '占位 appid 没被认出来');
    expect(
      out.contains('App 内隐私政策正文待提供'),
      isTrue,
      reason: '结构化隐私文档的 sections 为空，预检不能静默通过:\n$out',
    );
    expect(
      out.contains('113 页绑定与端点等价已通过'),
      isTrue,
      reason: 'github/master 已有保证金 App 路由，一致性章节不应再报该缺口:\n$out',
    );
  });

  test('★★ 隐私政策注释里的假 sections/version 不能骗绿', () {
    final Directory temp = Directory.systemTemp.createTempSync(
      'chengyin-legal-gate-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final File source = File('${temp.path}/legal_docs.dart')
      ..writeAsStringSync('''
// LegalDocType.privacyPolicy: LegalDoc(
//   version: 'v9.9', updatedAt: '2099-01-01',
//   sections: <LegalSection>[LegalSection('fake', 'fake')],
// ),
const docs = <String, LegalDoc>{
  LegalDocType.privacyPolicy: LegalDoc(
    title: '隐私政策',
    version: '',
    updatedAt: '',
    sections: <LegalSection>[],
  ),
};
''');

    final ProcessResult gate = Process.runSync(
      'python3',
      <String>['tool/legal_doc_gate.py', source.path],
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(gate.exitCode, isNot(0), reason: gate.stdout.toString());
    expect(gate.stdout.toString(), contains('pending=true'));
    expect(gate.stdout.toString(), contains('version 为空'));
    expect(gate.stdout.toString(), contains('updatedAt 为空'));

    final ProcessResult preflight = Process.runSync(
      'bash',
      <String>['tool/preflight.sh'],
      environment: _preflightEnvironment(<String, String>{
        'CHENGYIN_LEGAL_DOC_PATH': source.path,
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    final String out = preflight.stdout.toString();
    final int from = out.indexOf('3. App 内隐私政策');
    final int to = out.indexOf('4. ', from);
    final String section = out.substring(from, to > from ? to : out.length);
    expect(section, contains('✗'));
    expect(section, isNot(contains('✓')));
  });

  test('★★ 隐私政策 pending=false 且元数据完整才放行', () {
    final Directory temp = Directory.systemTemp.createTempSync(
      'chengyin-legal-gate-valid-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final File source = File('${temp.path}/legal_docs.dart')
      ..writeAsStringSync('''
const docs = <String, LegalDoc>{
  LegalDocType.privacyPolicy: LegalDoc(
    title: '隐私政策',
    version: 'v1.0',
    updatedAt: '2026-08-23',
    sections: <LegalSection>[
      LegalSection('一、范围', '正文'),
    ],
  ),
};
''');
    final ProcessResult gate = Process.runSync(
      'python3',
      <String>['tool/legal_doc_gate.py', source.path],
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(gate.exitCode, 0, reason: '${gate.stdout}\n${gate.stderr}');
    expect(gate.stdout.toString(), contains('pending=false'));
  });
}
