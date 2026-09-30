// 岗位权限显隐(缺口盘点 Top2)。
//
// ★★ `/api/merchant/access/me` 是唯一的权限真源,App 以前**一个位都没读**:
//   四个区块对核销员/运营/财务一律照摆,点进去吃 403 才看见一句「加载失败」。
//   后端 `dashboard`/`todo-summary`/`events` 三个接口是 **requireOwnerOnly** ——
//   权限位为真也不等于能请求(财务岗就是活样本:canReadFinance 真、非店主、照样 403)。
//   所以这一页的根换成 access/me,并且**不是店主就连请求都不发**
//   (真源 index.js 同一判据:`roleCode === 'MERCHANT_OWNER'` 才去要)。
//
// 这里锁三件事:①四块按岗位收放 ②非店主不发 owner-only 请求 ③无权限页说人话。

import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../golden/golden_theme.dart' show merchantGoldenTheme;
import 'merchant_access_fixtures.dart';

/// owner-only 三个接口的**请求计数器** —— 断言「没发」比断言「没画」更硬。
class _Spy {
  int dashboard = 0;
  int todo = 0;
  int events = 0;
}

List<dynamic> _workbenchOverrides(MerchantAccess access, _Spy spy) =>
    <dynamic>[
      merchantAccessProvider.overrideWith((ref) async => access),
      merchantDashboardProvider.overrideWith((ref) async {
        spy.dashboard++;
        return MerchantDashboard.fromJson(<String, dynamic>{
          'revenue': '12840.00',
        });
      }),
      merchantTodoProvider.overrideWith((ref) async {
        spy.todo++;
        return MerchantTodo.fromJson(<String, dynamic>{});
      }),
      merchantEventsProvider.overrideWith((ref) async {
        spy.events++;
        return <Map<String, dynamic>>[
          <String, dynamic>{'content': '静安咖啡 核销 1 张', 'time': '10:24'},
        ];
      }),
      businessStatusProvider.overrideWith(
        (ref) async => (open: true, text: '营业中'),
      ),
      merchantUnreadProvider.overrideWith((ref) async => 0),
    ];

Future<void> _pumpWorkbench(
  WidgetTester tester,
  MerchantAccess access,
  _Spy spy,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: _workbenchOverrides(access, spy).cast(),
      child: MaterialApp(
        theme: merchantGoldenTheme(),
        home: const MerchantHomePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const List<String> _ownerOnlyBlocks = <String>[
  '累计收入',
  '待办',
  '项目',
  '最新动态',
];

void main() {
  testWidgets('店主:四块都在', (WidgetTester tester) async {
    await _pumpWorkbench(tester, ownerAccess(), _Spy());

    for (final String anchor in _ownerOnlyBlocks) {
      expect(find.text(anchor), findsWidgets, reason: anchor);
    }
  });

  testWidgets('★ 核销员:四块一律不在,而且**一个 owner-only 请求都不发**', (
    WidgetTester tester,
  ) async {
    final _Spy spy = _Spy();
    await _pumpWorkbench(tester, checkinAccess(), spy);

    for (final String anchor in _ownerOnlyBlocks) {
      expect(find.text(anchor), findsNothing, reason: anchor);
    }
    expect(spy.dashboard, 0, reason: 'dashboard 在后端是 requireOwnerOnly');
    expect(spy.todo, 0);
    expect(spy.events, 0);

    // 不是把整页挡死 —— 他岗位有的能力照常给。
    expect(find.text('扫码核销'), findsOneWidget);
    expect(find.text('财务'), findsNothing, reason: '没有 finance:read');
    expect(find.text('店铺装修'), findsNothing, reason: '没有 profile:write');
  });

  testWidgets('★ 财务岗:有 finance:read 也**不能**请求 owner-only 的 dashboard', (
    WidgetTester tester,
  ) async {
    final _Spy spy = _Spy();
    await _pumpWorkbench(tester, financeAccess(), spy);

    expect(spy.dashboard, 0, reason: '权限位为真 ≠ 身份是店主,发出去就是 403');
    expect(find.text('累计收入'), findsNothing);
    // 财务入口本身按权限位给 —— 台账页读的是财务自己的接口。
    expect(find.text('财务'), findsOneWidget);
  });

  testWidgets('运营岗:没有 finance:read 就没有财务入口', (
    WidgetTester tester,
  ) async {
    final _Spy spy = _Spy();
    await _pumpWorkbench(tester, marketingAccess(), spy);

    expect(find.text('财务'), findsNothing);
    expect(spy.dashboard, 0);
  });

  testWidgets('★ 营销页:无权限不是故障 —— 说清缺哪项、出路是找店主、按钮是重新确认', (
    WidgetTester tester,
  ) async {
    final _MarketingSpy api = _MarketingSpy();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantAccessProvider.overrideWith((ref) async => checkinAccess()),
          merchantApiProvider.overrideWithValue(api),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantMarketingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的岗位还没有营销数据权限'), findsOneWidget);
    expect(find.text('请联系店主开通'), findsOneWidget);
    expect(find.text('重新确认'), findsOneWidget);
    // 前端闸:权限没确认过就连那一枪都不发(真源 #817 同口径)。
    expect(api.calls, 0);
  });

  testWidgets('运营岗进营销页:数据照常渲染', (WidgetTester tester) async {
    final _MarketingSpy api = _MarketingSpy();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          merchantAccessProvider.overrideWith((ref) async => marketingAccess()),
          merchantApiProvider.overrideWithValue(api),
        ].cast(),
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          home: const MerchantMarketingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(find.text('你的岗位还没有营销数据权限'), findsNothing);
  });
}

class _MarketingSpy implements MerchantApi {
  int calls = 0;

  @override
  Future<MerchantMarketing> marketingHome() async {
    calls++;
    return MerchantMarketing.fromJson(<String, dynamic>{});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
