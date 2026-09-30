// 商家工作台的消息入口与未读角标。
//
// ★★ 消息入口此前**只在「我的」页** —— 而合作邀约、官方通知都落在消息里,
//   商家在工作台完全看不到。小程序的结算页就挂着「查看聊天与系统通知」。
//
// ⚠️ 未读数**拿不到时不显示角标**,不显示 0 ——
//   「确实没有新消息」和「没查到」对用户是两回事。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  final String src = codeOf('lib/feature/merchant/merchant_home_page.dart');

  test('★ 工作台有消息入口', () {
    expect(src.contains("Key('merchant-im-entry')"), isTrue);
    expect(src.contains("push('/im')"), isTrue);
  });

  test('★★ 未读拿不到(null)时不显示角标 —— 不是显示 0', () {
    // 判据要同时看 null 和 >0 两条,只判其一都会漏。
    expect(src.contains('unread != null && unread > 0'), isTrue,
        reason: '显示「0」会让人以为确实没有新消息,而实际是没查到');
  });

  test('★ 未读数拉失败不打红工作台 —— 它只是个附加信息', () {
    final int at = src.indexOf('merchantUnreadProvider');
    expect(at, greaterThan(0));
    expect(src.substring(at).contains('catch (_) {'), isTrue,
        reason: '一个角标不该让整个工作台报错');
  });

  test('★ 三位数封顶 99+ —— 否则角标比图标还宽', () {
    // 角标本体走共用件 `CyBadge`(手动版拿的是暗端 `CyTokens.statusDanger`
    // 配 `Colors.white`,在恒浅的商家页上红不对、白字对比度也不足)——
    // 封顶因此落在共用件里,判据随之挪到那边,页面只负责给计数。
    expect(src.contains('CyBadge(count: unread'), isTrue);
    expect(
      codeOf('lib/core/widgets/cy_widgets.dart').contains("n > 99 ? '99+'"),
      isTrue,
      reason: '封顶挪进 CyBadge 后,这条判据必须跟着走 —— 否则等于没人守',
    );
  });
}
