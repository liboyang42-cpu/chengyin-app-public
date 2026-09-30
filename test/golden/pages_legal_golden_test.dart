// 法律协议页视觉快照:用户服务协议(首屏 + 滚到中段,看章节排版)/
// 账号注销须知(含带 \n 的条款列表)/ 隐私政策「待提供」态 /
// 登录处那行可点协议文案。
//
// 本页只依赖 cy_tokens + cy_widgets,不碰 providers,故不需要 Riverpod override。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_legal_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'golden_theme.dart';
import 'package:chengyin_app/feature/legal/legal_doc_page.dart';
import 'package:chengyin_app/feature/legal/legal_docs.dart';

Widget _app(Widget home) => MaterialApp(
  theme: goldenTheme(),
  debugShowCheckedModeBanner: false,
  home: home,
);

void main() {
  testWidgets('法律文档:用户服务协议(首屏)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(const LegalDocPage(type: LegalDocType.userAgreement)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/legal_user_agreement.png'),
    );
  });

  testWidgets('法律文档:用户服务协议(滚到中段,看章节排版)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(const LegalDocPage(type: LegalDocType.userAgreement)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/legal_user_agreement_scrolled.png'),
    );
  });

  testWidgets('法律文档:账号注销须知(条款内换行列表)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(const LegalDocPage(type: LegalDocType.cancellationNotice)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/legal_cancellation_notice.png'),
    );
  });

  testWidgets('法律文档:隐私政策「待提供」态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(const LegalDocPage(type: LegalDocType.privacyPolicy)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/legal_privacy_pending.png'),
    );
  });

  testWidgets('登录处协议行:两个书名号是明链(与灰底文案有可辨差异)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 120));
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LegalConsentLine(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/legal_consent_line.png'),
    );
  });
}
