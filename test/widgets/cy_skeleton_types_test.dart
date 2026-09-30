// CySkeleton 真源补档(amount / form-section / ticket / merchant-metric /
// route-timeline / map-card / post-card)的几何门禁。
//
// 口径对齐真源 `components/cy/skeleton/index.wxss`,rpx÷2=pt:
// 每条断言旁边注明它核的是真源哪条规则。断言的是「结构画得对不对」,
// 不是像素观感 —— 观感由 skeleton_types_golden_test 取景。

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSkeleton(
  WidgetTester tester,
  CySkeletonType type, {
  int count = 3,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: CySkeleton(type: type, count: count),
      ),
    ),
  );
  // 微光是无限循环动画,pump 一帧进入稳定态即可(不打断则 find 不到渲染树)。
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
}

const Key kAmountLabel = ValueKey<String>('sk-amount-label');
const Key kAmountValue = ValueKey<String>('sk-amount-value');

void main() {
  testWidgets('amount:单块 label 32%×10 + 主数 56%×40,不随 count 重复', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.amount, count: 5);

    // 真源 .sk-amount 没有 wx:for —— count 再大也只画一块。
    expect(find.byKey(kAmountLabel), findsOneWidget);
    expect(find.byKey(kAmountValue), findsOneWidget);

    final Size label = tester.getSize(find.byKey(kAmountLabel));
    final Size value = tester.getSize(find.byKey(kAmountValue));
    // .sk-amount-label: height space-2-5(10pt), width 32%。
    expect(label.height, 10);
    expect(label.width, closeTo(0.32 * 768, 1));
    // .sk-amount-value: height space-7(40pt), width 56%。
    expect(value.height, 40);
    expect(value.width, closeTo(0.56 * 768, 1));
  });

  testWidgets('form-section:count 个「标签+44pt 输入框」同构字段', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.formSection, count: 3);

    // .sk-form-field ×count;.sk-form-input height --cy-btn-h(44pt)。
    expect(
      find.byKey(const ValueKey<String>('sk-form-input')),
      findsNWidgets(3),
    );
    final Size input = tester.getSize(
      find.byKey(const ValueKey<String>('sk-form-input')).first,
    );
    expect(input.height, 44);
    expect(input.width, closeTo(768, 1));
  });

  testWidgets('ticket:78% 宽 360pt 高票,4pt 侧带 + 66pt 票根', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.ticket, count: 1);

    final Size ticket = tester.getSize(
      find.byKey(const ValueKey<String>('sk-ticket')),
    );
    // .sk-ticket: width 78%, height 720rpx=360pt。
    expect(ticket.height, 360);
    expect(ticket.width, closeTo(0.78 * 768, 1));

    // .sk-ticket-stub: 132rpx=66pt。
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('sk-ticket-stub')))
          .height,
      66,
    );
    // .sk-ticket-band: space-1=4pt 宽,通高。
    final Size band = tester.getSize(
      find.byKey(const ValueKey<String>('sk-ticket-band')),
    );
    expect(band.width, 4);
    expect(band.height, 360);
    // 票面文案 + 票根两层动作位都在。
    expect(
      find.byKey(const ValueKey<String>('sk-ticket-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sk-ticket-time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sk-ticket-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sk-ticket-action')),
      findsOneWidget,
    );
  });

  testWidgets('merchant-metric:两列网格三张卡,列距=行距 12pt', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.merchantMetric, count: 3);

    for (final int i in <int>[0, 1, 2]) {
      expect(find.byKey(ValueKey<String>('sk-metric-$i')), findsOneWidget);
    }
    final Rect a = tester.getRect(
      find.byKey(const ValueKey<String>('sk-metric-0')),
    );
    final Rect b = tester.getRect(
      find.byKey(const ValueKey<String>('sk-metric-1')),
    );
    final Rect c = tester.getRect(
      find.byKey(const ValueKey<String>('sk-metric-2')),
    );
    // grid-template-columns: repeat(2,…) gap space-3(12pt)。
    expect(a.top, b.top);
    expect(b.left - a.right, 12);
    expect(a.width, closeTo((768 - 12) / 2, 1));
    expect(c.top - a.bottom, 12);
    // 第三张独占一行,与首列左对齐。
    expect(c.left, a.left);
  });

  testWidgets('route-timeline:3 行 3 点、连接线 count-1 条且不画过末行', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.routeTimeline, count: 3);

    expect(
      find.byKey(const ValueKey<String>('sk-route-dot')),
      findsNWidgets(3),
    );
    // .sk-route-row:last-child .sk-route-line { display:none }。
    expect(
      find.byKey(const ValueKey<String>('sk-route-line')),
      findsNWidgets(2),
    );
    // 12pt 圆点(space-3),连接线 2pt 宽(4rpx)。
    final Size dot = tester.getSize(
      find.byKey(const ValueKey<String>('sk-route-dot')).first,
    );
    expect(dot, const Size(12, 12));
    final Size line = tester.getSize(
      find.byKey(const ValueKey<String>('sk-route-line')).first,
    );
    expect(line.width, 2);
  });

  testWidgets('map-card:画布 260pt 高(520rpx --cy-map-h)整宽', (
    WidgetTester tester,
  ) async {
    // 一卡 ≈ 260+文案衬=302pt,3 卡超视口会被 ListView 懒加载裁掉,
    // 取景按 2 卡断言,条数密度真源由调用方 count 传(真源 searchmap count=3)。
    await pumpSkeleton(tester, CySkeletonType.mapCard, count: 2);

    final Finder canvases = find.byKey(const ValueKey<String>('sk-map-canvas'));
    expect(canvases, findsNWidgets(2));
    final Size canvas = tester.getSize(canvases.first);
    expect(canvas.height, 260);
    expect(canvas.width, closeTo(768, 1));
  });

  testWidgets('post-card:44pt 圆头像 + 31/89/70% 三长短线 + 230pt 媒体 + 3 动作', (
    WidgetTester tester,
  ) async {
    await pumpSkeleton(tester, CySkeletonType.postCard, count: 2);

    final Size avatar = tester.getSize(
      find.byKey(const ValueKey<String>('sk-post-avatar')).first,
    );
    // .sk-post-avatar: 88rpx=44pt 圆,须与真卡同径,否则加载完横向弹。
    expect(avatar, const Size(44, 44));

    // 正文列宽 = 768 - 44 头像 - 10 间距(space-2-5)= 714。
    const double col = 768 - 44 - 10;
    final Size l1 = tester.getSize(
      find.byKey(const ValueKey<String>('sk-post-l1')).first,
    );
    final Size l2 = tester.getSize(
      find.byKey(const ValueKey<String>('sk-post-l2')).first,
    );
    final Size l3 = tester.getSize(
      find.byKey(const ValueKey<String>('sk-post-l3')).first,
    );
    expect(l1.width, closeTo(0.31 * col, 1));
    expect(l2.width, closeTo(0.89 * col, 1));
    expect(l3.width, closeTo(0.70 * col, 1));
    // 线必须长短不一(真源注释):等长像表格不像文字。
    expect(l1.width < l2.width && l3.width < l2.width, isTrue);

    // .sk-post-media: 460rpx=230pt 高,圆角 16pt 同真卡。
    final Size media = tester.getSize(
      find.byKey(const ValueKey<String>('sk-post-media')).first,
    );
    expect(media.height, 230);
    expect(media.width, closeTo(col, 1));

    // .sk-post-act: 88rpx=44pt 宽 × space-3-5=14pt 高,一行三个。
    for (final int i in <int>[0, 1, 2]) {
      final Size act = tester.getSize(
        find.byKey(ValueKey<String>('sk-post-act-$i')).first,
      );
      expect(act.width, 44);
      expect(act.height, 14);
    }
  });
}
