import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 选中参与人后,填进报名表单的必须是**原值**,不是掩码。
///
/// ★ 直接读源码而不是重建结构 —— 重建等于把被测逻辑在测试里抄一遍,
///   抄错了两边一起错,恒绿。这里读的是真文件真行。
void main() {
  test('报名表单填的是 mobilePhone 不是 maskedPhone', () {
    final src = File('lib/feature/activity/activity_detail_page.dart').readAsStringSync();
    final idx = src.indexOf('pickParticipant(context)');
    expect(idx, greaterThan(0), reason: '参与人选择器应当接在报名弹层里');

    // 只看选中之后那一小段赋值。
    final block = src.substring(idx, idx + 400);
    expect(block.contains('picked.mobilePhone'), isTrue,
        reason: '必须填原始号码,否则提交上去的是 138****1234 这种废数据');
    expect(block.contains('maskedPhone'), isFalse,
        reason: '掩码只用于列表显示,绝不能进可提交的表单');
  });

  test('全仓:掩码值不许被写进任何可提交的字段', () {
    // ★ 现在有两处展示参与人(报名选择器、管理页),将来可能更多。
    //   掩码是展示层;写进 controller / 请求体就会把 138****1234 存进库。
    final offenders = <String>[];
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('maskedPhone')) continue;
        // 「可提交」的位置有三类,漏一类门禁就是假的:
        //   ① 赋值进输入框:xxxCtrl.text = ...
        //   ② 放进 JSON 请求体:'phone': ...
        //   ③ 传给 API 的具名参数:mobilePhone: ...
        // ⚠️ 第一版只写了 ①②,负控(在管理页里传 mobilePhone: p.maskedPhone)
        //    **没有变红** —— 门禁当时是假的。这就是"负控必须做"的理由。
        final submittable = <RegExp>[
          RegExp(r'(Ctrl|Controller)\.text\s*='),
          RegExp(r"'(phone|mobilePhone|mobilephone|realName|realname)'\s*:"),
          RegExp(r'\b(phone|mobilePhone|mobilephone|realName|realname)\s*:'),
        ];
        if (submittable.any((RegExp re) => re.hasMatch(line))) {
          offenders.add('${f.path}:${i + 1}  $line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '掩码只用于显示。写进可提交字段会把 138****1234 存进库:\n'
            '${offenders.join('\n')}');
  });
}
