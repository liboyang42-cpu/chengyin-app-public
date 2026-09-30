// 发布确认弹层 × 发布者实名 —— 三入口接线之三(RUN-52)。
//
// 钉住真源 pages/publish/fabu/index.js `confirmPublishCheck` 的形态:
// · 已登记的人整节不见,只多一行「发布者实名已登记」;
// · 未登记时三格就在弹层里,点「继续发布」先落实名、再放行 ——
//   topic 创建那一发永远在登记之后(后端两道闸就是这个顺序);
// · 三项不齐点「继续发布」不打空炮:报第一条没满足的原因,弹层不关;
// · 登记失败弹层不关、字段原地,报错用软红整块,不给输入框描红边。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/publisher_identity_api.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity_fields.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';
import 'package:chengyin_app/feature/publish/publish_pro_sheets.dart';

import '../../support/fake_publisher_identity.dart';

class _Harness {
  _Harness({bool alreadyRegistered = false})
    : identity = PublisherIdentityController(
        source: kIdentitySourceTopicPublish,
        registered: alreadyRegistered,
      );

  final FakePublisherIdentityApi api = FakePublisherIdentityApi();
  final PublisherIdentityController identity;
  int registerInvoked = 0;

  Future<IdentityRegisterOutcome> register(
    PublisherIdentityController form,
  ) async {
    registerInvoked++;
    try {
      await api.register(
        realName: form.realName.text.trim(),
        idCard: normalizeIdCard(form.idCard.text),
        consent: true,
        source: form.source,
      );
      return const IdentityRegisterOutcome.ok();
    } catch (e) {
      return IdentityRegisterOutcome.fail(
        (e is PublisherIdentityException) ? e.message : '网络异常，实名信息没有提交成功',
        network: e is! PublisherIdentityException,
      );
    }
  }
}

/// 打开「发布前检查」弹层(不返回 pop 结果,pop 断言看控件是否还在)。
Future<void> _show(WidgetTester t, _Harness? h) async {
  await t.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) => CupertinoButton(
            onPressed: () => showPublishCheckSheet(
              c,
              blocking: const <PublishCheckItem>[],
              advisory: const <PublishCheckItem>[],
              identity: h?.identity,
              registerIdentity: h?.register,
            ),
            child: const Text('开'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
}

Future<void> _fill(WidgetTester t) async {
  await t.enterText(
    find.byKey(const ValueKey<String>('identity-real-name')),
    '陈晨',
  );
  await t.enterText(
    find.byKey(const ValueKey<String>('identity-id-card')),
    '99000019491231019X',
  );
  await t.tap(find.byKey(const Key('identity-consent')));
  await t.pump();
}

void main() {
  const continueBtn = Key('publish-check-continue');

  testWidgets('已登记:整节收成一行状态,点「继续发布」直接放行、不再登记', (
    WidgetTester t,
  ) async {
    final h = _Harness(alreadyRegistered: true);
    await _show(t, h);

    expect(find.text('发布者实名已登记'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('identity-real-name')),
      findsNothing,
      reason: '已登记的人不再给填字段的入口(改绑走人工)',
    );

    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(h.registerInvoked, 0);
    expect(h.api.registerCalls, isEmpty);
  });

  testWidgets('未登记:三项齐了点「继续发布」= 先落实名、再放行', (
    WidgetTester t,
  ) async {
    final h = _Harness();
    await _show(t, h);

    expect(
      find.byKey(const ValueKey<String>('identity-real-name')),
      findsOneWidget,
    );
    await _fill(t);
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();

    expect(h.registerInvoked, 1);
    expect(h.api.registerCalls, <Map<String, Object?>>[
      <String, Object?>{
        'realName': '陈晨',
        'idCard': '99000019491231019X',
        'consent': true,
        'source': 'topic_publish',
      },
    ]);
    // 放行 = 弹层 pop true,由发布页续发 topic 那一发;登记成功后字段当场收起。
    expect(
      find.byKey(const ValueKey<String>('identity-id-card')),
      findsNothing,
    );
  });

  testWidgets('三项不齐点「继续发布」不打空炮:说第一条没满足的、弹层不关', (
    WidgetTester t,
  ) async {
    final h = _Harness();
    await _show(t, h);

    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(h.registerInvoked, 0);
    expect(find.text('请填写真实姓名'), findsWidgets);
    expect(find.byKey(continueBtn), findsOneWidget, reason: '弹层不关');

    // 填了姓名,下一条按实名顺序说话。
    await t.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(find.text('身份证号格式不正确，请核对后重填'), findsWidgets);
    expect(find.byKey(continueBtn), findsOneWidget);
  });

  testWidgets('没勾单独同意仍是闸:个保法 §29 要显式同意', (
    WidgetTester t,
  ) async {
    final h = _Harness();
    await _show(t, h);
    await t.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await t.enterText(
      find.byKey(const ValueKey<String>('identity-id-card')),
      '99000019491231019X',
    );
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(h.registerInvoked, 0);
    expect(find.text('请先同意提供真实姓名与身份证号'), findsWidgets);

    await t.tap(find.byKey(const Key('identity-consent')));
    await t.pump();
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(h.registerInvoked, 1);
  });

  testWidgets('登记失败:弹层不关、字段原地、软红整块说原文;重试续走', (
    WidgetTester t,
  ) async {
    final h = _Harness();
    // 桩上的错误 = 服务端原话挡回来。
    h.api.registerError = const PublisherIdentityException(
      '实名信息已登记,如需变更请联系平台客服',
    );
    await _show(t, h);
    await _fill(t);

    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();

    expect(h.registerInvoked, 1);
    expect(find.byKey(const Key('identity-error')), findsOneWidget,
        reason: '报错用软红整块(cy-inline-error),不给输入框描红边');
    expect(find.text('实名信息已登记,如需变更请联系平台客服'), findsOneWidget);
    expect(find.byKey(continueBtn), findsOneWidget, reason: '弹层不关');
    expect(
      find.byKey(const ValueKey<String>('identity-id-card')),
      findsOneWidget,
      reason: '失败时字段原地保留让用户改',
    );

    h.api.registerError = null; // 同证同人,服务端幂等放行
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(h.registerInvoked, 2);
    expect(find.byKey(const ValueKey<String>('identity-id-card')),
        findsNothing);
  });

  testWidgets('无实名参数(旧调用形)不受影响:直接放行', (
    WidgetTester t,
  ) async {
    await _show(t, null);
    expect(find.text('发布者实名已登记'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('identity-real-name')),
      findsNothing,
    );
    await t.tap(find.byKey(continueBtn));
    await t.pumpAndSettle();
    expect(find.byKey(continueBtn), findsNothing, reason: '弹层已 pop');
  });
}
