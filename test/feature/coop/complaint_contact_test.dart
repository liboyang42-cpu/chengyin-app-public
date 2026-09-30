// 投诉的联系方式:后端没有这个字段,靠拼进 reason。
//
// ★★ 小程序 complaint/index.js:131 —— `reason = reason + '\n联系方式：' + contact`。
//   后端 `/api/coop/complaint/report` 只收 {topicId, reason}。
//   自己另发一个后端不认的字段 = 用户填了等于没填。
//
// ⚠️ 我第一次读那页时只看了提交语句 `data: JSON.stringify({topicId, reason})`
//   就判定「小程序收集了但不发送、是死字段」——**错的**,拼接在上面几行。
//   看提交语句不看它上面的赋值,会把「换了个地方发」读成「没发」。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  test('★★ 联系方式必须拼进 reason,不能另发一个字段', () {
    final String src = codeOf('lib/feature/coop/complaint_page.dart');
    // ⚠️ 断言要锚到**调用处**,不是「这个方法定义还在」——
    //   第一版只查了方法名存在,把调用点改回 _reason.text 也照样绿。
    expect(
      RegExp(r'reason:\s*_composedReason\(\)').hasMatch(src),
      isTrue,
      reason: '提交时没有用拼好的 reason —— 联系方式发不出去',
    );
    expect(
      src.contains(r"'$r\n联系方式：$c'"),
      isTrue,
      reason: '必须与小程序保持全角冒号的客服阅读格式',
    );
    // 别自作主张加一个后端不认的参数。
    expect(
      RegExp(r"contact\s*:").hasMatch(src),
      isFalse,
      reason: '后端没有 contact 这个字段,发过去会被忽略 —— 用户填了等于没填',
    );
  });

  test('★ 没填联系方式时不留一个空的「联系方式:」尾巴', () {
    final String src = codeOf('lib/feature/coop/complaint_page.dart');
    expect(
      src.contains('c.isEmpty ? r :'),
      isTrue,
      reason: '空的话直接返回正文 —— 否则客服看到一行没有内容的「联系方式:」',
    );
  });

  test('联系方式是**选填** —— 不填也能提交', () {
    final String src = codeOf('lib/feature/coop/complaint_page.dart');
    // 提交条件里只能有主题和正文,不许把联系方式也变成必填。
    expect(
      src.contains('_contact.text.trim().isNotEmpty &&'),
      isFalse,
      reason: '小程序那边是可选的,变成必填会把不想留电话的人挡在外面',
    );
  });
}
