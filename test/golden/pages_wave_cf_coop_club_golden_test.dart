// Wave-C/F 合作邀约详情(C52a 收到 / C52b 发出)、俱乐部核销详情
// (F60/F61 两条记录 / F62 取不到记录)、附近商家定位被拒(C56)。
//
// 每条对小程序 shot-matrix 的 state:
//   · C52a/C52b 是**同一页的两侧**:收到的(canHandle)与发出的(等对方),
//     按钮组完全不同,只拍一侧验不出另一侧。
//   · F60/F61 用同一个 provider 的两个 key(registrationId 1/2)——
//     核销详情按单号取,不是全局单例。
//   · F62 缺记录:App 没有独立「空」分支,取不到就走加载失败态(照实拍,
//     不为了对齐小程序的空态去伪造一个 App 里不存在的画面)。
//   · C56 是**定位被拒**态(不是普通网络错):文案要指向「去设置」,
//     混成网络错等于让用户反复重试一件永远不会成功的事。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_cf_coop_club_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_crm.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/feature/club/club_checkin_detail_page.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/coop/coop_invite_detail_page.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';

import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home, {ThemeData? theme}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: theme ?? goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String goldenPath) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

CoopInviteRow _row({required int id, required int status, String? reason}) =>
    CoopInviteRow(
      id: id,
      inviteType: 0,
      fromId: 9,
      toType: 'merchant',
      toId: 3,
      topicId: 9,
      status: status,
      message: '外滩那场我这边能配合。',
      handleReason: reason,
      shareMode: 1,
      shareRate: 12,
      partnerName: '外滩补给站',
      partnerLeaderName: '林野',
      partnerPhone: '138****0000',
      createTime: '2026-08-01 10:00:00',
    );

ClubCheckinDetail _checkin({
  required int registrationId,
  required String name,
  required String statusCode,
  required String statusText,
}) => ClubCheckinDetail(
  registrationId: registrationId,
  displayName: name,
  avatar: '',
  phoneText: '138****0000',
  phoneVisible: true,
  sessionTimeText: '8月24日 19:30',
  statusCode: statusCode,
  statusText: statusText,
  statusTimeText: '2026-08-24 19:42',
  topicName: '外滩夜行档案',
  topicCover: '',
  orderNo: 'CY20260824001',
  ticketText: '标准票 × 1',
  orderTimeText: '2026-08-20 12:00',
  paidAmountText: '¥68.00',
  verifyTimeText: '2026-08-24 19:42',
  storeName: '外滩补给站',
  operatorName: '林野',
  railStep: 3,
  canRefund: true,
);

void main() {
  testWidgets('C52a 协作邀约详情:收到的一侧(待处理)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          coopInviteDetailProvider(
            const CoopInviteDetailKey(inviteId: 1, sent: false),
          ).overrideWith(
            (Ref ref) async =>
                CoopInviteDetail(row: _row(id: 1, status: 0)),
          ),
        ],
        const CoopInviteDetailPage(inviteId: '1', box: 'received'),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('来自'), findsWidgets);
    await _shot(tester, 'goldens/page_coop_invite_detail_received.png');
  });

  testWidgets('C52b 协作邀约详情:发出的一侧(对方已拒)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          coopInviteDetailProvider(
            const CoopInviteDetailKey(inviteId: 2, sent: true),
          ).overrideWith(
            (Ref ref) async => CoopInviteDetail(
              row: _row(id: 2, status: 2, reason: '这段时间人手排不开'),
            ),
          ),
        ],
        const CoopInviteDetailPage(inviteId: '2', box: 'sent'),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这段时间人手排不开'), findsWidgets);
    await _shot(tester, 'goldens/page_coop_invite_detail_sent.png');
  });

  testWidgets('F60 核销详情:已核销单', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        clubCheckinDetailProvider((clubId: 1, registrationId: 1)).overrideWith(
          (Ref ref) async => _checkin(
            registrationId: 1,
            name: '周行',
            statusCode: 'VERIFIED',
            statusText: '已核销',
          ),
        ),
      ], const ClubCheckinDetailPage(clubId: 1, registrationId: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('周行'), findsWidgets);
    await _shot(tester, 'goldens/page_club_checkin_detail_verified.png');
  });

  testWidgets('F61 核销详情:待核销单', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        clubCheckinDetailProvider((clubId: 1, registrationId: 2)).overrideWith(
          (Ref ref) async => _checkin(
            registrationId: 2,
            name: '林野',
            statusCode: 'PENDING',
            statusText: '待核销',
          ),
        ),
      ], const ClubCheckinDetailPage(clubId: 1, registrationId: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('林野'), findsWidgets);
    await _shot(tester, 'goldens/page_club_checkin_detail_pending.png');
  });

  testWidgets('F62 核销详情:取不到这条记录', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        clubCheckinDetailProvider((clubId: 1, registrationId: 3)).overrideWith(
          (Ref ref) async => throw Exception('这条核销记录不存在'),
        ),
      ], const ClubCheckinDetailPage(clubId: 1, registrationId: 3)),
    );
    await tester.pumpAndSettle();
    expect(find.text('核销凭证没加载出来'), findsOneWidget);
    await _shot(tester, 'goldens/page_club_checkin_detail_missing.png');
  });

  testWidgets('C56 附近商家:定位被拒', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          nearbyMerchantsProvider.overrideWith(
            (Ref ref) async => throw const MapLocationException(
              '定位没打开，漫游看不到你在哪',
              canOpenSettings: true,
            ),
          ),
        ],
        const NearbyMerchantsPage(),
        theme: merchantGoldenTheme(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('需要定位才能找附近商家'), findsOneWidget);
    await _shot(tester, 'goldens/page_coop_nearby_permission.png');
  });
}
