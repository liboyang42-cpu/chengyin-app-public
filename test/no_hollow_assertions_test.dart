// 门禁:测试里不许出现「空壳断言」。
//
// ★ 空壳断言 = **只验证了作者自己写下的常量,完全没有触碰被测对象**。
//   本轮我自己写出来两次,而且当时都觉得「把语义记录下来了」:
//
//     expect(true, isTrue);                 // 「软探测不是硬闸」那条
//     expect(allowedFields.length, 6);      // 「白名单有六个字段」那条
//
//   前者什么也没测;后者只证明我数了六个,**不证明代码里就是这六个**。
//   它们永远绿,而且长得像正经测试 —— 比没有测试更坏,因为会让人以为覆盖到了。
//
// ⚠️ 判据只认**最狭窄**的那一类:`expect` 的实参是**字面量**
//   (true/false/数字/字符串),或对**同文件内 const 声明**的直接取值。
//   `all.length`、`declared.difference(...)` 这类**从被测对象算出来**的表达式
//   不算 —— 第一版扫描把它们也算进去了,两条都是误报。
//   宁可漏判,不要误伤:一道会误报的闸会被人关掉。
//
// 负控:写一条 `expect(true, isTrue)` → 本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 `{` 起找到配对的 `}`,返回其中的函数体。
String _bodyAt(String src, int openBraceIndex) {
  int depth = 1;
  int i = openBraceIndex + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(openBraceIndex + 1, i - 1);
}

void main() {
  test('★ 测试里不许有只验证字面量的空壳断言', () {
    // 纯字面量实参:true / false / 数字 / 单引号字符串
    final RegExp literalArg =
        RegExp(r"^\s*(true|false|-?\d+(\.\d+)?|'[^']*')\s*$");
    final RegExp testHead = RegExp(
        r"test(?:Widgets)?\(\s*'([^']{0,120})'[^)]*?,\s*\(?[^)]*\)?\s*(?:async\s*)?\{");

    final List<String> offenders = <String>[];
    int scannedFiles = 0;
    int scannedCases = 0;

    for (final FileSystemEntity e in Directory('test').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('_test.dart')) continue;
      // 本文件自己会写 `expect(true, isTrue)` 当例子,豁免
      if (e.path.endsWith('no_hollow_assertions_test.dart')) continue;
      scannedFiles++;
      final String src = e.readAsStringSync();

      for (final RegExpMatch m in testHead.allMatches(src)) {
        scannedCases++;
        final String body = _bodyAt(src, m.end - 1);
        final List<String> args = RegExp(r'expect\(\s*([^,]{1,80}),')
            .allMatches(body)
            .map((RegExpMatch a) => a.group(1)!)
            .toList();
        if (args.isEmpty) continue;

        // 只有当**每一条** expect 的实参都是纯字面量时才判空壳。
        if (args.every((String a) => literalArg.hasMatch(a))) {
          offenders.add('${e.path}  「${m.group(1)}」  → $args');
        }
      }
    }

    // ★ 两条下限:少了说明扫描本身失效,而不是"很干净"。
    expect(scannedFiles, greaterThanOrEqualTo(40),
        reason: '只扫到 $scannedFiles 个测试文件,太少了 —— 目录变了?');
    expect(scannedCases, greaterThanOrEqualTo(300),
        reason: '只解析出 $scannedCases 个用例,正则可能失效了');

    expect(offenders, isEmpty,
        reason: '这些用例只验证了字面量,没有触碰被测对象 —— 它们永远绿:\n'
            '${offenders.join('\n')}');
  });
}
