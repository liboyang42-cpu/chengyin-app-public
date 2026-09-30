// 地图组队 P 方案纯函数(A9 卡片状态机 / errorCode 分支 / P6 三态)的门禁。
//
// ★ 判据全部来自小程序只读快照 master@90e66d70:
//     utils/map-team.js                      被测真源
//     tests/unit/map-team.test.js            纯函数契约(下面逐条对拍)
//     tests/unit/map-team-page-contract.test.js  页面接线契约
//   快照改了而这里没改 = 两边漂移,应当红。
//
// ★ 产品判据四条(线卡)在这里各有一条:
//     ① 满员 / 进行中 / 审核中 → apply 返回这些 errorCode 时**撤下队伍**
//        (地图上不再有申请入口);
//     ② 已满员的主按钮不该出现在列表上(服务器不会再下发;客户端只按快照);
//     ③ 24h / 活动结束失效 → PENDING 卡 foot 文案(真源 @a7d179760 起改为以
//        服务端 applyExpireTime 说真实剩余,见 team_apply_expire_contract_test)+ withdraw APPLY_NOT_PENDING
//        「这条申请已经处理或失效」+ 重拉;
//     ④ 被拒不能再申 → REJECTED 卡片**一个按钮都没有**。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/team_map.dart';

Map<String, dynamic> _base() => <String, dynamic>{
  'teamId': 7,
  'title': '外滩夜行',
  'activityId': 11,
  'activityName': '外滩夜行路线 · 周五 19:30 场',
  'topicId': 3,
  'topicName': '外滩夜行路线',
  'productType': 1,
  'addressName': '外滩源',
  'coordSource': 'GATHER',
  'latitude': 31.2,
  'longitude': 121.4,
  'distance': 600,
  'leaderName': '小周',
  'leaderAvatar': 'a.png',
  'joinedCount': 3,
  'maxMembers': 4,
  'memberAvatars': <String>['a.png', 'b.png'],
  'viewerStatus': 'NONE',
  'viewerHasTicket': false,
  'pendingCount': null,
};

