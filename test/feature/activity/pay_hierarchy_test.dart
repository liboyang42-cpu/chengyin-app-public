// 建单后,主按钮位必须让给「当下唯一能推进的动作」。
//
// ★ 起因:原先无论哪个阶段,主按钮(FilledButton,视觉最重)永远是「提交报名」;
//   建单之后它变成**禁用**的「已建单,请完成支付」,而真正的下一步——付款——
//   被挤到下面的 OutlinedButton 里。**视觉层级与动作层级正好反了**:
//   屏幕上最显眼的东西是死的,唯一能推进的动作反而被弱化。
//   这是资金路径:建了单没付款的人,唯一要做的事就是付款。
//
// ★ 判据为什么读源码而不是渲染:
//   报名表在 showModalBottomSheet 里,要整页 ActivityDetailPage + 网络 + 登录态才起得来。
//   我第一版写成「在测试里按同样结构重建一遍再断言」—— 那是**同义反复**:
//   真实页面怎么改它都不会红。读真实文件至少锁住的是真东西。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _path = 'lib/feature/activity/activity_detail_page.dart';

void main() {
  final String src = File(_path).readAsStringSync();

  test('「已建单」不再占按钮位 —— 它是陈述,不是动作', () {
    expect(
      src.contains('已建单，请完成支付'),
      isFalse,
      reason:
          '这句话曾经是禁用主按钮的文案。它描述状态、不提供动作,不该占按钮位;'
          '状态请用 Text 陈述,把按钮位让给付款。',
    );
  });

  test('付款动作挂在 CyNativeButton 主按钮位上', () {
    // 接线随 #30 的结算页重排搬了位置:建单后**同一颗**主按钮换成「去支付」,
    // onRetryPay 直接挂在它身上(不再另起一颗次要按钮)。取该按钮前后一段,
    // 看它被哪种控件承载、接的是不是付款。
    final int i = src.indexOf("key: const Key('signup-pay')");
    expect(i, greaterThan(0), reason: '没找到付款按钮的接线,结构可能已变,请更新本断言');
    final String around = src.substring(i, (i + 300).clamp(0, src.length));
    expect(around.contains('onRetryPay'), isTrue,
        reason: '主按钮没接付款动作 ——'
            '建了单没付款的人唯一要做的事被挤到了次要位置');
    expect(around.contains("'去支付'"), isTrue,
        reason: '建单后主按钮该换成付款动作(去支付),不是一句陈述');
    final String before = src.substring((i - 200).clamp(0, src.length), i);
    expect(
      before.lastIndexOf('CyNativeButton') >
          before.lastIndexOf('OutlinedButton'),
      isTrue,
      reason:
          '付款动作必须在 Apple 原生主按钮位;'
          '把它放回次要按钮等于让最显眼的位置继续空着',
    );
  });
}
