// 入驻状态闭环(缺口盘点 2608/2618/2620 · Top5)。
//
// ★ 小程序进页先问「这个账号名下有没有已提交的申请」(`checkExisting`),
//   App 以前直接画四步向导 —— 于是:
//   · 提交过的商家再进这一页,看到的是空白表单,交第二份被后端拒,
//     报错「已提交过商家入驻申请」他看不懂(那条错误本来就不该出现);
//   · 驳回的申请没有出口:`MerchantApplyForm.id` 全仓**没有一处赋值**,
//     后端 update 分支永远走不到,商家只能干看着驳回原因。
// 这里锁的就是这两件事:状态页三态齐 + 驳回能重提且**带着原 id** 提交。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_application.dart';
import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:flutter/cupertino.dart';

import '../../support/fake_publisher_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeApi implements MerchantApi {
  _FakeApi({this.submitError});

  MerchantApplyForm? submitted;
  final Object? submitError;

  @override
  Future<void> submitApply(MerchantApplyForm form) async {
    if (submitError != null) throw submitError!;
    submitted = form;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const Key _actionKey = Key('merchant-apply-status-action');

/// 一条被驳回、四步都能直接走完的申请行(营业执照已回填 ⇒ 不必真传图)。
const MerchantApplication _reusable = MerchantApplication(
  id: 7,
  status: 2,
  accountStatus: 0,
  name: '河畔咖啡',
  preference: '餐饮',
  phone: '13800138000',
  address: '上海市静安区某路 1 号',
  businessTime: '周一至周日 10:00-22:00',
  description: '手冲与烘焙',
  businessLicense: 'https://cdn.example/license.png',
  rejectReason: '营业执照模糊，请重新上传',
  createTime: '2026-09-18 10:12:00',
);

Future<void> _pump(
  WidgetTester tester,
  MerchantApplication? application,
  _FakeApi api,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        merchantApplicationProvider.overrideWith((_) async {
          // null 在这里代表「问不出结论」(网络失败),不是「没有申请」——
          // 后者由 overrideWith((_) async => null) 那条用例单独锁。
          if (application == null) {
            throw MerchantApiException('网络连接失败，请检查网络后重新检查');
          }
          return application;
        }),
        merchantApiProvider.overrideWithValue(api),
        // 本页第 4 步多了实名闸(RUN-52):这里给一台「按未登记回答」的桩,
        // 由 _walkAndSubmit 当场把三格填掉 —— 与真人走一遍的时序一致。
        publisherIdentityApiProvider.overrideWithValue(
          FakePublisherIdentityApi(),
        ),
      ].cast(),
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/merchant/apply',
          routes: <RouteBase>[
            GoRoute(
              path: '/merchant/apply',
              builder: (_, _) => const MerchantApplyPage(),
            ),
            GoRoute(path: '/', builder: (_, _) => const Text('会员中心')),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, Key key) => tester
    .widget<CupertinoTextField>(find.byKey(key))
    .controller!
    .text;

/// 从第一步一路点「继续」到预览页,补上发布者实名三格,再点「提交」。
Future<void> _walkAndSubmit(WidgetTester tester) async {
  for (int step = 1; step < 4; step++) {
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
  }
  expect(find.text('入驻申请 · 预览确认'), findsOneWidget);
  await tester.enterText(
    find.byKey(const ValueKey<String>('identity-real-name')),
    '陈晨',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('identity-id-card')),
    '99000019491231019X',
  );
  await tester.tap(find.byKey(const Key('identity-consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('merchant-apply-next')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('查不出结论时**不给表单** —— 放行就等于放商家去交重复申请', (
    WidgetTester tester,
  ) async {
    await _pump(tester, null, _FakeApi());

    expect(find.text('暂时无法确认申请状态'), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.text('店铺名称'), findsNothing);
  });

  testWidgets('审核中:说清在等谁,且**没有**「重新申请」(重提会被后端拒)', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const MerchantApplication(
        id: 7,
        status: 0,
        accountStatus: 0,
        name: '河畔咖啡',
        createTime: '2026-09-18 10:12:00',
      ),
      _FakeApi(),
    );

    expect(find.text('审核中'), findsOneWidget);
    expect(
      find.text('我们正在审核你的资料，预计 1-3 个工作日内完成。'),
      findsOneWidget,
    );
    expect(find.text('2026-09-18 10:12:00'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('重新申请'), findsNothing);
  });

  testWidgets('★ 驳回:后端原话当原因,「重新申请」回填资料并重提时带原 id', (
    WidgetTester tester,
  ) async {
    final _FakeApi api = _FakeApi();
    await _pump(tester, _reusable, api);

    expect(find.text('已驳回'), findsOneWidget);
    expect(
      find.text('本次申请未通过。营业执照模糊，请重新上传'),
      findsOneWidget,
      reason: '驳回原因用后端原话(reson),不自己编',
    );

    await tester.tap(find.byKey(_actionKey));
    await tester.pumpAndSettle();

    // 落回第一步,资料全部回填 —— 商家不必从零再填一遍。
    expect(find.text('入驻申请 · 基础信息'), findsOneWidget);
    expect(_fieldText(tester, const Key('merchant-apply-name')), '河畔咖啡');
    expect(_fieldText(tester, const Key('merchant-apply-phone')), '13800138000');

    await _walkAndSubmit(tester);

    // ★ 这一条就是全仓原先缺的那次赋值:没有 id,后端只会新建第二条申请。
    expect(api.submitted?.id, 7);
    expect(api.submitted?.name, '河畔咖啡');
  });

  testWidgets('待启用:审核过了但身份条件没齐 —— 中性态,不是驳回也不是生效', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const MerchantApplication(id: 8, status: 1, accountStatus: 0, name: '河畔咖啡'),
      _FakeApi(),
    );

    expect(find.text('待启用'), findsOneWidget);
    expect(
      find.text('资料审核已通过；完成主理人移交等身份条件后，商家账号才会生效。'),
      findsOneWidget,
    );
    expect(find.text('重新申请'), findsNothing);
  });

  testWidgets('已生效:不再给申请入口,只给「返回」', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const MerchantApplication(id: 1, status: 1, accountStatus: 1, name: '河畔咖啡'),
      _FakeApi(),
    );

    expect(find.text('已生效'), findsNWidgets(2));
    expect(
      find.text('商家身份已生效，可以进入商家中心使用经营功能。'),
      findsOneWidget,
    );
    expect(find.text('重新申请'), findsNothing);
  });

  testWidgets('★ 停用:停用原因用 disableReason,绝不冒充驳回原因', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const MerchantApplication(
        id: 9,
        status: 2,
        accountStatus: 2,
        name: '河畔咖啡',
        rejectReason: '营业执照模糊，请重新上传',
        disableReason: '涉嫌虚假核销',
      ),
      _FakeApi(),
    );

    // 状态签与时间线末节点各说一次(真源 statusLabel / timelineText 同值)。
    expect(find.text('账号已停用'), findsNWidgets(2));
    expect(
      find.text(
        '商家账号已停用，经营功能暂不可用。停用原因：涉嫌虚假核销。请等待平台复核。',
      ),
      findsOneWidget,
    );
    // 停用压过驳回:即使 status==2 也不给重提入口。
    expect(find.text('重新申请'), findsNothing);
    expect(find.textContaining('营业执照模糊'), findsNothing);
  });

  testWidgets('撞上「已是俱乐部主理人」:整页拦下,不是 toast 让用户再试', (
    WidgetTester tester,
  ) async {
    final _FakeApi api = _FakeApi(
      submitError: MerchantApiException('您已是俱乐部主理人，无法申请商家入驻'),
    );
    await _pump(tester, _reusable, api);

    await tester.tap(find.byKey(_actionKey));
    await tester.pumpAndSettle();
    await _walkAndSubmit(tester);

    expect(find.text('无法申请入驻'), findsOneWidget);
    expect(find.text('您已是俱乐部主理人，无法申请商家入驻'), findsOneWidget);
  });
}
