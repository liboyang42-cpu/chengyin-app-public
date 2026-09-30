// ClubDirectorProjection 契约测试 —— 小程序 `club-game-director-adapter.js`
// normalize/派生闸的移植是否忠实,全看这里。
//
// 纪律只有一条:**数不进来就报「待确认」,绝不兜底成 0/空** ——
// 主理人把「0/5 站 READY」当事实,和把缺失的 teamsReady 当 false 一样危险。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_director.dart';

Map<String, dynamic> _base({
  String perspective = 'CLUB',
  String status = 'RUNNING',
  int revision = 3,
  List<String> actions = const <String>['FINISH'],
  Map<String, dynamic>? club,
}) => <String, dynamic>{
  'perspective': perspective,
  'activityId': 41,
  'status': status,
  'revision': revision,
  'availableActions': actions,
  'club':
      club ??
      <String, dynamic>{
        'readiness': <String, dynamic>{
          'requiredStations': 2,
          'readyStations': 1,
          'teamsReady': false,
        },
      },
};

ClubDirectorProjection _parse(Map<String, dynamic> raw) =>
    ClubDirectorProjection.fromJson(raw);

void main() {
  group('入口闸', () {
    test('非 CLUB 视角 → OWNER_REQUIRED(投错视角不能混进导演台)', () {
      for (final String perspective in <String>['PLAYER', 'MERCHANT', '']) {
        expect(
          () => _parse(_base(perspective: perspective)),
          throwsA(
            isA<ClubDirectorFormatException>().having(
              (ClubDirectorFormatException e) => e.code,
              'code',
              'OWNER_REQUIRED',
            ),
          ),
          reason: 'perspective=$perspective',
        );
      }
    });

    test('没有 club 块只有「无局可 PREPARE」这一种合法空壳', () {
      final ClubDirectorProjection shell = _parse(<String, dynamic>{
        'perspective': 'CLUB',
        'activityId': 41,
        'status': 'NOT_PREPARED',
        'revision': 0,
        'availableActions': <String>['PREPARE'],
      });
      expect(shell.canPrepare, isTrue);
      expect(
        () => _parse(<String, dynamic>{
          'perspective': 'CLUB',
          'activityId': 41,
          'status': 'RUNNING',
          'revision': 0,
          'availableActions': <String>['FINISH'],
        }),
        throwsA(isA<ClubDirectorFormatException>()),
        reason: '进行中却没有 club 块 = 形状坏,不是空局',
      );
    });
  });

  group('状态与就绪的读法', () {
    test('七态中文标签;没见过的态读「状态待确认」而不是猜', () {
      expect(_parse(_base(status: 'NOT_PREPARED')).sessionStatusText, '未准备');
      expect(_parse(_base(status: 'DRAFT')).sessionStatusText, '草稿');
      expect(_parse(_base(status: 'PREPARING')).sessionStatusText, '准备中');
      expect(_parse(_base(status: 'READY')).sessionStatusText, '待开局');
      expect(_parse(_base(status: 'RUNNING')).sessionStatusText, '进行中');
      expect(_parse(_base(status: 'FINISHED')).sessionStatusText, '已结束');
      expect(_parse(_base(status: 'CANCELLED')).sessionStatusText, '已取消');
      expect(_parse(_base(status: 'WARP_DRIVE')).sessionStatusText, '状态待确认');
    });

    test('readiness 数不进来报「待确认」,不写 0/x', () {
      final ClubDirectorProjection unknown = _parse(
        _base(club: <String, dynamic>{'readiness': <String, dynamic>{}}),
      );
      expect(unknown.readinessText, '站点准备数据待确认');
      expect(
        _parse(
          _base(
            club: <String, dynamic>{
              'readiness': <String, dynamic>{
                'requiredStations': 5,
                'readyStations': 3,
              },
            },
          ),
        ).readinessText,
        '3/5 站 READY',
      );
    });

    test('blockers:服务端显式给的原样用;没给才按三判据兜底(真源同序)', () {
      final ClubDirectorProjection explicit = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{
              'requiredStations': 2,
              'readyStations': 2,
              'teamsReady': true,
              'blockers': <String>['商家端未接入'],
            },
          },
        ),
      );
      expect(explicit.readiness.blockers, <String>['商家端未接入']);

      final ClubDirectorProjection derived = _parse(_base());
      expect(derived.readiness.blockers, <String>['1 个站点未 READY', '仍有队员未分配角色']);
    });
  });

  group('派生闸', () {
    test('canAssignRoles 要动作 + roleOptions 两个都有;榜单闸要 visible 真是布尔', () {
      ClubDirectorProjection p(List<String> a, Map<String, dynamic> club) =>
          _parse(_base(actions: a, club: club));
      final Map<String, dynamic> opts = <String, dynamic>{
        'readiness': <String, dynamic>{},
        'roleOptions': <Map<String, dynamic>>[
          <String, dynamic>{'roleCode': 'LEADER', 'roleName': '队长'},
        ],
      };
      expect(p(<String>['ASSIGN_ROLES'], opts).canAssignRoles, isTrue);
      expect(p(<String>[], opts).canAssignRoles, isFalse);
      expect(
        p(
          <String>['ASSIGN_ROLES'],
          <String, dynamic>{'readiness': <String, dynamic>{}},
        ).canAssignRoles,
        isFalse,
        reason: '有动作没选项 = 开了个必挂的按钮',
      );
      expect(
        p(
          <String>['SET_LEADERBOARD_VISIBILITY'],
          <String, dynamic>{'readiness': <String, dynamic>{}},
        ).canToggleLeaderboard,
        isFalse,
        reason: 'leaderboardVisible 缺省 = 状态待确认,不给切',
      );
      expect(
        p(
          <String>['SET_LEADERBOARD_VISIBILITY'],
          <String, dynamic>{
            'readiness': <String, dynamic>{},
            'leaderboard': <String, dynamic>{'visible': true},
          },
        ).canToggleLeaderboard,
        isTrue,
      );
    });

    test('章节候选:已解锁/不可解的适配器闸先滤,当前章节再排除,空标题兜「章节 #id」', () {
      final ClubDirectorProjection p = _parse(<String, dynamic>{
        ..._base(actions: <String>['UNLOCK_CHAPTER']),
        'currentChapterId': 1,
        'club': <String, dynamic>{
          'readiness': <String, dynamic>{},
          'chapterOptions': <Map<String, dynamic>>[
            <String, dynamic>{'chapterId': 1, 'title': '第一章'},
            <String, dynamic>{'chapterId': 2, 'title': '第二章'},
            <String, dynamic>{'chapterId': 3, 'title': '', 'unlockable': true},
            <String, dynamic>{'chapterId': 4, 'title': '第四章', 'unlocked': true},
            <String, dynamic>{
              'chapterId': 5,
              'title': '第五章',
              'unlockable': false,
            },
          ],
        },
      });
      expect(
        p.unlockChapterOptions.map(
          (ClubDirectorChapterOption o) => o.chapterId,
        ),
        <int>[2, 3],
      );
      expect(p.unlockChapterOptions.last.title, '章节 #3');
      expect(p.canUnlockChapter, isTrue);
    });

    test('接管来源只认「有角色码且 CONFIRMED」的行', () {
      final ClubDirectorProjection p = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'roles': <Map<String, dynamic>>[
              <String, dynamic>{
                'teamId': 5,
                'memberId': 11,
                'roleCode': 'LEADER',
                'status': 'CONFIRMED',
              },
              <String, dynamic>{
                'teamId': 5,
                'memberId': 12,
                'roleCode': 'LEADER',
                'confirmationStatus': 'PENDING',
              },
              <String, dynamic>{'teamId': 5, 'memberId': 13},
            ],
          },
        ),
      );
      expect(
        p.takeoverCandidates.single.memberId,
        11,
        reason: 'status 与 confirmationStatus 同源取其一',
      );
    });

    test('roleMemberRows:行 id 是 teamId:memberId,没角色码的行是灰的', () {
      final ClubDirectorProjection p = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'teams': <Map<String, dynamic>>[
              <String, dynamic>{'teamId': 5, 'name': '红队'},
            ],
            'roles': <Map<String, dynamic>>[
              <String, dynamic>{
                'teamId': 5,
                'memberId': 11,
                'memberName': '阿岚',
                'roleCode': 'LEADER',
                'roleName': '队长',
              },
              <String, dynamic>{
                'teamId': 5,
                'memberId': 12,
                'memberName': '小游',
              },
              <String, dynamic>{'memberId': 13},
            ],
          },
        ),
      );
      final List<ClubDirectorMemberRow> rows = p.roleMemberRows;
      expect(rows, hasLength(2), reason: '没有 teamId 的行定位不了,不进表');
      expect(rows.first.id, '5:11');
      expect(rows.first.value, '队长');
      expect(rows.first.muted, isFalse);
      expect(rows.last.title, '小游');
      expect(rows.last.value, '角色待分配');
      expect(rows.last.muted, isTrue);
    });
  });

  group('广播人数', () {
    test('全部档:有一队人数数不进来就是 null,界面读「人数待确认」', () {
      final ClubDirectorProjection complete = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'teams': <Map<String, dynamic>>[
              <String, dynamic>{'teamId': 5, 'memberCount': 4},
              <String, dynamic>{'teamId': 6, 'memberCount': 3},
            ],
          },
        ),
      );
      final ClubDirectorBroadcastTarget all = complete
          .broadcastTargets('ALL')
          .single;
      expect(all.label, '全部在场玩家');
      expect(complete.broadcastRecipientCount(all), 7);
      expect(complete.broadcastRecipientCount(null), isNull);

      final ClubDirectorProjection hole = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'teams': <Map<String, dynamic>>[
              <String, dynamic>{'teamId': 5, 'memberCount': 4},
              <String, dynamic>{'teamId': 6},
            ],
          },
        ),
      );
      expect(
        hole.broadcastRecipientCount(hole.broadcastTargets('ALL').single),
        isNull,
        reason: '4 + 未知 ≠ 4 —— 不许拿已知数当全量',
      );
    });

    test('角色档:聚合数优先;缺聚合但每行可点人也行;两头不全 → null', () {
      ClubDirectorProjection withRoles(List<Map<String, dynamic>> roles) =>
          _parse(
            _base(
              club: <String, dynamic>{
                'readiness': <String, dynamic>{},
                'roleOptions': <Map<String, dynamic>>[
                  <String, dynamic>{'roleCode': 'LEADER'},
                ],
                'roles': roles,
              },
            ),
          );
      final ClubDirectorProjection aggregated = withRoles(
        <Map<String, dynamic>>[
          <String, dynamic>{'roleCode': 'LEADER', 'memberCount': 3},
          <String, dynamic>{'roleCode': 'PHOTO', 'memberCount': 2},
        ],
      );
      final ClubDirectorBroadcastTarget leader = aggregated
          .broadcastTargets('ROLE')
          .single;
      expect(leader.label, 'LEADER', reason: '没给 roleName 用 roleCode 兜底');
      expect(aggregated.broadcastRecipientCount(leader), 3);

      final ClubDirectorProjection byPerson = withRoles(<Map<String, dynamic>>[
        <String, dynamic>{'roleCode': 'LEADER', 'memberId': 11},
        <String, dynamic>{'roleCode': 'LEADER', 'memberId': 12},
        <String, dynamic>{'roleCode': 'PHOTO', 'memberId': 13},
      ]);
      expect(
        byPerson.broadcastRecipientCount(
          byPerson.broadcastTargets('ROLE').single,
        ),
        2,
      );

      final ClubDirectorProjection partial = withRoles(<Map<String, dynamic>>[
        <String, dynamic>{'roleCode': 'LEADER', 'memberId': 11},
        <String, dynamic>{'memberCount': 5},
      ]);
      expect(
        partial.broadcastRecipientCount(
          partial.broadcastTargets('ROLE').single,
        ),
        isNull,
      );
    });
  });

  group('行投影与排序', () {
    test('站点异常置顶且同档保持原序(稳定排序);名字四级兜底', () {
      final ClubDirectorProjection p = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'stations': <Map<String, dynamic>>[
              <String, dynamic>{'nodeId': 1, 'status': 'READY', 'name': 'A'},
              <String, dynamic>{'nodeId': 2, 'status': 'RUNNING', 'name': 'B'},
              <String, dynamic>{'nodeId': 3, 'status': 'PAUSED', 'name': 'C'},
              <String, dynamic>{
                'nodeId': 4,
                'status': 'ERROR',
                'stationName': 'D',
              },
              <String, dynamic>{'nodeId': 5, 'status': 'READY'},
            ],
          },
        ),
      );
      expect(
        p.stations.map((ClubDirectorStation s) => s.nodeId),
        <int>[3, 4, 2, 1, 5],
        reason: 'PAUSED/ERROR(档0)< RUNNING(档2)< READY(档3);同档保持下发序',
      );
      expect(p.stations.last.nameText, '未命名节点');
      expect(p.stations.first.statusText, 'PAUSED');
      expect(p.stations.first.issueText, isEmpty, reason: '暂停原因没下发就如实为空');
    });

    test('队伍缺数读「进度待确认」,非法 hintLevel / stuckNode 当没下发', () {
      final ClubDirectorProjection p = _parse(
        _base(
          club: <String, dynamic>{
            'readiness': <String, dynamic>{},
            'teams': <Map<String, dynamic>>[
              <String, dynamic>{
                'teamId': 5,
                'teamName': '红队',
                'hintLevel': 9,
                'currentStuckNode': <String, dynamic>{
                  'nodeId': 0,
                  'nodeName': '坏',
                },
                'recentEvent': <String, dynamic>{'action': 'PLAYER_SUBMIT'},
              },
              <String, dynamic>{
                'teamId': 6,
                'completedNodes': 2,
                'totalNodes': 7,
                'hintLevel': 1,
              },
            ],
          },
        ),
      );
      expect(p.teams.first.nameText, '红队');
      expect(p.teams.first.progressText, '进度待确认');
      expect(p.teams.first.hintLevelText, '待确认');
      expect(p.teams.first.stuckNodeText, '待确认');
      expect(p.teams.first.recentEventText, '待确认', reason: '事件缺 outcome 不拼半截话');
      expect(p.teams.last.progressText, '2/7 节点');
      expect(p.teams.last.hintLevelText, '一级提示');
    });
  });
}
