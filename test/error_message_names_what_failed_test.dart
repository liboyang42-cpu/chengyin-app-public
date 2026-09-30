// 错误文案必须说清**什么**没加载出来。
//
// ★★ 小程序全仓的惯例是「XX没能加载出来」(类别 / 工作台 / 现成玩法 / 可投诉活动…),
//   而 App 里曾有 **20 处**笼统的「加载失败」。
//
//   差别不是措辞好看:一屏上常有多块内容各自加载,只说「加载失败」的话
//   用户不知道是**哪一块**挂了,也就不知道现在看到的内容还能不能信。
//
// ⚠️ 这条只管**页面上的**错误标题(StatusView / cy-error 那一层)。
//   API 层 `throw Exception(msg ?? '加载失败')` 是**兜底**,不在此列 ——
//   那里的第一选择永远是后端原话,兜底文案本来就不该抢戏。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★ 页面错误标题不许只说「加载失败」', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e
        in Directory('lib/feature').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('/npc/')) continue; // 用户在改的目录
      final String code = codeOf(e.path);
      // 只看 message:/title: 位上的,不看 API 兜底里的。
      if (RegExp(r"(?:message|title)\s*:\s*'加载失败'").hasMatch(code)) {
        offenders.add(e.path);
      }
    }
    expect(offenders, isEmpty,
        reason: '这些页面只说「加载失败」,没说是什么失败了 —— '
            '一屏上常有多块内容各自加载,用户不知道哪块挂了:\n'
            '${offenders.join('\n')}');
  });

  test('★ 断言写法自查:换个说法必须仍能扫到这一类', () {
    // 防止上面那条因为正则写窄而变成恒绿。
    const String sample = "StatusView(message: '加载失败', sub: 'x')";
    expect(RegExp(r"(?:message|title)\s*:\s*'加载失败'").hasMatch(sample), isTrue);
  });
}
