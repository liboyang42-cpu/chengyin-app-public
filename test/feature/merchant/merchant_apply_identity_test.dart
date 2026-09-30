// 商家入驻(第 4 步·预览确认)× 发布者实名 —— 三入口接线之二。
//
// 钉住真源 pages/merchant/apply/index.js 的形态:
// · 进第 4 屏才查一次状态,已登记收起字段;
// · 「提交」的亮灭由经营者实名三项闸着(规则只有 publisher_identity.dart 一份);
// · 提交时序 = 先 /api/publisher/identity、后 merchant_registration,
//   入驻单里永不含 realName/idCard(隐私红线 + 服务端闸);
// · 登记失败 → 入驻单不发,「申请暂未提交」错误条原地并可「重新提交」。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_application.dart';
import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_publisher_identity.dart';

/// 商家 + 实名两台桩挂在同一条调用时序上:登记那发没过,入驻单永发不出去。
class _OrderedApis {
  _OrderedApis({this.identityRegistered = false});

  final FakePublisherIdentityApi identity = FakePublisherIdentityApi();
  final List<String> calls = <String>[];
  MerchantApplyForm? submitted;
  Object? submitError;

  late final MerchantApi merchant = _FakeMerchantApi(this);

  late final PublisherIdentityApi publisher = _FakePublisher(this);

  final bool identityRegistered;

  Future<MerchantApplication?> application() => Future.value(_reusable);
}

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi(this._o);
  final _OrderedApis _o;

  @override
  Future<void> submitApply(MerchantApplyForm form) async {
    _o.calls.add('merchant');
    if (_o.submitError != null) throw _o.submitError!;
    _o.submitted = form;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePublisher extends PublisherIdentityApi {
  _FakePublisher(this._o) : super(dummyDioClient());
  final _OrderedApis _o;

  @override
  Future<bool> status() async {
    _o.calls.add('status');
    return _o.identity.registered || _o.identityRegistered;
  }

  @override
  Future<void> register({
    required String realName,
    required String idCard,
    required bool consent,
    required String source,
  }) async {
    _o.calls.add('identity');
    await _o.identity.register(
      realName: realName,
      idCard: idCard,
      consent: consent,
      source: source,
    );
  }
}

/// 一条资料齐全、只是被驳回的申请:走「重新申请」回填,免得真传营业执照。
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

Future<_OrderedApis> _pumpReapply(WidgetTester tester, {
  bool identityRegistered = false,
  Object? submitError,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final o = _OrderedApis(identityRegistered: identityRegistered)
    ..submitError = submitError;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        merchantApplicationProvider.overrideWith((_) async => _reusable),
        merchantApiProvider.overrideWithValue(o.merchant),
        publisherIdentityApiProvider.overrideWithValue(o.publisher),
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
  await tester.tap(find.text('重新申请'));
  await tester.pumpAndSettle();
  return o;
}

/// 前三步资料已回填,连点三个「继续」落到第 4 屏。
Future<void> _toStep4(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pumpAndSettle();
  }
  expect(find.text('入驻申请 · 预览确认'), findsOneWidget);
}

// 第 4 步的「提交」与前三步的「继续」是同一个键(禁用=onPressed null)。
Finder _submitBtn() => find.byKey(const Key('merchant-apply-next'));

Future<void> _fillIdentity(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('identity-real-name')),
  );
  await tester.pumpAndSettle();
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
}

void main() {
  testWidgets('进第 4 屏才查状态;已登记的人收起字段、只回一句状态', (
    WidgetTester tester,
  ) async {
    final o = await _pumpReapply(tester, identityRegistered: true);
    // 前三屏不该多发这一发查询。
    expect(o.calls, isEmpty);
    await _toStep4(tester);
    expect(o.calls, <String>['status']);

    expect(
      find.text('已登记。如需变更实名信息，请联系平台客服。'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('identity-real-name')),
      findsNothing,
    );

    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();
    expect(o.calls, <String>['status', 'merchant'],
        reason: '已登记 → 不再发登记,直接落入驻单');
    expect(o.submitted, isNotNull);
  });

  testWidgets('未登记:三项不齐「提交」不亮;差什么按实名顺序说什么', (
    WidgetTester tester,
  ) async {
    final o = await _pumpReapply(tester);
    await _toStep4(tester);

    expect(
      find.byKey(const ValueKey<String>('identity-real-name')),
      findsOneWidget,
    );
    final disabled = tester.widget<CupertinoButton>(_submitBtn());
    expect(disabled.onPressed, isNull, reason: '空实名不能提交');

    await tester.enterText(
      find.byKey(const ValueKey<String>('identity-real-name')),
      '陈晨',
    );
    await tester.pump();
    expect(
      tester.widget<CupertinoButton>(_submitBtn()).onPressed, isNull,
      reason: '还差证件与同意,报的是顺序里的下一条',
    );

    await _fillIdentity(tester);
    expect(tester.widget<CupertinoButton>(_submitBtn()).onPressed, isNotNull);
    expect(o.calls, <String>['status'], reason: '填格不重复查状态');
  });

  testWidgets('提交时序:先 /api/publisher/identity、后 merchant_registration', (
    WidgetTester tester,
  ) async {
    final o = await _pumpReapply(tester);
    await _toStep4(tester);
    await _fillIdentity(tester);

    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();

    expect(o.calls, <String>['status', 'identity', 'merchant']);
    expect(o.identity.registerCalls, <Map<String, Object?>>[
      <String, Object?>{
        'realName': '陈晨',
        'idCard': '99000019491231019X',
        'consent': true,
        'source': 'merchant_apply',
      },
    ]);
    expect(o.submitted, isNotNull);
    // 值不再回显:登记成功当场收起。
    expect(
      find.byKey(const ValueKey<String>('identity-id-card')),
      findsNothing,
    );
  });

  testWidgets('登记失败:入驻单不发,「申请暂未提交」错误条原地、重新提交续走', (
    WidgetTester tester,
  ) async {
    final o = await _pumpReapply(tester);
    o.identity.registerError = const PublisherIdentityException(
      '实名信息已登记,如需变更请联系平台客服',
    );
    await _toStep4(tester);
    await _fillIdentity(tester);

    await tester.tap(_submitBtn());
    await tester.pumpAndSettle();

    expect(o.calls, <String>['status', 'identity']);
    expect(o.submitted, isNull, reason: '实名没过,入驻单绝不能跟着发出去');
    expect(
      find.byKey(const Key('merchant-apply-submit-error')),
      findsOneWidget,
    );
    expect(find.text('申请暂未提交'), findsOneWidget);
    expect(find.text('实名信息已登记,如需变更请联系平台客服'), findsOneWidget,
        reason: '错误条说接口原文');
    // 失败时字段原地保留让用户改(填写态,不是登记后的回显态)。
    expect(
      find.byKey(const ValueKey<String>('identity-id-card')),
      findsOneWidget,
    );

    o.identity.registerError = null; // 同证同人,服务端幂等放行
    await tester.tap(find.text('重新提交'));
    await tester.pumpAndSettle();
    expect(o.calls, <String>['status', 'identity', 'identity', 'merchant']);
    expect(o.submitted, isNotNull);
  });
}