void main() {
  test('卡片状态机:六个 mode 与快照逐条一致', () {
    expect(teamCardState(_base()).mode, 'buy');
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerHasTicket': true}).mode, 'apply');
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerStatus': 'PENDING'}).mode, 'pending');
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerStatus': 'LEADER'}).mode, 'leader');
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerStatus': 'JOINED'}).mode, 'joined');
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerStatus': 'REJECTED'}).mode, 'rejected');
    // 未知状态按最保守的 NONE(不给队长能力)。
    expect(teamCardState(<String, dynamic>{..._base(), 'viewerStatus': 'WHATEVER'}).mode, 'buy');
  });

  test('P2 没票:主按钮「去买这场的票」,无次级;P3 有票:「申请加入」', () {
    final TeamCardState buy = teamCardState(_base());
    expect(buy.primary?.text, '去买这场的票');
    expect(buy.primary?.action, 'buy');
    expect(buy.secondary, isNull);
    expect(buy.notice?.text, '加入队伍需要先持有这一场的票');
    expect(buy.foot, '买完回到地图,这张卡会变成「申请加入」');

    final TeamCardState apply = teamCardState(<String, dynamic>{
      ..._base(),
      'viewerHasTicket': true,
    });
    expect(apply.primary?.text, '申请加入');
    expect(apply.notice?.tone, 'ok');
    expect(apply.foot, '队长同意后,你会自动进入这支队伍的群聊');
  });

  test('P4 申请中:即使有票也只剩「撤回申请」+ 失效说明(真源 @a7d179760)', () {
    final TeamCardState state = teamCardState(<String, dynamic>{
      ..._base(),
      'viewerStatus': 'PENDING',
      'viewerHasTicket': true,
    });
    expect(state.primary, isNull);
    expect(state.secondary?.text, '撤回申请');
    expect(state.secondary?.action, 'withdraw');
    // 拿不到 applyExpireTime → 通用规则句,**不许**再断言写死的小时数
    // (真失效 = min(申请+24h, 场次开始);契约见 team_apply_expire_contract_test)。
    expect(state.foot, '队长没处理或活动开始时,申请自动失效');
  });

  test('被拒不能再申:REJECTED 卡片一个按钮都没有(有票也不给)', () {
    final TeamCardState state = teamCardState(<String, dynamic>{
      ..._base(),
      'viewerStatus': 'REJECTED',
      'viewerHasTicket': true,
    });
    expect(state.mode, 'rejected');
    expect(state.primary, isNull);
    expect(state.secondary, isNull);
    expect(state.notice?.text, '不能再申请这支队伍');
  });

  test('P5 队长:进审批模式,不出申请/买票按钮', () {
    final TeamCardState state = teamCardState(<String, dynamic>{
      ..._base(),
      'viewerStatus': 'LEADER',
      'pendingCount': 2,
    });
    expect(state.mode, 'leader');
    expect(state.primary, isNull);
    expect(state.secondary, isNull);
  });

  test('卡片文案:标题兜底 / 副标题 / 成员行 / 名字胶囊', () {
    final TeamNearbyCard card = decorateTeam(<String, dynamic>{..._base(), 'title': null});
    expect(card.name, '玩家队伍');
    expect(card.sub, '城市定向 · 外滩源集合 · 距你 600 m');
    expect(card.membersLine, '队长 小周 · 已组 3 人 · 还差 1 人满员');
    expect(card.plate, '玩家队伍 · 3/4');

    expect(
      decorateTeam(<String, dynamic>{..._base(), 'viewerStatus': 'PENDING'}).plate,
      '外滩夜行 · 申请中',
    );
    expect(
      decorateTeam(<String, dynamic>{
        ..._base(),
        'viewerStatus': 'LEADER',
        'pendingCount': 2,
      }).plate,
      '我的队伍 · 2 人申请',
    );
    expect(
      decorateTeam(<String, dynamic>{
        ..._base(),
        'productType': 2,
        'coordSource': 'TOPIC_NODE',
        'distance': 1500,
      }).sub,
      '自由探索 · 外滩源附近 · 距你 1.5 km',
    );
    // 已满员:文案不再说「还差 N 人」。
    expect(
      decorateTeam(<String, dynamic>{..._base(), 'joinedCount': 4}).membersLine,
      '队长 小周 · 已组 4 人 · 已满员',
    );
  });

  test('私密字段不进卡片视图:inviteCode / leaderMemberId / ownerType 一律丢掉', () {
    final TeamNearbyCard card = decorateTeam(<String, dynamic>{
      ..._base(),
      'inviteCode': 'SECRET1',
      'leaderMemberId': 99,
      'ownerType': 2,
    });
    final String json = <String, Object?>{
      'name': card.name,
      'heading': card.heading,
      'sub': card.sub,
      'plate': card.plate,
      'faces': card.faces,
    }.toString();
    expect(json.contains('SECRET1'), isFalse);
    expect(json.contains('99'), isFalse);
  });

  test('顶部条与角控件文案(含范围回卷)', () {
    expect(teamHeaderText(2), '附近的队伍 · 2 支在招募');
    expect(teamHeaderText(0), '附近的队伍 · 0 支在招募');
    expect(teamRangeText(1000), '范围 1 km');
    expect(teamRangeText(3000), '范围 3 km');
    expect(teamNextRadius(1000), 3000);
    expect(teamNextRadius(20000), 1000);
    expect(teamMyTeamsText(0), '我的队伍');
    expect(teamMyTeamsText(2), '我的队伍 · 2');
  });

  test('errorCode=apply:每个码落到对的界面动作(只认码,不解析 msg)', () {
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'TICKET_REQUIRED'}).patch,
      <String, Object?>{'viewerHasTicket': false, 'viewerStatus': 'NONE'},
    );
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'APPLY_REJECTED'}).patch,
      <String, Object?>{'viewerStatus': 'REJECTED'},
    );
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'APPLY_PENDING'}).patch,
      <String, Object?>{'viewerStatus': 'PENDING'},
    );
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'ALREADY_JOINED'}).patch,
      <String, Object?>{'viewerStatus': 'JOINED'},
    );
    // 满员 / 进行中 / 审核中:撤下队伍,地图上不再有申请入口。
    for (final String code in <String>[
      'TEAM_FULL',
      'ACTIVITY_STARTED',
      'TEAM_UNDER_REVIEW',
      'TEAM_NOT_PUBLIC',
    ]) {
      final TeamErrorOutcome outcome = resolveTeamError('apply', <String, dynamic>{'errorCode': code});
      expect(outcome.dropTeam, isTrue, reason: code);
    }
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'TICKET_REQUIRED'}).primary,
      '去买票',
    );
    expect(
      resolveTeamError('apply', <String, dynamic>{'errorCode': 'APPLY_BLOCKED'}).dropTeam,
      isFalse,
    );
  });

  test('errorCode=withdraw / handle:24h 失效与满员刷新各归各位', () {
    expect(
      resolveTeamError('withdraw', <String, dynamic>{'errorCode': 'APPLY_NOT_PENDING'}).refresh,
      isTrue,
    );
    expect(
      resolveTeamError('handle', <String, dynamic>{'errorCode': 'APPLY_NOT_PENDING'}).dropApplicant,
      isTrue,
    );
    expect(
      resolveTeamError('handle', <String, dynamic>{'errorCode': 'TICKET_REQUIRED'}).dropApplicant,
      isTrue,
    );
    expect(
      resolveTeamError('handle', <String, dynamic>{'errorCode': 'TEAM_FULL'}).refresh,
      isTrue,
    );
  });

  test('没有 errorCode 只报兜底失败:文案里写了码也不触发状态改动', () {
    final TeamErrorOutcome outcome = resolveTeamError('apply', <String, dynamic>{
      'msg': '请先购买本场次的票(TICKET_REQUIRED)',
    });
    expect(outcome.patch, isNull);
    expect(outcome.dropTeam, isFalse);
    expect(outcome.why, '请先购买本场次的票(TICKET_REQUIRED)');
    expect(outcome.primary, '');
    expect(outcome.title, '申请没发出去');
  });

  test('失败出口合同:标题恒有、动作最多两个', () {
    final List<String?> codes = <String?>[
      'TICKET_REQUIRED', 'APPLY_REJECTED', 'APPLY_PENDING', 'ALREADY_JOINED',
      'TEAM_FULL', 'ACTIVITY_STARTED', 'TEAM_UNDER_REVIEW', 'TEAM_NOT_PUBLIC',
      'APPLY_BLOCKED', 'APPLY_NOT_PENDING', null,
    ];
    for (final String op in <String>['apply', 'withdraw', 'handle']) {
      for (final String? code in codes) {
        final TeamErrorOutcome outcome = resolveTeamError(op, <String, dynamic>{'errorCode': code, 'msg': 'x'});
        expect(outcome.title, isNotEmpty, reason: '$op/$code');
        expect(
          <String>[outcome.primary, outcome.secondary].where((String s) => s.isNotEmpty).length <= 2,
          isTrue,
        );
      }
    }
  });

  test('P6 三态行:已加入 / 申请中 / 队长未同意;同队去重以已加入为准;私密字段不进', () {
    final List<MyTeamRow> rows = myTeamRows(
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 7, 'title': '外滩夜行', 'joinedCount': 3, 'maxMembers': 4, 'status': 0, 'inviteCode': 'SECRET1'},
        // 已结束(3)/ 已解散(4)不进「我的队伍」。
        <String, dynamic>{'id': 9, 'title': '散了', 'joinedCount': 1, 'maxMembers': 4, 'status': 4},
        <String, dynamic>{'id': 12, 'title': '结束了', 'joinedCount': 4, 'maxMembers': 4, 'status': 3},
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{'teamId': 8, 'title': '苏河湾探店日', 'leaderName': '阿May', 'applyStatus': 'PENDING'},
        <String, dynamic>{'teamId': 10, 'title': '霓虹拾光', 'leaderName': 'x', 'applyStatus': 'REJECTED'},
        <String, dynamic>{'teamId': 7, 'title': '外滩夜行', 'applyStatus': 'PENDING'},
      ],
    );
    expect(
      rows.map((MyTeamRow r) => <Object?>[r.teamId, r.badge, r.actionText, r.actionKind, r.sub, r.action]).toList(),
      <List<Object?>>[
        <Object?>[7, '已加入', '进入队伍', 'primary', '3/4 人', 'enter'],
        <Object?>[8, '申请中', '撤回申请', 'secondary', '队长 阿May', 'withdraw'],
        <Object?>[10, '队长未同意', '看附近队伍', 'secondary', '不能再申请这支队伍', 'nearby'],
      ],
    );
    expect(rows.toString().contains('SECRET1'), isFalse);
    // 角控件计数不算被拒。
    expect(teamMyTeamsCount(rows), 2);
  });

  test('P5 申请人行:「持本场票 · N 分钟前申请」;解析不出的时间不编', () {
    final DateTime now = DateTime(2026, 9, 15, 12, 10);
    final List<TeamApplicantRow> rows = teamApplicantRows(
      <Map<String, dynamic>>[
        <String, dynamic>{'memberId': 5, 'memberName': '阿杰', 'memberAvatar': 'x', 'appliedAt': '2026-09-15 12:08:00'},
        <String, dynamic>{'memberId': 6, 'memberName': 'Mia', 'appliedAt': '看不懂的时间'},
      ],
      now,
    );
    expect(rows.first.sub, '持本场票 · 2 分钟前申请');
    expect(rows[1].sub, '持本场票');
    expect(teamLeaderSub(<String, dynamic>{'joinedCount': 3, 'maxMembers': 4}), '你是队长 · 已组 3/4 · 还能再加 1 人');
    expect(teamLeaderFoot(<String, dynamic>{'joinedCount': 3, 'maxMembers': 4}), '同意 1 人后队伍满员:从地图上消失,其余申请自动失效');
  });

  test('TEAM_NOT_PUBLIC 不冒充「已满 / 已开始」', () {
    final TeamErrorOutcome outcome = resolveTeamError('apply', <String, dynamic>{'errorCode': 'TEAM_NOT_PUBLIC'});
    expect(outcome.dropTeam, isTrue);
    expect(outcome.title, '这支队伍只接受邀请');
  });
}
