// account 域「加载 / 空 / 错」三态与真源对齐(2026-09-18 iOS 27 外观复核)。
//
// 每条断言都能对回一句真源,不是照着实现抄的:
//   · pages/address/address.wxml:13       加载态 = cy-skeleton type="list" count="4"
//   · pages/mylike/mylike.wxml:14         加载态 = cy-skeleton type="card" count="3"
//   · components/cy/scene-asset-income-detail/index.wxml
//                                         加载态 = cy-skeleton type="list" count="4";
//                                         空态是 cy-empty(**无重试**),重试只挂 cy-error
//   · subpackageA/pages/infomation/infomation.wxml:68-80
//                                         文档区三态 + 文案(此前失败/空是整块不渲染)
//   · pages/addressinfo/addressinfo.wxml:19-21
//                                         读回失败盖住表单,只留「重新加载」

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/data/models/balance_detail.dart';
import 'package:chengyin_app/data/models/infomation.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/account/income_detail_page.dart';
import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/account/play_guide_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';

import '../../support/fixed_auth.dart';

// 账号域带登录门的页面测「登录后的三态」要先声明已登录(否则先撞门)。
Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: <dynamic>[signedInAuthOverride(), ...overrides].cast(),
  child: MaterialApp(home: home),
);

/// 永不落地的 Future = 稳定停在 loading 态。
Future<T> _pending<T>() => Completer<T>().future;

class _FailingAddressApi extends Fake implements AddressApi {
  _FailingAddressApi(this.onInfoCall);
  final void Function() onInfoCall;

  @override
  Future<MemberAddress> info(int id) {
    onInfoCall();
    return Future<MemberAddress>.error(Exception('地址不可用'));
  }
}

class _PendingAddressApi extends Fake implements AddressApi {
  @override
  Future<MemberAddress> info(int id) => _pending<MemberAddress>();
}

class _SaveFailingAddressApi extends Fake implements AddressApi {
  @override
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    String? province,
    String? detailAddress,
    bool isDefault = false,
  }) => Future<void>.error(Exception('网络开小差了'));
}

