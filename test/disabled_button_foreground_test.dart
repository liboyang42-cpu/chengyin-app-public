import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 禁用态按钮的“看不见的字”门禁。
///
/// 暗色下 `bgSubtle` 叠在页面底色上约 #0E0E0E，`actionPrimaryFg` 是 #0A0A0A；
/// 亮色下 `bgSubtle` 是 #F8FAFC，`actionPrimaryFg` 是 #FFFFFF。两边都约 1.1:1，
/// 禁用按钮上的文字直接消失。小程序原型的口径是“占位色字 + 中性底”，
/// 所以能被禁用的按钮，前景色必须跟着禁用条件切走。
///
/// 没写 `disabledColor` 也一样：Cupertino 默认的禁用底色同样是页面底色附近的
/// 中性填充，反色前景压上去照样看不见。
///
/// 判据：一个 [CupertinoButton] 的 `onPressed` 能取到 null（说明它会进禁用态）时，
/// 它内部任何 `color:` / `foregroundColor:` 都必须在写 `actionPrimaryFg` /
/// `textInverse` 的同时给出一个弱化色，否则就是无条件反色。

/// 源码里一处具名实参。
typedef _Arg = ({String name, String value});

/// 逐字符扫描，跳过注释与字符串（含 `${}` 插值），收集所有具名实参。
///
/// 这里不用正则：Dart 里字符串插值可以再套字符串，正则会把注释和文案里的
/// 括号、引号当成代码，门禁就会假红或假绿。
List<_Arg> _args(String src) {
  final List<_Arg> out = <_Arg>[];
  final List<int> depths = <int>[]; // 每个待收尾实参开始时的深度
  final List<String> names = <String>[];
  final List<int> starts = <int>[];
  int depth = 0;
  int i = 0;
  // 只有 `(` 与 `,` 之后才可能是具名实参；空白和注释不改变这个位置判断。
  bool atArgStart = true;

  void closeArgsAt(int d, int end) {
    while (depths.isNotEmpty && depths.last >= d) {
      out.add((
        name: names.removeLast(),
        value: src.substring(starts.removeLast(), end),
      ));
      depths.removeLast();
    }
  }

  while (i < src.length) {
    final String c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      final int end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    if (c == ' ' || c == '\n' || c == '\t' || c == '\r') {
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      final String q = c;
      i++;
      int braces = 0;
      while (i < src.length) {
        if (src[i] == r'\') {
          i += 2;
          continue;
        }
        if (src[i] == r'$' && i + 1 < src.length && src[i + 1] == '{') {
          braces++;
          i += 2;
          continue;
        }
        if (braces > 0 && src[i] == '}') {
          braces--;
          i++;
          continue;
        }
        if (braces == 0 && src[i] == q) {
          i++;
          break;
        }
        i++;
      }
      atArgStart = false;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      atArgStart = c == '(';
      i++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      closeArgsAt(depth, i);
      depth--;
      atArgStart = false;
      i++;
      continue;
    }
    if (c == ',') {
      closeArgsAt(depth, i);
      atArgStart = true;
      i++;
      continue;
    }
    final Match? m = atArgStart ? _namedArg.matchAsPrefix(src, i) : null;
    if (m != null) {
      names.add(m.group(1)!);
      starts.add(m.end);
      depths.add(depth);
      atArgStart = false;
      i = m.end;
      continue;
    }
    atArgStart = false;
    i++;
  }
  closeArgsAt(0, src.length);
  return out;
}

final RegExp _namedArg = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)');

/// 取出每个 `CupertinoButton(` 的括号配平正文。
List<String> _cupertinoButtons(String src) {
  final List<String> blocks = <String>[];
  for (final Match m in RegExp(r'CupertinoButton\s*\(').allMatches(src)) {
    int depth = 0;
    for (int i = m.end - 1; i < src.length; i++) {
      if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
        final int end = src.indexOf('*/', i + 2);
        i = end < 0 ? src.length : end + 1;
        continue;
      }
      if (src[i] == '(') depth++;
      if (src[i] == ')') {
        depth--;
        if (depth == 0) {
          blocks.add(src.substring(m.end, i));
          break;
        }
      }
    }
  }
  return blocks;
}

final RegExp _inverseFg = RegExp(r'\b(actionPrimaryFg|textInverse)\b');

/// 真三元运算的 `?`。`?.` 和 `??` 都不是分支，不能算“跟着状态切了”。
final RegExp _ternary = RegExp(r'(?<!\?)\?(?![.?])');

/// onPressed 表达式本身能否求值为 null（剥掉闭包块体后再看）。
///
/// 裸标识符（`onPressed: primaryAction`）看不出可空性，回到文件里找它的声明：
/// 类型带 `?` 才算能进禁用态，否则是永远点得动的方法引用。
bool _nullable(String expr, String file) {
  final StringBuffer out = StringBuffer();
  int depth = 0;
  for (int i = 0; i < expr.length; i++) {
    final String c = expr[i];
    if (c == '{') depth++;
    if (depth == 0) out.write(c);
    if (c == '}') depth--;
  }
  final String expression = out.toString().trim();
  final RegExpMatch? bare = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_]*)$',
  ).firstMatch(expression);
  if (bare != null) {
    return RegExp(r'\?\s+' + bare.group(1)! + r'\b').hasMatch(file);
  }
  return RegExp(r'\bnull\b').hasMatch(expression);
}

