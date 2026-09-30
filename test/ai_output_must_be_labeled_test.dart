// 有 AI 产出的界面必须带来源标注。
//
// ★★ 这**不是文案偏好,是合规标注**。小程序 club/detail/index.wxml:457
//   那行注释写得很直白:「合规:AI 生成内容来源标注」。
//   对用户它还有第二个作用:提醒「这段是机器写的,发出去之前你得看一遍」——
//   因为发出去之后署名的是**用户**,不是 AI。
//
// ⚠️ 2026-08-20 之前 App 的三个 AI 产出面(俱乐部 AI 策划 / 主题 AI 起草 /
//   节点 AI 助手)**一处都没标**。这条门禁拦的是「以后新增一个 AI 面又忘了标」。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★ 调了 AI 生成接口的界面,必须挂 AiGeneratedNote', () {
    final List<String> missing = <String>[];
    int scanned = 0;
    for (final FileSystemEntity e
        in Directory('lib/feature').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String code = codeOf(e.path);
      // 「产出面」= 真的调了生成类接口的文件。只引用 API 类型不算。
      // sendChat = NPC 自由追问,是**真调模型**的那一轨。
      // (事件冒泡话术不在内:NpcEventService 查表随机取预审变体、不调模型,
      //  小程序侧同样没标 —— 那不是生成内容。)
      final bool generates = RegExp(
              r'\.(themeDraft|clubDesign|nodeGenerate|sendChat)\s*\(')
          .hasMatch(code);
      if (!generates) continue;
      scanned++;
      if (!code.contains('AiGeneratedNote')) missing.add(e.path);
    }
    expect(scanned, greaterThanOrEqualTo(3),
        reason: '只扫到 $scanned 个 AI 产出面 —— 断言写法失效了(方法名改了?)');
    expect(missing, isEmpty,
        reason: '这些界面会显示 AI 生成的内容,却没有来源标注:\n${missing.join('\n')}');
  });

  test('★ 标注文案与小程序逐字一致 —— 同一句合规话不该有两种说法', () {
    final String src = codeOf('lib/core/widgets/ai_generated_note.dart');
    expect(src.contains('AI 生成内容,请核对后再发布'), isTrue);
  });
}
