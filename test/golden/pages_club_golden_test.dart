// 俱乐部管理各页的整页视觉快照。
//
// 快照一律走 goldenTheme()(按钮字族替换成测试环境有中文字形的那个),
// 数据全部 override 成固定假数据,不打网络。团码页的二维码用 code 回落
// (qrcodeUrl 空 → 等宽码文本),确定性渲染、不碰网络图。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_club_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_dissolution_blockers_page.dart';
import 'package:chengyin_app/feature/club/club_edit_page.dart';
import 'package:chengyin_app/feature/club/club_edition_report_page.dart';
import 'package:chengyin_app/feature/club/club_enroll_page.dart';
import 'package:chengyin_app/feature/club/club_group_code_page.dart';
import 'package:chengyin_app/feature/club/club_join_requests_page.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() => DioClient(TokenStore(const FlutterSecureStorage()));

class _FakeGroupCodeApi extends GroupCodeApi {
  _FakeGroupCodeApi() : super(_dummyDioClient());

  @override
  Future<GroupCodeIssue> issue(int activityId) async {
    return GroupCodeIssue(
      qrcodeUrl: '',
      code: 'KX-2026-08-19-01',
      ttlMs: 5000,
    );
  }
}

Club _ownerClub() => Club(
  id: 1,
  name: '城西探店社',
  logo: '',
  cover: '',
  description: '专注城市街区的探店路线,每期一个街区主题。',
  city: '上海',
  clubType: '旅行组织',
  activityPrefs: const <String>['轻社交', '城市定向'],
  keywords: '探店,街区',
  style: '轻松 + 深度',
  memberCount: 12,
  isOwner: true,
  joinPolicySupported: true,
  joinPolicy: 1,
  prioritySignupEnabled: true,
  memberReservedQuota: 5,
  nonOwnerMemberCount: 2,
  leaderName: '陈晨',
  pendingJoinRequestCount: 2,
);

void main() {
  testWidgets('报名名册(主理人视角)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          clubDetailProvider(1).overrideWith(
            (ref) async => _ownerClub(),
          ),
          clubTopicsProvider(1).overrideWith(
            (ref) async => <ClubTopic>[
              ClubTopic(
                id: 10,
                name: '静安第一期',
                signupCount: 8,
                startDate: '2026-08-24 14:00',
              ),
              ClubTopic(
                id: 11,
                name: '一个特别特别长的团名用来检验两行截断是否正确显示省略号',
                signupCount: 3,
                startDate: '2026-09-01 10:00',
              ),
            ],
          ),
          clubMembersProvider(1).overrideWith(
            (ref) async => <ClubMember>[],
          ),
        ],
        const ClubEnrollPage(clubId: 1, clubName: '城西探店社'),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_enroll.png'),
    );
  });

  testWidgets('入会申请列表', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          clubJoinRequestsProvider(1).overrideWith(
            (ref) async => <JoinRequest>[
              JoinRequest(
                memberId: 11,
                nickname: '小明',
                joinTime: '2026-08-19T10:20:00',
              ),
              JoinRequest(
                memberId: 12,
                nickname: '一个昵称特别特别长的人用来检验截断是否正确显示省略号',
                joinTime: '2026-08-19T09:05:00',
              ),
            ],
          ),
        ],
        const ClubJoinRequestsPage(clubId: 1),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_join_requests.png'),
    );
  });

  testWidgets('解散前待处理(有阻断)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          clubDissolutionBlockersProvider(1).overrideWith(
            (ref) async => DissolutionBlockers(
              deposits: <ClubDeposit>[
                ClubDeposit(
                  id: 501,
                  depositStatus: 2,
                  amount: 1000,
                  topicId: 10,
                  retryable: true,
                ),
                ClubDeposit(
                  id: 502,
                  depositStatus: 5,
                  amount: 500,
                  topicId: 11,
                ),
              ],
              settlements: <ClubSettlement>[
                ClubSettlement(id: 601, direction: 'outgoing', amount: 88, topicId: 10),
                ClubSettlement(id: 602, direction: 'incoming', amount: 199, topicId: 12),
              ],
            ),
          ),
        ],
        const ClubDissolutionBlockersPage(clubId: 1),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_dissolution_blockers.png'),
    );
  });

  testWidgets('探店日工时与证据(已选期次)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 900));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          clubEditionsProvider(1).overrideWith(
            (ref) async => <EditionOption>[
              EditionOption(id: 10, label: '静安第一期（2026-08-24）'),
              EditionOption(id: 12, label: '徐汇第二期（2026-09-06）'),
              EditionOption(id: 13, label: '普陀第三期（2026-09-20）'),
            ],
          ),
        ],
        const ClubEditionReportPage(clubId: 1),
      ),
    );
    await tester.pumpAndSettle();
    // 期次下拉用 initialValue 需要 frame 就位。
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_edition_report.png'),
    );
  });

  testWidgets('编辑俱乐部(加载完成的表单)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 1100));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          clubDetailProvider(1).overrideWith(
            (ref) async => _ownerClub(),
          ),
        ],
        const ClubEditPage(clubId: 1),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_edit.png'),
    );
  });

  testWidgets('团核销码(出码完成态)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          groupCodeApiProvider.overrideWithValue(_FakeGroupCodeApi()),
        ],
        const ClubGroupCodePage(
          activityId: 77,
          activityName: '静安第一期',
        ),
      ),
    );
    // 周期倒计时 timer 会让 pumpAndSettle 永远不静,这里手动推进固定帧。
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_page_group_code.png'),
    );
    // 销毁页面释放周期 Timer。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
