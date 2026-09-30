// 「协议入口可点」的行为测试 —— 截图只能证明长什么样,证明不了点下去会发生什么。
// 这里真的 tap 那两个书名号,断言导航确实落到了对应文档。
//
// 顺带守住文本移植的完整性(节数 / 首尾节标题),防止将来有人截断或"顺手润色"。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/feature/legal/legal_doc_page.dart';
import 'package:chengyin_app/feature/legal/legal_docs.dart';

/// 最小路由宿主:首页只放协议行,/legal/:type 走真实页面。
Widget _host() {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: Center(child: LegalConsentLine())),
      ),
      GoRoute(
        path: '/legal/:type',
        builder: (_, GoRouterState state) =>
            LegalDocPage(type: state.pathParameters['type'] ?? ''),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('点《用户服务协议》→ 进同名文档页(与真源文档名一致)', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocPage), findsNothing);

    await tester.tapOnText(find.textRange.ofSubstring('《用户服务协议》'));
    await tester.pumpAndSettle();

    expect(find.byType(LegalDocPage), findsOneWidget);
    expect(find.text('用户服务协议'), findsOneWidget);
    // 正文真的渲染出来了,不是空壳页。
    expect(find.textContaining('一、协议主体与生效'), findsOneWidget);
  });

  testWidgets('点《隐私政策》→ 进隐私政策的「待提供」态(不是用户协议)', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tapOnText(find.textRange.ofSubstring('《隐私政策》'));
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('该文档待提供'), findsOneWidget);
    // 负控:不能拿用户协议的正文来充数。
    expect(find.textContaining('一、协议主体与生效'), findsNothing);
  });

  testWidgets('非链接部分点了不跳转(别把整行都做成按钮)', (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tapOnText(find.textRange.ofSubstring('登录即同意'));
    await tester.pumpAndSettle();

    expect(find.byType(LegalDocPage), findsNothing);
  });

  test('移植自小程序的两份定稿文本没有被截断', () {
    final LegalDoc ua = legalDoc(LegalDocType.userAgreement);
    expect(ua.version, 'v2.2');
    expect(ua.updatedAt, '2026-08-12');
    expect(ua.sections.length, 13);
    expect(ua.sections.first.h, '一、协议主体与生效');
    expect(ua.sections.last.h, '十三、联系我们');

    final LegalDoc cn = legalDoc(LegalDocType.cancellationNotice);
    expect(cn.version, 'v2.1');
    expect(cn.sections.length, 5);
    expect(cn.sections.first.h, '一、注销条件');
    expect(cn.sections.last.h, '五、撤销与申诉');
    // 第一节的分号列表靠 \n 换行,别在移植时被吃掉。
    expect(cn.sections.first.p.split('\n').length, 6);
  });

  test('隐私政策是「待提供」占位,不许被别的文本顶包', () {
    final LegalDoc pp = legalDoc(LegalDocType.privacyPolicy);
    expect(pp.title, '隐私政策');
    expect(pp.pending, isTrue);
    expect(pp.sections, isEmpty);
  });

  test('未知 type 兜底到用户服务协议,不返回空白页', () {
    expect(legalDoc('nope').title, '用户服务协议');
  });

  // R10(收款模型 2026-09-15 定稿 §3):提现 = 联系平台客服线下处理
  // (真源 `utils/withdraw-cs.js` 只给「返回」「复制」两枚按钮),App 侧已删除
  // 银行卡表单与转零钱入口。协议里再出现这两种提现,就是在承诺一条不存在的
  // 入口 —— 商城域 B1 报告点名过这一处,故留门禁防回退。
  test('协议正文不再出现银行卡 / 微信零钱提现(R10)', () {
    for (final LegalDoc doc in kLegalDocs.values) {
      final String all = <String>[
        doc.intro ?? '',
        for (final LegalSection s in doc.sections) '${s.h}\n${s.p}',
      ].join('\n');
      expect(all.contains('银行卡'), isFalse, reason: '《${doc.title}》仍提银行卡');
      expect(all.contains('微信零钱'), isFalse, reason: '《${doc.title}》仍提微信零钱');
      expect(all.contains('风险确认'), isFalse, reason: '《${doc.title}》仍提风险确认');
    }
  });
}
