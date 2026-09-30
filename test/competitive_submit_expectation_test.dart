// 竞争性提交必须说清「提交 ≠ 拿到」。
//
// ★★ 招商章节是**竞争位**:多家商家可以报同一个章节,主办方挑一家。
//   只说「已提交,等待审核」会让商家以为位置已经锁定 ——
//   他会按「已拿下」去安排排期和备货,落选时的损失是真的。
//
//   小程序的成功页专门有一句「报名成功不等于中标」
//   (pages/topic/merchantapply/index.wxml:88)。
//
// ⚠️ 这条与「猎假保证」是**一体两面**:
//   那条防「声称存在实际不生效」,这条防「让人以为已经拿到了」。
//   两个方向都是**对用户承诺了系统给不了的东西**。

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★ 承接申请的成功文案必须说明不等于中标', () {
    final String src = codeOf('lib/feature/merchant/merchant_recruit_page.dart');
    final int at = src.indexOf("message = '已提交");
    expect(at, greaterThan(0), reason: '断言写法失效了 —— 成功文案改写了?');
    // 锚到那一句本身,不做文件级检查(文件里别处也可能提到中标)。
    final String line =
        src.substring(at, (at + 120).clamp(0, src.length));
    expect(line.contains('不等于中标'), isTrue,
        reason: '招商是竞争位,只说「等待审核」会让商家以为位置已经锁定,'
            '按「已拿下」去排期备货,落选的损失是真的');
  });
}
