// 已选图片上的「删除」热区必须够大。
//
// ★★ 用**真渲染量尺寸**,不看代码猜:
//   `Icon(size: 14)` + `padding: 2` 算出来是 18pt,但那只是我的心算 ——
//   实际热区由 GestureDetector 的 child 布局决定,得渲出来 getSize 才算数。
//   (本轮我刚写过一个恒绿的"长文本溢出"探针,教训是:
//    判尺寸/热区只认渲染回读,不认正则和心算。)
//
// ★ 44pt 是 iOS HIG 与 Material 共同的最小触达尺寸。
//   这个钮是**删除已选照片** —— 点不中的代价是反复戳,
//   而它又压在图片角上,周围全是可滑动区域,更难点。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/square/square_compose_page.dart';

void main() {
  testWidgets('★★ 删除已选图的热区 ≥ 44pt', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SquareComposeThumb(
          url: 'https://example.invalid/a.png',
          onRemove: () {},
        ),
      ),
    ));
    await tester.pump();

    final Finder remove = find.byKey(SquareComposeThumb.removeKey);
    expect(remove, findsOneWidget, reason: '删除钮不见了');

    final Size s = tester.getSize(remove);
    expect(s.width, greaterThanOrEqualTo(44),
        reason: '删除热区只有 ${s.width}pt —— 低于 44pt 的最小触达尺寸;'
            '它压在图片角上、周围全是可滑动区域,点不中会反复戳');
    expect(s.height, greaterThanOrEqualTo(44),
        reason: '删除热区只有 ${s.height}pt 高');
  });
}
