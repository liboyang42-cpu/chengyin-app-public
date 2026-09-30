// 产品词汇:同一件东西在两个客户端不能叫两个名字。
//
// ★★ 小程序特意给几样东西起了有产品感的名字(「城市签名」「城市角色」),
//   App 此前用的是通用词(「简介」「在城市里的角色」)。
//   用户在两端看到同一样东西的两个名字,会以为是两回事。
//
// ⚠️ 这条**只锁点名的那几处**,不做全局替换 ——
//   小程序自己的俱乐部/模板/发布简介就叫「简介」,
//   全局替换会把那三处也改错。词汇对齐是**逐处**的,不是查找替换。

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★ 个人资料的自我介绍叫「城市签名」(小程序 gerenziliao:24)', () {
    final String src = codeOf('lib/feature/profile/profile_edit_page.dart');
    expect(src.contains("label: '城市签名'"), isTrue);
    expect(
      src.contains("label: '简介'"),
      isFalse,
      reason: '这一处小程序叫「城市签名」—— 通用词丢掉了产品感,也和另一端对不上',
    );
  });

  test('★ 商家的角色定位叫「城市角色」(小程序全仓 17 处)', () {
    final String src = codeOf('lib/feature/merchant/merchant_decor_page.dart');
    expect(
      src.contains("label: '城市角色名'"),
      isTrue,
      reason: '当前小程序 FIELDS.cityRole 的单字段 Sheet 真源文案',
    );
    expect(src.contains('在城市里的角色'), isFalse, reason: '自己改写的说法');
  });

  test('★★ 但**不许**把所有「简介」都改掉 —— 小程序那几处本来就叫简介', () {
    // 这条是防「对齐」变成一次粗暴的查找替换。
    for (final String f in <String>[
      'lib/feature/club/club_create_page.dart',
      'lib/feature/publish/publish_page.dart',
    ]) {
      expect(
        codeOf(f).contains("label: '简介'"),
        isTrue,
        reason: '$f 的「简介」被顺手改掉了 —— 小程序那一处就叫简介',
      );
    }
  });
}
