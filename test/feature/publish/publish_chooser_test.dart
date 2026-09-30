// 发布选择面:锁态要说清「谁能用 + 怎么解锁」,且真的按不动。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/publish/publish_capability.dart';
import 'package:chengyin_app/feature/publish/publish_chooser_sheet.dart';

void main() {
  test('★★ 四张卡与小程序一一对齐,顺序不变', () {
    final List<PublishCard> c = publishCards(const PublishCapability());
    expect(c.length, 4);
    expect(c.map((PublishCard x) => x.subtitle).toList(), <String>[
      '一条城市路线',
      '一个节点玩法',
      '单场活动',
      '优惠券',
    ]);
    expect(c.map((PublishCard x) => x.title).toList(), <String>[
      '发布主题',
      '发布模板',
      '发布',
      '创建',
    ]);
    expect(c[0].tag, '从灵感到可玩，只差一次发布');
    expect(c[1].tag, '沉淀可复用的玩法，给路线当积木');
    expect(c[2].art, PublishCardArt.locked);
    expect(c[3].art, PublishCardArt.locked);
  });

  test('★★ fail-closed:拿不到身份(默认 player)⇒ 活动与优惠券都锁着', () {
    // PublishCapability 的默认值就是 player —— 未知身份不放行。
    final List<PublishCard> c = publishCards(const PublishCapability());
    expect(c[0].unlocked, isTrue, reason: '发主题人人可用');
    expect(c[1].unlocked, isTrue, reason: '发模板人人可用');
    expect(c[2].unlocked, isFalse, reason: '仅俱乐部主理人');
    expect(c[3].unlocked, isFalse, reason: '仅商家');
  });

  test('俱乐部主理人解锁活动,但不解锁优惠券', () {
    final List<PublishCard> c = publishCards(
      const PublishCapability(role: 'club'),
    );
    expect(c[2].unlocked, isTrue);
    expect(c[2].art, PublishCardArt.activity);
    expect(c[3].unlocked, isFalse);
  });

  test('商家解锁优惠券,但不解锁活动', () {
    final List<PublishCard> c = publishCards(
      const PublishCapability(role: 'merchant', isMerchant: true),
    );
    expect(c[2].unlocked, isFalse);
    expect(c[3].unlocked, isTrue);
    expect(c[3].art, PublishCardArt.template);
  });

  test('★ 每张锁着的卡都必须说清「为什么锁」和「怎么解锁」', () {
    for (final PublishCard c in publishCards(const PublishCapability())) {
      if (c.unlocked) continue;
      expect(c.lockedWhy, isNotNull);
      expect(c.lockedHow, isNotNull);
      expect(
        c.lockedHow!.contains('解锁'),
        isTrue,
        reason: '只说「暂未解锁」等于什么都没说 —— 要告诉人怎么才能用',
      );
    }
  });

  testWidgets('★★ 锁着的卡按钮真的按不动 —— 不给一个点下去什么都不发生的钮', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(),
          ),
        ].cast(),
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPublishChooser(c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // PageView 只渲当前页,先确认第一张是解锁的。
    expect(find.byKey(const Key('publish-card-cta-一条城市路线')), findsOneWidget);
    final CupertinoButton first = t.widget<CupertinoButton>(
      find.byKey(const Key('publish-card-cta-一条城市路线')),
    );
    expect(first.onPressed, isNotNull);

    // 翻到「单场活动」那张。
    await t.drag(find.byType(PageView), const Offset(-800, 0));
    await t.pumpAndSettle();
    await t.drag(find.byType(PageView), const Offset(-800, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('publish-card-locked-单场活动')), findsOneWidget);
    final CupertinoButton act = t.widget<CupertinoButton>(
      find.byKey(const Key('publish-card-cta-单场活动')),
    );
    expect(act.onPressed, isNull, reason: '锁着就要真按不动;给个能按但什么都不发生的钮是假保证');
  });

  testWidgets('发布主题不直达编辑器：先选主题类型，再选创建方式', (WidgetTester t) async {
    String? route;
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(),
          ),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: PublishChooserView(
              onNavigate: (String value) => route = value,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('publish-card-cta-一条城市路线')));
    await t.pumpAndSettle();
    expect(find.text('选择主题类型'), findsOneWidget);
    expect(route, isNull, reason: '选主题前不能直接进编辑器');

    await t.tap(find.byKey(const Key('publish-topic-mode-2')));
    await t.pumpAndSettle();
    expect(find.text('选择创建方式'), findsOneWidget);
    expect(find.text('快速配置'), findsOneWidget);
    expect(find.text('专业手动'), findsOneWidget);

    await t.tap(find.byKey(const Key('publish-topic-quick')));
    expect(route, '/publish?mode=2');
  });

  testWidgets('一级恢复四张横向大卡、源插画比例与四个页码点', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(),
          ),
        ].cast(),
        child: const MaterialApp(home: Scaffold(body: PublishChooserView())),
      ),
    );
    await t.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    final AspectRatio art = t.widget<AspectRatio>(
      find.byKey(const Key('publish-card-art-一条城市路线')),
    );
    expect(art.aspectRatio, closeTo(340 / 215, 0.0001));
    for (int i = 0; i < 4; i++) {
      expect(find.byKey(Key('publish-chooser-dot-$i')), findsOneWidget);
    }
  });

  testWidgets('专业手动入口携带已选模式到真实 /publish/pro', (WidgetTester t) async {
    String? route;
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(),
          ),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: PublishChooserView(
              onNavigate: (String value) => route = value,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('publish-card-cta-一条城市路线')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('publish-topic-mode-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('publish-topic-pro')));
    expect(route, '/publish/pro?mode=1');
  });

  testWidgets('模板卡先进价值主张页，不直达编辑器', (WidgetTester t) async {
    String? route;
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          publishCapabilityProvider.overrideWith(
            (Ref ref) async => const PublishCapability(),
          ),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: PublishChooserView(
              onNavigate: (String value) => route = value,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.drag(find.byType(PageView), const Offset(-800, 0));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('publish-card-cta-一个节点玩法')));
    expect(route, '/template/intro');
  });
}