List<String> _violations(String src) {
  final List<String> found = <String>[];
  for (final String block in _cupertinoButtons(src)) {
    final List<_Arg> args = _args(block);
    final _Arg? onPressed = args
        .where((_Arg a) => a.name == 'onPressed')
        .firstOrNull;
    // 只看 onPressed 表达式本身能不能取到 null。块体闭包里的 `null` 是函数体
    // 内部的事，按钮照样永远点得动，所以先把 `{...}` 剥掉再判。
    if (onPressed == null || !_nullable(onPressed.value, src)) continue;
    for (final _Arg a in args) {
      if (a.name != 'color' && a.name != 'foregroundColor') continue;
      if (!_inverseFg.hasMatch(a.value)) continue;
      if (_ternary.hasMatch(a.value)) continue; // 已经跟着状态切了
      found.add('${a.name}: ${a.value.trim()}');
    }
  }
  return found;
}

const String _bad = '''
CupertinoButton(
  color: palette.actionPrimaryBg,
  disabledColor: palette.bgSubtle,
  foregroundColor: palette.actionPrimaryFg,
  onPressed: _busy ? null : _submit,
  child: const Text('提交'),
)
''';

const String _good = '''
CupertinoButton(
  color: palette.actionPrimaryBg,
  disabledColor: palette.bgSubtle,
  foregroundColor: _busy ? palette.textPlaceholder : palette.actionPrimaryFg,
  onPressed: _busy ? null : _submit,
  child: const Text('提交'),
)
''';

const String _alwaysEnabled = '''
CupertinoButton(
  color: p.actionPrimaryBg,
  foregroundColor: p.actionPrimaryFg,
  onPressed: () => Navigator.of(context).pop(_result),
  child: const Text('填进表单(还能改)'),
)
''';

const String _childTextStyle = '''
CupertinoButton(
  color: palette.actionPrimaryBg,
  disabledColor: palette.actionSecondaryBg,
  onPressed: _selected.isEmpty ? null : _confirm,
  child: Text('完成', style: TextStyle(color: palette.actionPrimaryFg)),
)
''';

/// `onPressed` 是可空回调变量时，可空性只能回文件里查声明。
const String _bareNullable = '''
final VoidCallback? primaryAction = _busy ? null : _submit;
CupertinoButton(
  color: palette.actionPrimaryBg,
  foregroundColor: palette.actionPrimaryFg,
  onPressed: primaryAction,
  child: const Text('确认购买'),
)
''';

/// 同名变量声明为非空时是方法引用，永远点得动。
const String _bareNonNull = '''
final VoidCallback onTap = _submit;
CupertinoButton(
  color: palette.actionPrimaryBg,
  foregroundColor: palette.actionPrimaryFg,
  onPressed: onTap,
  child: const Text('确认购买'),
)
''';

/// `?.` / `??` 不是分支，不许拿它顶替三元。
const String _nullSafeNotTernary = '''
CupertinoButton(
  color: palette.actionPrimaryBg,
  foregroundColor: theme?.actionPrimaryFg ?? palette.actionPrimaryFg,
  onPressed: _busy ? null : _submit,
  child: const Text('提交'),
)
''';

void main() {
  test('负控：禁用态写死反色前景会被抓到', () {
    expect(_violations(_bad), <String>[
      'foregroundColor: palette.actionPrimaryFg',
    ]);
    expect(_violations(_childTextStyle), <String>[
      'color: palette.actionPrimaryFg',
    ]);
    expect(_violations(_bareNullable), <String>[
      'foregroundColor: palette.actionPrimaryFg',
    ]);
    expect(_violations(_nullSafeNotTernary), <String>[
      'foregroundColor: theme?.actionPrimaryFg ?? palette.actionPrimaryFg',
    ]);
  });

  test('正控：跟着条件切的、以及永远可点的按钮不会误报', () {
    expect(_violations(_good), isEmpty);
    expect(_violations(_alwaysEnabled), isEmpty);
    expect(_violations(_bareNonNull), isEmpty);
  });

  test('lib/ 里没有禁用态看不见字的按钮', () {
    final List<String> failures = <String>[];
    int scanned = 0;
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      for (final String v in _violations(entity.readAsStringSync())) {
        failures.add('${entity.path}: $v');
      }
    }

    expect(scanned, greaterThanOrEqualTo(200));
    expect(
      failures,
      isEmpty,
      reason:
          '按钮能进禁用态时，前景色要跟着禁用条件切到 textPlaceholder（原型口径），'
          '否则暗色 #0A0A0A 压在 #0E0E0E 上、亮色 #FFFFFF 压在 #F8FAFC 上，字看不见。\n'
          '${failures.join('\n')}',
    );
  });
}
