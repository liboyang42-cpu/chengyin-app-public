// 帖文正文的富文本呈现。
//
// ★ 对照小程序(`components/cy/post-card/index.wxml`):正文是纯文本,
//   夹 2 行 + 一个点了没用的「展开」提示。App 这条线要:保换行/段落、
//   标 @/#、真展开、屏幕阅读器能整段朗读。

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/feature/square/square_post_content.dart';

void main() {
  group('正文分词', () {
    test('@提及 与 #话题 单独成 token,其余是普通文本', () {
      final List<SquareContentToken> tokens = squareContentTokens(
        '谢谢 @阿兰 带路 #苏州河夜行',
      );
      expect(
        tokens.map((SquareContentToken t) => '${t.kind.name}:${t.text}'),
        <String>['text:谢谢 ', 'mention:@阿兰', 'text: 带路 ', 'topic:#苏州河夜行'],
      );
    });

    test('邮箱、价格里的符号不算 token —— 要有边界', () {
      final List<SquareContentToken> tokens = squareContentTokens(
        '联系 a@b.com,票价 5#6,再来(@阿兰,#话题)',
      );
      expect(
        tokens.where((t) => t.kind != SquareContentTokenKind.text),
        isNotEmpty,
      );
      final List<String> tags = tokens
          .where((t) => t.kind != SquareContentTokenKind.text)
          .map((t) => t.text)
          .toList();
      expect(tags, <String>['@阿兰', '#话题'], reason: '句首/标点后才是 token 起点');
    });

    test('超长的 @ 串不吞整句', () {
      final String long = '@${'字' * (squareContentTagMaxLength + 1)}';
      final List<SquareContentToken> tokens = squareContentTokens('看 $long 这里');
      expect(
        tokens.any((t) => t.kind != SquareContentTokenKind.text),
        isFalse,
        reason: '超过 $squareContentTagMaxLength 字就不当成一个整体',
      );
    });

    test('换行切段,空行保留', () {
      final List<List<SquareContentToken>> paragraphs = squareContentParagraphs(
        '第一段\n\n第二段\r\n第三段',
      );
      expect(paragraphs.length, 4);
      expect(paragraphs[1], isEmpty, reason: '空行要留一个空段,否则段间距会塌掉');
      expect(paragraphs[2].first.text, '第二段');
    });
  });

  group('正文组件', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[CyPalette.dark]),
      home: Scaffold(body: SizedBox(width: 320, child: child)),
    );

    testWidgets('短正文不出现展开入口,按段落铺开', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const SquarePostContent(text: '第一段\n\n第二段 @阿兰 #夜行')),
      );
      expect(find.text('第一段', findRichText: true), findsOneWidget);
      expect(find.text('第二段 @阿兰 #夜行', findRichText: true), findsOneWidget);
      expect(find.byKey(const Key('square-content-toggle')), findsNothing);
    });

    testWidgets('长正文先夹断,点「展开全文」后铺开,再点收起', (WidgetTester tester) async {
      final String long = List<String>.generate(
        8,
        (int i) => '第 $i 段:苏州河边的风比昨天轻,路灯一盏盏亮起来。',
      ).join('\n');
      await tester.pumpWidget(wrap(SquarePostContent(text: long)));

      expect(find.byKey(const Key('square-content-collapsed')), findsOneWidget);
      expect(find.text('展开全文'), findsOneWidget);
      expect(find.byKey(const Key('square-content-expanded')), findsNothing);

      await tester.tap(find.byKey(const Key('square-content-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('square-content-expanded')), findsOneWidget);
      expect(find.text('第 7 段:苏州河边的风比昨天轻,路灯一盏盏亮起来。'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);

      await tester.tap(find.byKey(const Key('square-content-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('square-content-collapsed')), findsOneWidget);
    });

    testWidgets('expandable: false 时只铺开,不给二次展开', (WidgetTester tester) async {
      final String long = List<String>.generate(
        8,
        (int i) => '第 $i 行',
      ).join('\n');
      await tester.pumpWidget(
        wrap(SquarePostContent(text: long, expandable: false)),
      );
      expect(find.byKey(const Key('square-content-expanded')), findsOneWidget);
      expect(find.byKey(const Key('square-content-toggle')), findsNothing);
    });

    testWidgets('屏幕阅读器能整段读到正文,展开按钮有 button 语义', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final String long = List<String>.generate(
        8,
        (int i) => '第 $i 段:苏州河边的风比昨天轻。',
      ).join('\n');
      await tester.pumpWidget(wrap(SquarePostContent(text: long)));

      final SemanticsNode body = tester.getSemantics(
        find.byKey(const Key('square-content-collapsed')),
      );
      expect(body.label, contains('第 7 段'), reason: '折叠态下也要能朗读全文,不是只读可见部分');
      expect(find.bySemanticsLabel('展开全文'), findsOneWidget);
      handle.dispose();
    });
  });
}
