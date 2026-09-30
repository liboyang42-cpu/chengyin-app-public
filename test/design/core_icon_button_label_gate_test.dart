// 共用层图标按钮语义门禁:图标-only 的 CupertinoButton 必须有可命名的语义。
//
// ★ 判据来源:HIG-A11y / ADA「包容与无障碍」—— VoiceOver 必须念得出这个钮
//   是干什么的。图标按钮没有文字,语义只能来自 `Semantics(label:)` /
//   `semanticLabel` / `tooltip` 或 `CyNativeIconButton` 的 `label`。
//
// ⚠️ 这是**静态近似**:判据 = 按钮块里有语义参数,或按钮真的被一个
//   `Semantics(...)` 调用**包住**(括号配平后的区间包含,不是「附近出现过」)。
//   它**不能证明运行时语义挂在了正确节点上** —— 真判据是渲染回读
//   (样式:`test/feature/apple_native/raw_gesture_semantics_test.dart` 的
//   `find.bySemanticsLabel` + `takeSemantics().flagsCollection.isButton`)。
//   ⚠️ 第一版用的是「往前 400 字符窗口」,负控当场证明它会**假绿**:
//   按钮前面 400 字符里恰好有别的 `Semantics(` 就蒙混过关。区间包含才是对的。
//
// ★ 范围:`lib/core/widgets/**`(共用层)。四条 UI 线正在写的就是这一层;
//   feature 页的存量没有逐个人肉核过,不塞进来假装守着 ——
//   没核过的 allowlist 会让这道闸变成假的。
//
// ★ 负控:合成一个裸图标按钮(无任何语义)→ 必须被扫到;
//   前面带 `Semantics(label: …)` 的合成按钮 → 不许被误报。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scan_support.dart';

/// 语义声明的四种合法写法(命中其一即可)。
final RegExp _labeled = RegExp(
  r'Semantics\s*\(|semanticLabel\s*:|tooltip\s*:|label\s*:',
);

/// 扫描一份源码,返回违规的 `相对路径 @ 偏移` 列表。
List<String> scanIconButtons(String path, String source) {
  final String code = stripComments(source);
  final List<String> offenders = <String>[];

  /// 从 `(` 起括号配平,返回配对 `)` 的下标(找不到返回源码长度)。
  int matchClose(int open) {
    int depth = 0;
    int j = open;
    while (j < code.length) {
      if (code[j] == '(') depth++;
      if (code[j] == ')') {
        depth--;
        if (depth == 0) return j;
      }
      j++;
    }
    return code.length;
  }

  // 所有 `Semantics(...)` 的区间。`\b` 保证不匹配 `ExcludeSemantics(` ——
  // 后者是「去掉语义」,单独出现不构成语义来源。
  final List<(int, int)> semanticsRanges = <(int, int)>[
    for (final RegExpMatch m in RegExp(r'\bSemantics\s*\(').allMatches(code))
      (m.start, matchClose(m.end - 1)),
  ];

  for (final RegExpMatch m in RegExp(r'CupertinoButton\s*\(').allMatches(code)) {
    final int end = matchClose(m.end - 1);
    final String block = code.substring(m.start, end + 1);
    final bool iconOnly =
        block.contains('Icon(') && !RegExp(r'Text\s*\(').hasMatch(block);
    if (!iconOnly) continue;
    final bool hasOwnLabel = _labeled.hasMatch(block);
    final bool enclosed = semanticsRanges.any(
      ((int, int) r) => r.$1 < m.start && end < r.$2,
    );
    if (!hasOwnLabel && !enclosed) {
      offenders.add('$path @${m.start}');
    }
  }
  return offenders;
}

void main() {
  test('★ 共用层图标按钮必须有语义标签', () {
    final Directory core = Directory('lib/core/widgets');
    expect(core.existsSync(), isTrue, reason: '找不到 lib/core/widgets,扫描退化为空 = 假绿');

    final List<String> offenders = <String>[];
    int scanned = 0;
    int cupertinoButtons = 0;
    for (final FileSystemEntity e in core.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final List<String> hits = scanIconButtons(e.path, e.readAsStringSync());
      offenders.addAll(hits);
      final String code = codeOfFile(e.path);
      cupertinoButtons += RegExp(r'CupertinoButton\s*\(')
          .allMatches(code)
          .length;
    }
    expect(
      scanned,
      greaterThanOrEqualTo(10),
      reason: '只扫到 $scanned 个共用层文件,目录变了就先修这条闸',
    );
    expect(
      cupertinoButtons,
      greaterThanOrEqualTo(2),
      reason: '一个 CupertinoButton 都没扫到 —— 正则失效了,别把它当通过',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          '图标按钮没有文字,不挂语义 VoiceOver 只会念「按钮」——'
          '给 `Semantics(label: …)` 或改成 `CyNativeIconButton(label: …)`,'
          '确属误报就登记理由:\n${offenders.join('\n')}',
    );
  });

  test('负控:裸图标按钮必须被扫到,带语义的不许误报', () {
    const String unlabeled = '''
      CupertinoButton(
        onPressed: () {},
        child: Icon(CupertinoIcons.trash),
      )
''';
    expect(scanIconButtons('x.dart', unlabeled), hasLength(1));

    const String labeled = '''
      Semantics(
        label: '删除',
        button: true,
        child: CupertinoButton(
          onPressed: () {},
          child: Icon(CupertinoIcons.trash),
        ),
      )
''';
    expect(scanIconButtons('x.dart', labeled), isEmpty);

    // ★ 曾经的假绿:按钮前面恰好有另一个组件的 `Semantics(` ——
    //   400 字符窗口版本会放行,区间包含版本必须报出来。
    const String distant = '''
      Semantics(
        label: '别的组件',
        child: Text('x'),
      ),
      CupertinoButton(
        onPressed: () {},
        child: Icon(CupertinoIcons.trash),
      )
''';
    expect(
      scanIconButtons('x.dart', distant),
      hasLength(1),
      reason: '不能被附近的无关 Semantics 骗过',
    );

    // 带文字的按钮(图标 + 文字)不归这条管。
    const String withText = '''
      CupertinoButton(
        onPressed: () {},
        child: Row(children: <Widget>[Icon(CupertinoIcons.trash), Text('删除')]),
      )
''';
    expect(scanIconButtons('x.dart', withText), isEmpty);
  });
}
