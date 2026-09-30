@Tags(<String>['needs-local-env'])
// 要重新生成 tokens.wxss 并逐字节比对,依赖小程序仓。
// 见 .github/workflows/ci.yml:CI 上按 tag 排除。
library;

// 设计 token 生成链门禁。
//
// ★★ `cy_palette_parity_test.dart` 建立前，`cy_palette.dart` 曾长期写着
//   “App 侧靠该测试”，但仓库里实际没有这个文件。声称存在、实际不生效会制造
//   虚假安全感，比明说“没有门禁”更坏；这条教训必须跟着新门禁留下。
//
// ★ 旧测试只比较手工锚定的少量值，覆盖不到新增 token；这里直接重新生成完整
//   产物并逐字节比较，生成范围由带理由的 allowlist 控制。
//
// ★ 真源必须是可变的 tokens.wxss：改真源后本测试必须红，重新生成后才绿。
//   真源缺失、生成器失败、解析退化为空都必须红，不能把“查不了”伪装成通过。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String home = Platform.environment['HOME'] ?? '';
  final String sourcePath =
      Platform.environment['CY_TOKENS_WXSS'] ??
      '$home/Downloads/chengyin/chengyinhub-xcx/style/tokens.wxss';

  test('★★ tokens.wxss 重新生成后必须与仓库产物逐字节一致', () {
    final Directory temp = Directory.systemTemp.createTempSync(
      'cy-token-codegen-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final File actual = File('${temp.path}/cy_tokens.g.dart');
    final ProcessResult result = Process.runSync('python3', <String>[
      'tool/gen_tokens.py',
      '--source',
      sourcePath,
      '--output',
      actual.path,
    ], workingDirectory: Directory.current.path);

    expect(
      result.exitCode,
      0,
      reason: 'token 生成器运行失败：\n${result.stdout}\n${result.stderr}',
    );

    final String generated = actual.readAsStringSync();
    final int declarationCount = RegExp(
      r'^  static const (?:Color|double|Duration|Curve) ',
      multiLine: true,
    ).allMatches(generated).length;
    expect(
      declarationCount,
      greaterThanOrEqualTo(120),
      reason: '只生成了 $declarationCount 条主题声明，解析器可能已经失效',
    );
    expect(
      result.stdout,
      contains('allowlist 未找到 0 条'),
      reason: 'allowlist 中每一条都必须能在真源找到：\n${result.stdout}',
    );

    final File committed = File('lib/core/theme/cy_tokens.g.dart');
    expect(
      committed.existsSync(),
      isTrue,
      reason: '缺少已提交生成物；运行 python3 tool/gen_tokens.py',
    );
    expect(
      generated,
      committed.readAsStringSync(),
      reason: 'tokens.wxss 或生成器已变化；运行 python3 tool/gen_tokens.py 重新生成',
    );
  });
}
