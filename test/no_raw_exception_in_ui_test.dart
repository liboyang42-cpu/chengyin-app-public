// 用户可见文案里不许出现异常原文。
//
// ★ 为什么值得一道闸:`DioException` 的 toString 是
//   `DioException [bad response]: This exception was thrown because the response
//   has a status code of 502 …  https://pub.dev/packages/dio#…` ——
//   一屏中文里砸下来一段英文栈,用户读到的只有「这 App 坏了」。
//   b1 报告反复按 P1 记这一类(2026-09-18 第二轮:6 处)。
//
// 判据(两条都占才算违规):
//   ① 位置在 `catch` 块里 —— 那里抛出来的可能是**原样透传**的 DioException;
//   ② 该异常对象被拼进了字符串字面量(`'创建失败:$e'` / `'$error'`)。
//
// 出闸方式:换成 `friendlyErrorMessage(e, fallback: '点名失败的是什么')`
// (`lib/core/network/dio_client.dart`),原文交给 `debugPrint`,release 会剥掉。
// 上游是我方 API 层、已经回了中文业务原话(如「记录不可见」)时用同一处的
// `friendlyOrBackendMessage` —— 它只在异常是英文栈时才说人话。
// 真有必须照说原文的理由(如服务端裁决),用 `// cy-raw-error-ok: <为什么>`
// 标在该行或上一行 —— 例外必须仍然有事可做,见下面第二条 test。
//
// ⚠️ 不在 `catch` 块里的 `sub: '$error'` 不在此闸口径内:那些多是
//   `AsyncValue.when(error:)` 的槽位,而俱乐部 CRM 那一层的 API 已经把
//   DioException 归一成中文原话(`club_crm_api.dart` 的 `_fromDio`),照说才对。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 已在别线收口的文件:本线按铁律不碰,那边合入后豁免必须删掉(有 test 逼着)。
/// (rebase 到 #235 已落地的 main 后:#235 收口的两处均已无事可做,豁免清空。)
const Map<String, String> _pendingElsewhere = <String, String>{};

const String _marker = 'cy-raw-error-ok';

final RegExp _catchRe = RegExp(r'\bcatch\s*\(');
final RegExp _rawErrorInterp = RegExp(r'\$(?:e|error)\b');

int _indent(String line) => line.length - line.trimLeft().length;

/// 剥整行注释与行尾注释(行号不变),照 `test/support/source_text.dart` 的口径。
List<String> _codeLines(List<String> raw) => raw.map((String line) {
  final String t = line.trimLeft();
  if (t.startsWith('//')) return '';
  final int at = line.indexOf('//');
  return at >= 0 ? line.substring(0, at) : line;
}).toList();

/// 每个 catch 块的 body 行区间(含 catch 那一行,防一行写完的写法)。
/// 按缩进切块 —— `dart format` 之后 block body 一定比 `catch` 那行深。
List<List<int>> _catchBodies(List<String> code) {
  final List<List<int>> out = <List<int>>[];
  for (int i = 0; i < code.length; i++) {
    if (!_catchRe.hasMatch(code[i])) continue;
    final int catchIndent = _indent(code[i]);
    int end = code.length - 1;
    for (int j = i + 1; j < code.length; j++) {
      final String t = code[j].trim();
      if (t.isEmpty) continue;
      if (_indent(code[j]) <= catchIndent && t.startsWith('}')) {
        end = j - 1;
        break;
      }
    }
    out.add(<int>[i, end]);
  }
  return out;
}

List<String> _hits(List<String> raw, List<String> code, int from, int to) {
  final List<String> out = <String>[];
  bool inDevPrint = false;
  for (int i = from; i <= to && i < code.length; i++) {
    if (code[i].contains('debugPrint(')) inDevPrint = true;
    final bool devPrint = inDevPrint;
    if (inDevPrint && code[i].contains(');')) inDevPrint = false;
    if (devPrint) continue;
    for (final RegExpMatch m in RegExp(
      r"'((?:[^'\\]|\\.)*)'",
    ).allMatches(code[i])) {
      if (!_rawErrorInterp.hasMatch(m.group(1)!)) continue;
      final bool marked =
          raw[i].contains(_marker) || (i > 0 && raw[i - 1].contains(_marker));
      if (!marked) out.add('${i + 1}: ${raw[i].trim()}');
      break;
    }
  }
  return out;
}

/// 返回 文件路径 → 违规行。
Map<String, List<String>> _scan() {
  final Map<String, List<String>> found = <String, List<String>>{};
  for (final FileSystemEntity e in Directory(
    'lib/feature',
  ).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final List<String> raw = e.readAsLinesSync();
    final List<String> code = _codeLines(raw);
    final List<String> hits = <String>[
      for (final List<int> body in _catchBodies(code))
        ..._hits(raw, code, body[0], body[1]),
    ];
    if (hits.isNotEmpty) found[e.path] = hits;
  }
  return found;
}

void main() {
  test('★★ lib/feature 的 catch 里不把异常原文拼进用户文案', () {
    final Map<String, List<String>> found = _scan();
    final List<String> offenders = <String>[
      for (final MapEntry<String, List<String>> entry in found.entries)
        if (!_pendingElsewhere.containsKey(entry.key))
          '${entry.key}\n  ${entry.value.join('\n  ')}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          '这些地方把异常原文(DioException 的英文栈)直接拼给了用户 —— '
          '换成 friendlyErrorMessage(e, fallback: \'点名失败的是什么\'),'
          '原文交 debugPrint:\n${offenders.join('\n')}',
    );
  });

  test('★ 别线豁免必须仍然有事可做 —— 收口后要删掉', () {
    final Map<String, List<String>> found = _scan();
    final List<String> stale = <String>[
      for (final MapEntry<String, String> entry in _pendingElsewhere.entries)
        if (!found.containsKey(entry.key)) '${entry.key}(${entry.value})',
    ];
    expect(
      stale,
      isEmpty,
      reason:
          '这些文件已经没有裸异常了,把 _pendingElsewhere 里的条目删掉:\n'
          '${stale.join('\n')}',
    );
  });

  test('★ 断言写法自查:换个变量名必须仍能扫到这一类', () {
    expect(_rawErrorInterp.hasMatch("'创建失败:\$e'"), isTrue);
    expect(_rawErrorInterp.hasMatch("'保存失败:\$error'"), isTrue);
    expect(_rawErrorInterp.hasMatch("'退款没有完成'"), isFalse);
    // 变量名别扩大打击面:`$errorText` 是另一回事。
    expect(_rawErrorInterp.hasMatch("'\$errorText'"), isFalse);
  });
}