void main() {
  /// 骨架**档位与条数**都要锁 —— 真源 list(头像+两行)与 card(封面卡)是
  /// 两种同构对象,渲染错档 = 加载完成时整块跳版(D4),和没骨架一样。
  void expectSkeleton(
    WidgetTester tester, {
    required CySkeletonType type,
    required int count,
  }) {
    final sk = tester.widget<CySkeleton>(find.byType(CySkeleton));
    expect(sk.type, type);
    expect(sk.count, count);
  }

  /// 玩法文档区在三种玩法卡之下,首屏外(ListView 懒加载)—— 先滚到再断言。
  Future<void> scrollToDocSection(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('参与人列表加载态是骨架,不是转圈', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        participantsProvider.overrideWith((_) => _pending<List<Participant>>()),
      ], const ParticipantsPage(liquidGlassSupported: false)),
    );
    await tester.pump();
    expect(find.byType(CySkeleton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // 真源 pages/address/address.wxml:13 = type="list" count="4"
    expectSkeleton(tester, type: CySkeletonType.list, count: 4);
  });

  testWidgets('我的收藏加载态是骨架,不是转圈', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        myLikesProvider.overrideWith((_) => _pending<List<Topic>>()),
      ], const MyLikesPage()),
    );
    await tester.pump();
    expect(find.byType(CySkeleton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // 真源 pages/mylike/mylike.wxml:14 = type="card" count="3"
    expectSkeleton(tester, type: CySkeletonType.card, count: 3);
  });

  testWidgets('收益明细:加载态是骨架,不是转圈', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        incomeDetailProvider.overrideWith(
          (_, _) => _pending<List<BalanceDetail>>(),
        ),
      ], const IncomeDetailPage()),
    );
    await tester.pump();
    expect(find.byType(CySkeleton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // 真源 scene-asset-income-detail/index.wxml = type="list" count="4"
    expectSkeleton(tester, type: CySkeletonType.list, count: 4);
  });

  testWidgets('玩法文档:加载态是 list 骨架(真源 infomation.wxml:68)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationsProvider.overrideWith((_) => _pending<List<Infomation>>()),
      ], const PlayGuidePage()),
    );
    await tester.pump();
    await scrollToDocSection(tester, find.byType(CySkeleton));
    expectSkeleton(tester, type: CySkeletonType.list, count: 2);
  });

  testWidgets('收益明细:入账绿/出账红(真源用户裁决),缺金额不吃红', (WidgetTester tester) async {
    BalanceDetail row(int id, String? amount, int? changeType) =>
        BalanceDetail.fromJson(<String, dynamic>{
          'id': id,
          'changeBalance': amount,
          'changeType': changeType,
        });
    await tester.pumpWidget(
      _app(<dynamic>[
        incomeDetailProvider.overrideWith(
          (_, _) async => <BalanceDetail>[
            row(1, '128.00', 1),
            row(2, '50.00', 2),
            row(3, '', 1),
          ],
        ),
      ], const IncomeDetailPage()),
    );
    await tester.pumpAndSettle();
    // scene-asset-income-detail/index.wxss:入账绿、出账红,走 status 语义 token。
    // 方向冗余(+/− 号与「收入/支出」文案)由 income_detail_test 锁着。
    Color amountColor(int id) {
      final Finder f = find.byKey(Key('income-amount-$id'));
      return tester.widget<Text>(f).style!.color!;
    }

    final CyPalette p = CyPalette.of(tester.element(find.text('收益明细')));
    expect(amountColor(1), p.statusSuccess);
    expect(amountColor(2), p.statusDanger);
    // 缺金额是「没有数」不是支出 —— 中性色,不能吃到红。
    expect(amountColor(3), p.textTertiary);
  });

  testWidgets('收益明细:空态不给「重试」这个假出口', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        incomeDetailProvider.overrideWith((_, _) async => <BalanceDetail>[]),
      ], const IncomeDetailPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无收益记录'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('玩法文档:失败态说清是什么没加载出来并给重试', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationsProvider.overrideWith((_) async => throw Exception('网络异常')),
      ], const PlayGuidePage()),
    );
    await tester.pumpAndSettle();
    await scrollToDocSection(tester, find.text('玩法文档没能加载出来'));
    expect(find.text('玩法文档没能加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('玩法文档:空态不再整块消失,文案逐字对齐真源', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationsProvider.overrideWith((_) async => const <Infomation>[]),
      ], const PlayGuidePage()),
    );
    await tester.pumpAndSettle();
    await scrollToDocSection(tester, find.text('暂无玩法说明'));
    expect(find.text('暂无玩法说明'), findsOneWidget);
    expect(find.text('内容上线后会出现在这里'), findsOneWidget);
  });

  testWidgets('读回参与人失败:不进表单(否则保存会清空旧地址),只给「重新加载」', (WidgetTester tester) async {
    int infoCalls = 0;
    await tester.pumpWidget(
      _app(<dynamic>[
        addressApiProvider.overrideWithValue(
          _FailingAddressApi(() => infoCalls++),
        ),
      ], const AddressEditPage(addressId: 7)),
    );
    await tester.pumpAndSettle();
    expect(find.text('参与人信息没能加载出来'), findsOneWidget);
    expect(find.text('保存参与人信息'), findsNothing);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(infoCalls, 2);
  });

  testWidgets('参与人编辑加载态 = form-section 骨架(真源 addressinfo.wxml:11),与表单同构', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        addressApiProvider.overrideWithValue(_PendingAddressApi()),
      ], const AddressEditPage(addressId: 7)),
    );
    await tester.pump();
    expectSkeleton(tester, type: CySkeletonType.formSection, count: 2);
  });

  testWidgets('保存失败:标题说清「什么没保存」+ 原话 + 「重试保存」(真源 cy-inline-error 三件套)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        addressApiProvider.overrideWithValue(_SaveFailingAddressApi()),
      ], const AddressEditPage()),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(CupertinoTextFormFieldRow);
    await tester.enterText(fields.at(0), '林野');
    await tester.enterText(fields.at(1), '13800008001');
    await tester.pump();
    await tester.tap(find.byKey(const Key('address-save-participant')));
    await tester.pumpAndSettle();
    expect(find.text('参与人信息没有保存'), findsOneWidget);
    expect(find.text('网络开小差了'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
  });
}
