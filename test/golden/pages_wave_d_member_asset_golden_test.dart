// Wave-D 我的参与 / 邀请记录 / 收益明细 / 他人主页。
//
// 每条对小程序 shot-matrix 的 state:
//   · D08 参与记录常态 / D09 空 / D10 失败态 —— 三态同页三图,空与错不能混。
//   · D23 邀请记录(sheet 式记录页,rewardReady=true 才有「已到账」的底气)/
//     D24 加载失败要给可重试错误,不许误报为空。
//   · D28 收益明细「全部」/ D29 换「创作收益」筛选 —— 换筛选就是换 family key,
//     只拍一张验不出筛选轴。
//   · A42 他人主页:关注/粉丝/获赞都在,证明不是自己的主页。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_d_member_asset_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/balance_detail.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/account/income_detail_page.dart';
import 'package:chengyin_app/feature/account/invite_history_logic.dart';
import 'package:chengyin_app/feature/account/invite_history_page.dart';
import 'package:chengyin_app/feature/participation/participation_api.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:chengyin_app/feature/participation/participation_page.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';

import 'golden_theme.dart';
import '../support/fixed_auth.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: <dynamic>[signedInAuthOverride(), ...overrides].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String goldenPath) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

final ParticipationRecord _record = ParticipationRecord(
  id: 1,
  ownerType: 1,
  ownerId: 11,
  sourceName: '城市夜行 · 建筑线索',
  coverUrl: '',
  address: '外滩观景平台',
  dateText: '08.01 – 08.31',
  typeLabel: '城市定向',
  state: ParticipationState.inProgress,
);

final InviteHistoryState _invites = InviteHistoryState(
  groups: const <InviteGroup>[
    InviteGroup('时间待同步', <InviteRow>[
      InviteRow(
        id: 1,
        name: '周行',
        timeText: '邀请时间待同步',
        statusText: '首购奖励已到账 · 8月7日 10:30',
        rewardText: '+10 积分',
      ),
      InviteRow(
        id: 2,
        name: '林野',
        timeText: '邀请时间待同步',
        statusText: '已加入 · 首购待完成',
        rewardText: '待解锁',
      ),
    ], '+10 积分'),
  ],
  total: 2,
  rewardReady: true,
  earnedTotal: 10,
);

const List<BalanceDetail> _incomeRows = <BalanceDetail>[
  BalanceDetail(
    id: 1,
    eventType: 1,
    changeReason: '路线发布收益',
    changeBalance: '128.00',
    changeType: 1,
    createTime: '2026-08-01 10:00:00',
  ),
  BalanceDetail(
    id: 2,
    eventType: 3,
    changeReason: '提现申请',
    changeBalance: '50.00',
    changeType: 2,
    createTime: '2026-08-01 11:00:00',
  ),
];

void main() {
  testWidgets('D08 我的参与:常态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        participationRecordsProvider.overrideWith(
          (Ref ref) async => <ParticipationRecord>[_record],
        ),
      ], const ParticipationPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('城市夜行 · 建筑线索'), findsOneWidget);
    await _shot(tester, 'goldens/page_participation_normal.png');
  });

  testWidgets('D09 我的参与:空态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        participationRecordsProvider.overrideWith(
          (Ref ref) async => const <ParticipationRecord>[],
        ),
      ], const ParticipationPage()),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'goldens/page_participation_empty.png');
  });

  testWidgets('D10 我的参与:失败态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        participationRecordsProvider.overrideWith(
          (Ref ref) async => throw Exception('网络连接失败'),
        ),
      ], const ParticipationPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('参与记录没能打开'), findsOneWidget);
    await _shot(tester, 'goldens/page_participation_error.png');
  });

  testWidgets('D23 邀请记录:常态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        inviteHistoryProvider.overrideWith((Ref ref) async => _invites),
      ], const InviteHistoryPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('周行'), findsOneWidget);
    await _shot(tester, 'goldens/page_invite_history.png');
  });

  testWidgets('D24 邀请记录:失败态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        inviteHistoryProvider.overrideWith(
          (Ref ref) async => throw Exception('网络连接失败'),
        ),
      ], const InviteHistoryPage()),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'goldens/page_invite_history_error.png');
  });

  testWidgets('D28 收益明细:全部', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        incomeDetailProvider(
          IncomeEventFilter.all,
        ).overrideWith((Ref ref) async => _incomeRows),
        incomeDetailProvider(
          IncomeEventFilter.create,
        ).overrideWith((Ref ref) async => _incomeRows.take(1).toList()),
      ], const IncomeDetailPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('路线发布收益'), findsOneWidget);
    await _shot(tester, 'goldens/page_income_detail_all.png');
  });

  testWidgets('D29 收益明细:创作收益筛选', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        incomeDetailProvider(
          IncomeEventFilter.all,
        ).overrideWith((Ref ref) async => _incomeRows),
        incomeDetailProvider(
          IncomeEventFilter.create,
        ).overrideWith((Ref ref) async => _incomeRows.take(1).toList()),
      ], const IncomeDetailPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创作收益'));
    await tester.pumpAndSettle();
    expect(find.text('提现申请'), findsNothing);
    await _shot(tester, 'goldens/page_income_detail_create.png');
  });

  testWidgets('A42 他人主页:常态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 1000));
    await tester.pumpWidget(
      _app(<dynamic>[
        otherProfileProvider(2).overrideWith(
          (Ref ref) async => ProfileDetail(
            id: 2,
            nickname: '城市漫游者',
            avatar: '',
            introduction: '把走过的地方做成别人也能走的路线。',
            levelId: 5,
            point: 320,
            followNum: 12,
            fansNum: 34,
            likeNum: 208,
            topicNum: 6,
            activityNum: 9,
          ),
        ),
        otherPostsProvider(
          2,
        ).overrideWith((Ref ref) async => const <SquarePost>[]),
      ], const UserProfilePage(memberId: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('城市漫游者'), findsWidgets);
    await _shot(tester, 'goldens/page_user_profile_other.png');
  });
}
