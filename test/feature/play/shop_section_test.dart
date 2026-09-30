import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/shop_section.dart';

PlayNode _n({Map<String, dynamic>? extra}) => PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': '长乐路旧物店', 'address': '长乐路 139 号', 'sortId': 1,
      'businessTime': '12:00-21:00',
      ...?extra,
    });

Future<void> _pump(WidgetTester t, PlayNode n,
        {VoidCallback? shop, VoidCallback nav = _noop}) async =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(body: ShopSection(node: n, onTapShop: shop, onTapNav: nav)),
    ));

void _noop() {}

void main() {
  testWidgets('店名与营业时间在', (t) async {
    await _pump(t, _n());
    expect(find.text('长乐路旧物店'), findsOneWidget);
    expect(find.textContaining('12:00-21:00'), findsOneWidget);
  });

  testWidgets('★有 npc 才渲染分身行', (t) async {
    await _pump(t, _n(extra: <String, dynamic>{
      'npc': <String, dynamic>{'name': '阿旧', 'greeting': 'hi'},
    }));
    expect(find.textContaining('阿旧'), findsOneWidget);
  });

  testWidgets('★没有 npc 就没有分身行 —— 没有分身就没有可点的东西', (t) async {
    await _pump(t, _n());
    expect(find.textContaining('店铺替身'), findsNothing);
  });

  testWidgets('★判据只有地址:有地址就渲整行,「导航」始终在(照样机 index.wxml:420)', (t) async {
    // ⚠️ 2026-09-09 裁决更正:上一版是「无坐标就不渲染导航二字」。样机 `.fx-shop__nav`
    //   的 wx:if 只看 address,坐标的事留给 openHeroNav 用一句提示回答 ——
    //   整行不渲染信息量更小:用户不知道这里本该能导航,也拿不到那句解释。
    //   坐标判据现在长在 card_detail_page 的 _navigate 里(见该页测试)。
    await _pump(t, _n());
    expect(find.text('长乐路 139 号'), findsOneWidget);
    expect(find.text('导航'), findsOneWidget);
  });

  testWidgets('★真的没有地址才不渲染这一行', (t) async {
    await _pump(t, PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': '长乐路旧物店', 'address': '', 'sortId': 1,
    }));
    expect(find.byIcon(Icons.place_outlined), findsNothing);
  });

  testWidgets('★openStatus 后端三态优先渲染', (t) async {
    await _pump(t, _n(extra: <String, dynamic>{'openStatus': '营业中'}));
    expect(find.textContaining('营业中'), findsOneWidget);
  });

  testWidgets('★已核销时不渲染营业态,但「今日 …」照渲', (t) async {
    await _pump(t, _n(extra: <String, dynamic>{'done': true, 'openStatus': '营业中'}));
    expect(find.textContaining('营业中'), findsNothing);
    // 样机那段「· 今日 …」在 wx:else 之外(index.wxml:408-413),已核销照渲。
    expect(find.text('已核销 · 今日 12:00-21:00'), findsOneWidget);
  });

  testWidgets('★openStatus 缺失时不渲染营业态,也不臆造占位文案', (t) async {
    await _pump(t, PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': '长乐路旧物店', 'address': '长乐路 139 号', 'sortId': 1,
    }));
    expect(find.textContaining('营业'), findsNothing);
    expect(find.textContaining('未知'), findsNothing);
    expect(find.textContaining('待'), findsNothing);
  });

  testWidgets('★导航行独立可点,不和整卡抢', (t) async {
    int shop = 0, nav = 0;
    await _pump(t, _n(extra: <String, dynamic>{'latitude': 31.2, 'longitude': 121.4}),
        shop: () => shop++, nav: () => nav++);
    await t.tap(find.text('导航'));
    await t.pump();
    expect(nav, 1);
    expect(shop, 0, reason: '点导航不该顺带触发进对话');
  });

  testWidgets('★导航行至少 44pt —— 原来实测 41.0pt', (t) async {
    await _pump(t, _n(), nav: () {});
    final double h = t.getSize(find.ancestor(
      of: find.text('导航'),
      matching: find.byType(Container),
    ).first).height;
    expect(h, greaterThanOrEqualTo(44.0), reason: 'iOS HIG / Material 的最小触达尺寸');
  });

  testWidgets('★两个手势区都有按钮语义和自己的 label(不是两段文本粘起来)', (t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await _pump(t, _n(extra: <String, dynamic>{
      'npc': <String, dynamic>{'name': '阿旧', 'greeting': 'hi'},
    }), shop: () {}, nav: () {});
    // 样机两处都写了 aria-role="button" + 专门的 label
    // (`和 {{npcName}} 对话` / `导航到 {{address}}`,index.wxml:402-403、421-423)。
    // 之前是裸 GestureDetector:读屏只拿到粘连的两段文本,连 button 都不是。
    for (final String label in <String>['和 阿旧 对话', '导航到 长乐路 139 号']) {
      final Finder f = find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == label,
        description: 'Semantics(label: "$label")',
      );
      expect(f, findsOneWidget, reason: '缺 label:$label');
      final SemanticsNode node = t.getSemantics(f);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue,
          reason: '「$label」没有 button 语义,读屏只会念一串文本');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.label.startsWith(label), isTrue,
          reason: '专门的 label 要排在最前,而不是被内容文本淹掉:${node.label}');
    }
    handle.dispose();
  });

  testWidgets('★★没有分身时读屏不许念「对话」—— 那家点了也不进页', (t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await _pump(t, _n(), shop: () {}, nav: () {});
    // ⚠️ 用「label 里有店名」认人,不用「以店名打头」—— 后者把要测的东西
    //    (文案长什么样)混进了找人的条件里:回落成「和 长乐路旧物店 对话」时
    //    finder 直接找不到,红在「Found 0 widgets」而不是红在「不许念对话」上。
    //    店名两种写法里都在,导航那颗的 `导航到 长乐路 139 号` 里没有。
    final Finder f = find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.button == true &&
          (w.properties.label ?? '').contains('长乐路旧物店'),
      description: 'Semantics(button, label 里带店名)',
    );
    expect(f, findsOneWidget, reason: '没有分身也还是一颗可点的按钮,只是点了给提示');
    final SemanticsNode node = t.getSemantics(f);
    expect(node.label.contains('对话'), isFalse,
        reason: '入口 card_detail_page.dart:131 只弹「这家还没有店铺分身」,'
            '念「和 长乐路旧物店 对话」= 承诺一个点不开的东西:${node.label}');
    expect(node.label.contains('这家还没有店铺分身'), isTrue,
        reason: '要念出真实结果,而不是只剩个店名');
    handle.dispose();
  });

  testWidgets('★营业态带状态色圆点,已核销不带', (t) async {
    await _pump(t, _n(extra: <String, dynamic>{'openStatus': '营业中'}));
    expect(_dots(t), 1, reason: '样机 .fx-tile__dot 跟在营业态前面');
    await _pump(t, _n(extra: <String, dynamic>{'done': true}));
    expect(_dots(t), 0, reason: '已核销那一档样机走 .fx-shop__off,没有点');
  });
}

/// 数一数圆点(BoxShape.circle 的 Container)。
int _dots(WidgetTester t) => t
    .widgetList<Container>(find.byType(Container))
    .where((Container c) =>
        c.decoration is BoxDecoration &&
        (c.decoration! as BoxDecoration).shape == BoxShape.circle)
    .length;
