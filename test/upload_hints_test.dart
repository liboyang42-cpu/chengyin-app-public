// 上传位必须标出要求的图片比例。
//
// ★★ 小程序在 6 处上传位都标了(俱乐部封面/头像、个人背景图、玩法封面、勋章图…),
//   App 此前只有 club_create 一处写了。
//
//   这不是装饰:用户传一张竖图当 16:9 封面,系统只能裁 ——
//   **裁掉的往往正是他想让人看到的那部分**。事前一句话,好过事后一张被裁坏的图。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('文案格式与小程序一致 —— 同一件事不该有两种说法', () {
    final String src = codeOf('lib/core/widgets/upload_hints.dart');
    expect(src.contains('16:9 横图'), isTrue);
    expect(src.contains('1:1 方图'), isTrue);
  });

  test('★★ 有固定比例要求的上传位,必须把比例说出来', () {
    // 判据:文件里出现 `aspect:` 这类固定比例的图片位,
    // 就应该能在同一份文件里找到比例提示。
    final List<String> missing = <String>[];
    int scanned = 0;
    for (final FileSystemEntity e
        in Directory('lib/feature').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('/npc/')) continue; // 用户在改的目录
      final String code = codeOf(e.path);
      // ⚠️ 判据要锚到**每一个**比例位,不能只查「这份文件里有没有提示」——
      //   第一版就是文件级的:同一份文件里另一个位标了,这个位没标也照样绿
      //   (负控当场证伪)。
      for (final RegExpMatch m
          in RegExp(r'aspect:\s*16\s*/\s*9').allMatches(code)) {
        scanned++;
        // 往前找它所属的那个组件的开头(取 300 字符窗口)。
        final int from = (m.start - 300).clamp(0, code.length);
        final String seg = code.substring(from, m.start);
        if (!seg.contains('kHint16x9') && !seg.contains('uploadHint')) {
          missing.add('${e.path}  (offset ${m.start})');
        }
      }
    }
    expect(scanned, greaterThan(0),
        reason: '一个 16:9 的图片位都没扫到 —— 断言写法失效了');
    expect(missing, isEmpty,
        reason: '这些页面要求 16:9,却没告诉用户:\n${missing.join('\n')}');
  });
}
