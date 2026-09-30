// 协议行的可点区必须够大。
//
// ★ 为什么单独立一条:`legal_consent_line_test.dart` 已经证明「点了能跳」,但那是
//   用 `tapOnText` 精确命中文字中心点的——**它永远不会因为热区太小而失败**。
//   真人用拇指点一行 16pt 高的小字会点空,而所有现有测试都是绿的。
//   这正是「截图/tap 测试证明不了热区」那一类:热区要用数值回读,不能靠点得中。
//
// 阈值取 Apple HIG 的最小可点尺寸 44pt(Android Material 是 48dp,取宽松那个)。
// 这行是 App Store 审核员必点的两个链接,点不中直接影响过审。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/legal/legal_doc_page.dart';

void main() {
  testWidgets('《用户协议》《隐私政策》的可点高度 ≥ 44pt(HIG 最小可点尺寸)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: LegalConsentLine())),
      ),
    );
    await tester.pumpAndSettle();

    // 行内链接的命中盒 = 该 span 所在行的文字盒,所以量整行的行盒高度即可。
    final RenderBox box = tester.renderObject<RenderBox>(
      find.byType(RichText).first,
    );
    expect(
      box.size.height,
      greaterThanOrEqualTo(44.0),
      reason: '行盒只有 ${box.size.height}pt —— 拇指点不中,'
          '而 tapOnText 那种精确命中的测试抓不到这个',
    );
  });
}
