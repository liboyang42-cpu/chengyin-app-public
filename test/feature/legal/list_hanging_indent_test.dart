// 法律文本里的编号列表要能被识别成「列表行」,从而悬挂缩进。
//
// ★ 定稿文本里的列表写在同一个字符串里、用 \n 分行(《账号注销须知》第一节的
//   五种不可注销情形)。整段丢给一个 Text 时,换行会**顶格**到最左 ——
//   较长的第 4 条会断成「…处理相关业 / 务;」,「务;」孤零零顶在行首,
//   看着像新的一条。这是用户要阅读并同意的法律文本,读不清不是排版洁癖。
//
// 判据是「这一段被拆成了多个 Text」而不是像素 —— 像素归 golden 管,
// 这条管的是**结构**:整段一个 Text 时它必然红。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/legal/legal_doc_page.dart';
import 'package:chengyin_app/feature/legal/legal_docs.dart';

void main() {
  testWidgets('《账号注销须知》第一节的五条不是揉在一个 Text 里', (
    WidgetTester tester,
  ) async {
    final LegalDoc doc = legalDoc(LegalDocType.cancellationNotice);
    final String firstSection = doc.sections.first.p;
    // 前提自查:文本确实是用 \n 分行的多行段落(共 6 行:引子 + 五条)。
    expect(firstSection.split('\n').length, 6);

    await tester.pumpWidget(
      MaterialApp(home: LegalDocPage(type: LegalDocType.cancellationNotice)),
    );
    await tester.pumpAndSettle();

    // 每一条都应当独立成行可被找到(整段一个 Text 时,这些 find 全部落空)。
    for (final String tail in <String>[
      '账户存在未处理余额；',
      '法律法规规定的其他暂不能注销情形。',
    ]) {
      expect(
        find.text(tail),
        findsOneWidget,
        reason: '「$tail」没有独立成行 —— 说明整段仍被当成一个 Text 渲染',
      );
    }
  });
}
