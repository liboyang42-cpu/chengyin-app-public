// 运营四页的模型层形状纪律(负控):「算不出来」与「是零」、「回执坏了」与
// 「没权限」必须分开,坏形状一律返回 null/抛错,不拿 0 或空串兜底。
//
// 逐条对齐小程序 pages/club/{event-ops,governance,notify,roles}(@90e66d70):
//   - event-ops:occurrence 的 signupCount=null → 「报名数待确认」且不给编辑;
//     series 的 offerMinutes/version/recurrence/capacity/waitlistEnabled 全是硬校验;
//   - governance:俱乐部封禁必须有到期时间,平台永久封禁没有;申诉的 targetType 只能是 BAN;
//   - notify:preview 必须 phoneIncluded=false 且站内可用、订阅号不可用;
//   - roster:phoneIncluded 必须是 false(服务端越界下发手机号 = 回执坏了)。

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_login_gate.dart';
import 'package:chengyin_app/feature/club/club_ops_access.dart';

Map<String, dynamic> _seriesJson({
  Object? version = 3,
  Object? offerMinutes = 1440,
  String recurrenceType = 'WEEKLY',
  Object? capacity,
  Object? waitlistEnabled = true,
}) => <String, dynamic>{
  'id': 7,
  'clubId': 1,
  'topicId': 12,
  'defaultLeadMemberId': 1,
  'version': version,
  'recurrenceType': recurrenceType,
  'defaultCapacity': capacity,
  'waitlistEnabled': waitlistEnabled,
  'offerMinutes': offerMinutes,
  'futureDates': <String>['2026-10-01'],
};

Map<String, dynamic> _accessJson({
  Object? active = true,
  Object? canManageRoles = true,
  Object? clubId = 1,
}) => <String, dynamic>{
  'active': active,
  'canManageRoles': canManageRoles,
  'club': <String, dynamic>{'id': clubId},
  'permissions': <String>[kClubNotifySend],
  'roleCodes': <String>['CLUB_OWNER'],
};

DioException _status(int status) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: status,
  ),
);

void main() {
  group('ClubOpsAccess:active 必须明说', () {
    test('active 不是布尔 → activeDeclared=false(调用方进错误态,不栽成没权限)', () {
      expect(
        ClubOpsAccess.fromJson(_accessJson(active: null)).activeDeclared,
        isFalse,
      );
      expect(
        ClubOpsAccess.fromJson(_accessJson(active: 'true')).active,
        isFalse,
      );
      expect(
        ClubOpsAccess.fromJson(_accessJson(active: true)).activeDeclared,
        isTrue,
      );
    });

    test('canManageRoles 只认严格 true', () {
      expect(
        ClubOpsAccess.fromJson(_accessJson(canManageRoles: 1)).canManageRoles,
        isFalse,
      );
      expect(
        ClubOpsAccess.fromJson(
          _accessJson(canManageRoles: true),
        ).canManageRoles,
        isTrue,
      );
    });

    test('clubId=0 视为缺失', () {
      expect(ClubOpsAccess.fromJson(_accessJson(clubId: 0)).clubId, isNull);
    });
  });

  group('ClubOpsDenyReason:拒绝理由分得清', () {
    ClubOpsAccess access({
      bool active = true,
      int clubId = 1,
      Set<String> permissions = const <String>{kClubNotifySend},
    }) => ClubOpsAccess(
      activeDeclared: true,
      active: active,
      clubId: clubId,
      permissions: permissions,
      roleCodes: const <String>[],
      canManageRoles: false,
    );

    test('不属于该俱乐部 vs 页面权限不足', () {
      final ClubOpsAccess outsider = access(clubId: 2);
      expect(
        clubOpsDenyReason(
          outsider,
          clubId: 1,
          allowed: (ClubOpsAccess a) => true,
          deniedMessage: '没权限',
        ),
        '当前账号不属于该俱乐部',
      );
      final ClubOpsAccess member = access(permissions: const <String>{});
      expect(
        clubOpsDenyReason(
          member,
          clubId: 1,
          allowed: (ClubOpsAccess a) => a.has(kClubNotifySend),
          deniedMessage: '没权限',
        ),
        '没权限',
      );
      expect(
        clubOpsDenyReason(
          member,
          clubId: 1,
          allowed: (ClubOpsAccess a) => true,
          deniedMessage: '没权限',
        ),
        isNull,
      );
    });

    test('403 → 权限拒绝;连接失败 → 网络态;业务码 → 业务错误态(401 归登录门)', () {
      // ★ 401 是「没登录」,不是「没权限」:权限屏会把游客指去查自己的角色。
      //   页面(event-ops / governance)先问 clubLoginRequired,是就走登录引导
      //   (test/feature/club/club_login_gate_test.dart);本分类器只兜底
      //   剩下那种还没接登录门的页面,所以 401 仍落 noPermission 这一档。
      expect(clubLoginRequired(_status(401)), isTrue);
      expect(clubLoginRequired(_status(403)), isFalse);
      expect(
        classifyClubOpsFailure(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: 403,
            ),
          ),
        ),
        (denied: true, network: false),
      );
      expect(
        classifyClubOpsFailure(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        ),
        (denied: false, network: true),
      );
      expect(
        clubOpsFailureState(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: 403,
            ),
          ),
        ),
        ClubOpsLoadState.noPermission,
      );
    });
  });

  group('EventSeries:硬校验', () {
    test('合法形状通过', () {
      final EventSeries? series = EventSeries.tryFromJson(
        _seriesJson(),
        clubId: 1,
      );
      expect(series, isNotNull);
      expect(EventSeries.recurrenceLabel('WEEKLY'), '每周');
      expect(EventSeries.recurrenceLabel('SOMETHING'), 'SOMETHING');
    });

    test(
      'version<0 / offerMinutes 越界 / recurrence 非法 / capacity 越界 / waitlist 非布尔 → null',
      () {
        expect(
          EventSeries.tryFromJson(_seriesJson(version: -1), clubId: 1),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(_seriesJson(offerMinutes: 4), clubId: 1),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(_seriesJson(offerMinutes: 1441), clubId: 1),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(
            _seriesJson(recurrenceType: 'DAILY'),
            clubId: 1,
          ),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(_seriesJson(capacity: 0), clubId: 1),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(_seriesJson(capacity: 10001), clubId: 1),
          isNull,
        );
        expect(
          EventSeries.tryFromJson(
            _seriesJson(waitlistEnabled: 'true'),
            clubId: 1,
          ),
          isNull,
        );
      },
    );

    test('capacity 为 null 合法(沿用票种);clubId 不符 → null', () {
      expect(EventSeries.tryFromJson(_seriesJson(), clubId: 1), isNotNull);
      expect(
        EventSeries.tryFromJson(_seriesJson(), clubId: 2),
        isNull,
        reason: '别的俱乐部的系列不能进这个页面',
      );
    });
  });

  group('SeriesOccurrence:算不出来 ≠ 是零', () {
    test('signupCount=null → 报名数待确认;0 → 未开售', () {
      final SeriesOccurrence unknown =
          SeriesOccurrence.fromJson(<String, dynamic>{
            'occurrenceId': 1,
            'activityId': 41,
            'occurrenceAt': '2026-10-01 19:30:00',
            'status': 'ACTIVE',
            'signupCount': null,
            'editable': true,
          });
      expect(unknown.meta, '报名数待确认');
      expect(unknown.badgeKind, 'editable');

      final SeriesOccurrence none = SeriesOccurrence.fromJson(<String, dynamic>{
        'occurrenceId': 1,
        'activityId': 41,
        'occurrenceAt': '2026-10-01 19:30:00',
        'status': 'ACTIVE',
        'signupCount': 0,
        'editable': true,
      });
      expect(none.meta, '未开售');
    });

    test('取消行带退款单数;不可编辑写明锁定原因', () {
      final SeriesOccurrence cancelled =
          SeriesOccurrence.fromJson(<String, dynamic>{
            'occurrenceId': 1,
            'activityId': 41,
            'occurrenceAt': '2026-10-01 19:30:00',
            'status': 'CANCELLED',
            'signupCount': 3,
            'refundedCount': 2,
            'editable': false,
          });
      expect(cancelled.meta, '已退款 2 单');
      expect(cancelled.badgeKind, 'cancelled');

      final SeriesOccurrence locked =
          SeriesOccurrence.fromJson(<String, dynamic>{
            'occurrenceId': 1,
            'activityId': 41,
            'occurrenceAt': '2026-10-01 19:30:00',
            'status': 'ACTIVE',
            'signupCount': 3,
            'editable': false,
            'lockReason': '已开始',
          });
      expect(locked.badge, '已开始');
      expect(locked.badgeKind, 'locked');
    });

    test('日期解析不出来就原样显示,不编日期', () {
      expect(SeriesOccurrence.occurrenceDateText(null), '日期待确认');
      expect(SeriesOccurrence.occurrenceDateText('garbage'), 'garbage');
      expect(
        SeriesOccurrence.occurrenceDateText('2026-10-01 19:30:00'),
        '10月1日 周四 19:30',
      );
    });
  });

  group('OccurrenceStatus / CancellationOutcome', () {
    test('取消状态与发布态必须自洽', () {
      expect(
        OccurrenceStatus.tryFromJson(<String, dynamic>{
          'activityId': 41,
          'occurrenceStatus': 'CANCELLED',
          'activityCancelled': true,
          'publishStatus': 0,
          'cancelReason': '场馆临时封闭',
        }, activityId: 41),
        isNotNull,
      );
      expect(
        OccurrenceStatus.tryFromJson(<String, dynamic>{
          'activityId': 41,
          'occurrenceStatus': 'CANCELLED',
          'activityCancelled': false,
          'publishStatus': 1,
        }, activityId: 41),
        isNull,
        reason: '说取消了但发布态还挂着 → 回执坏了',
      );
      expect(
        OccurrenceStatus.tryFromJson(<String, dynamic>{
          'activityId': 42,
          'occurrenceStatus': 'ACTIVE',
          'activityCancelled': false,
          'publishStatus': 1,
        }, activityId: 41),
        isNull,
        reason: '回读的不是本场 → 不认',
      );
    });

    test('退款进度人话 5 档 + 未知档不编', () {
      String summary(String status) =>
          CancellationOutcome(activityId: 41, refundStatus: status).summary;
      expect(summary('NOT_REQUIRED'), '无需退款');
      expect(summary('MANUAL_REVIEW_REQUIRED'), '退款需人工跟进');
      expect(summary('ACCEPTED_WITH_MANUAL_REVIEW'), '退款任务已受理，部分需人工跟进');
      expect(summary('ACCEPTED'), '退款任务已受理');
      expect(summary('REFUND_REQUESTED'), '退款任务已受理');
      expect(summary('ALREADY_ACCEPTED'), '退款任务已受理');
      expect(summary('SOMETHING_NEW'), '退款状态待回读');
    });
  });

  group('ClubRoster:手机号越界 = 回执坏了', () {
    Map<String, dynamic> rosterJson({Object? phoneIncluded = false}) =>
        <String, dynamic>{
          'registered': <dynamic>[
            <String, dynamic>{'memberId': 12, 'nickname': '阿明'},
          ],
          'waitlist': <dynamic>[],
          'arrived': <dynamic>[],
          'noShow': <dynamic>[],
          'phoneIncluded': phoneIncluded,
        };

    test('phoneIncluded=false 才认', () {
      expect(ClubRoster.tryFromJson(rosterJson()), isNotNull);
      expect(ClubRoster.tryFromJson(rosterJson(phoneIncluded: true)), isNull);
      expect(ClubRoster.tryFromJson(rosterJson(phoneIncluded: null)), isNull);
    });

    test('桶形状不全 / 成员缺 id → null,不拿空桶兜底', () {
      final Map<String, dynamic> broken = rosterJson()..remove('waitlist');
      expect(ClubRoster.tryFromJson(broken), isNull);
      expect(
        ClubRoster.tryFromJson(<String, dynamic>{
          ...rosterJson(),
          'registered': <dynamic>[
            <String, dynamic>{'nickname': '阿明'},
          ],
        }),
        isNull,
      );
    });

    test('昵称缺失用 id 兜底,不出现空行', () {
      final ClubRoster? roster = ClubRoster.tryFromJson(<String, dynamic>{
        ...rosterJson(),
        'registered': <dynamic>[
          <String, dynamic>{'memberId': 12, 'nickname': '  '},
        ],
      });
      expect(roster!.registered.single.nickname, '成员 #12');
    });
  });

  group('GovernanceBan / GovernanceCase', () {
    Map<String, dynamic> banJson({
      String sourceType = 'CLUB',
      String status = 'ACTIVE',
      Object? expiresAt = '2026-10-01T10:00:00',
      Object? version = 5,
      String banReason = '连续骚扰',
    }) => <String, dynamic>{
      'id': 21,
      'clubId': 1,
      'targetMemberId': 12,
      'targetNickname': '阿明',
      'sourceType': sourceType,
      'status': status,
      'version': version,
      'banReason': banReason,
      'bannedAt': '2026-09-01T10:00:00',
      'expiresAt': expiresAt,
    };

    test('俱乐部封禁必须有到期时间;平台封禁可永久', () {
      expect(GovernanceBan.tryList(<dynamic>[banJson()], 1), hasLength(1));
      expect(
        GovernanceBan.tryList(<dynamic>[banJson(expiresAt: null)], 1),
        isNull,
        reason: '俱乐部封禁没有到期时间 → 回执坏了',
      );
      final List<GovernanceBan>? platform = GovernanceBan.tryList(<dynamic>[
        banJson(sourceType: 'PLATFORM', expiresAt: null),
      ], 1);
      expect(platform, hasLength(1));
      expect(platform!.single.expiresText, '平台永久封禁');
      expect(platform.single.canClubUnban, isFalse);
    });

    test('解封只给「生效中 + 俱乐部封禁」;理由缺失 / 版本非法 → 坏回执', () {
      final List<GovernanceBan>? rows = GovernanceBan.tryList(<dynamic>[
        banJson(),
        banJson(status: 'UNBANNED'),
      ], 1);
      expect(rows, hasLength(2));
      expect(rows!.first.canClubUnban, isTrue);
      expect(rows.last.canClubUnban, isFalse);
      expect(rows.last.statusText, '已解封');
      expect(
        GovernanceBan.tryList(<dynamic>[banJson(banReason: '  ')], 1),
        isNull,
      );
      expect(GovernanceBan.tryList(<dynamic>[banJson(version: -1)], 1), isNull);
      expect(
        GovernanceBan.tryList(<dynamic>[banJson(status: 'BANNED')], 1),
        isNull,
      );
      expect(
        GovernanceBan.tryList(<dynamic>[banJson()], 2),
        isNull,
        reason: '别的俱乐部的治理记录不能混进来',
      );
    });

    test('工单:申诉的 targetType 只能是 BAN;举报要三种目标之一', () {
      Map<String, dynamic> caseJson({
        String caseType = 'REPORT',
        String targetType = 'MEMBER',
      }) => <String, dynamic>{
        'id': 7,
        'clubId': 1,
        'caseType': caseType,
        'targetType': targetType,
        'targetId': 12,
        'reason': '在活动现场多次骚扰他人',
        'status': 'PENDING',
        'version': 1,
        'createTime': '2026-09-05T09:00:00',
      };

      expect(GovernanceCase.tryList(<dynamic>[caseJson()], 1), hasLength(1));
      expect(
        GovernanceCase.tryList(<dynamic>[
          caseJson(caseType: 'REPORT', targetType: 'CLUB'),
        ], 1),
        hasLength(1),
      );
      expect(
        GovernanceCase.tryList(<dynamic>[
          caseJson(caseType: 'APPEAL', targetType: 'MEMBER'),
        ], 1),
        isNull,
        reason: '申诉只能针对封禁',
      );
      expect(
        GovernanceCase.tryList(<dynamic>[
          caseJson(caseType: 'APPEAL', targetType: 'BAN'),
        ], 1),
        hasLength(1),
      );
      expect(GovernanceCase.reportTargetText('ACTIVITY'), '活动');
      expect(GovernanceCase.reportTargetText('MEMBERS'), '成员');
    });
  });

  group('RoleScopeData:范围与形状', () {
    Map<String, dynamic> roleJson({
      String roleCode = 'CLUB_CO_OWNER',
      String scopeType = 'CLUB',
    }) => <String, dynamic>{
      'roleCode': roleCode,
      'name': '副主理人',
      'scopeType': scopeType,
      'permissions': <String>['club:member:manage'],
    };

    Map<String, dynamic> assignmentJson({
      String scopeType = 'CLUB',
      int scopeId = 1,
      String roleCode = 'CLUB_CO_OWNER',
    }) => <String, dynamic>{
      'id': 11,
      'targetMemberId': 12,
      'memberName': '阿明',
      'roleCode': roleCode,
      'roleName': '副主理人',
      'scopeType': scopeType,
      'scopeId': scopeId,
      'version': 3,
    };

    test('带 activityId 只认场次级角色与场次范围委派', () {
      final RoleScopeData? eventScope = RoleScopeData.tryFromJson(
        <String, dynamic>{
          'roles': <dynamic>[
            roleJson(roleCode: 'EVENT_LEAD', scopeType: 'EVENT'),
          ],
          'assignments': <dynamic>[
            assignmentJson(scopeType: 'EVENT', scopeId: 9),
          ],
        },
        clubId: 1,
        activityId: 9,
      );
      expect(eventScope, isNotNull);
      expect(eventScope!.roles.single.roleCode, 'EVENT_LEAD');
      expect(
        eventScope.roles.single.summary,
        '仅负责当前场次的现场执行与核销',
        reason: '固定角色说明逐字上屏',
      );

      // 场次范围里混进俱乐部级角色 → 坏回执。
      expect(
        RoleScopeData.tryFromJson(
          <String, dynamic>{
            'roles': <dynamic>[roleJson()],
            'assignments': <dynamic>[],
          },
          clubId: 1,
          activityId: 9,
        ),
        isNull,
      );
      // 委派挂到别的场次 → 坏回执。
      expect(
        RoleScopeData.tryFromJson(
          <String, dynamic>{
            'roles': <dynamic>[
              roleJson(roleCode: 'EVENT_LEAD', scopeType: 'EVENT'),
            ],
            'assignments': <dynamic>[
              assignmentJson(
                roleCode: 'EVENT_LEAD',
                scopeType: 'EVENT',
                scopeId: 8,
              ),
            ],
          },
          clubId: 1,
          activityId: 9,
        ),
        isNull,
      );
    });

    test('俱乐部范围:roles 全被过滤掉 → null;缺 permissions → null', () {
      expect(
        RoleScopeData.tryFromJson(<String, dynamic>{
          'roles': <dynamic>[
            roleJson(roleCode: 'EVENT_LEAD', scopeType: 'EVENT'),
          ],
          'assignments': <dynamic>[],
        }, clubId: 1),
        isNull,
      );
      expect(
        RoleScopeData.tryFromJson(<String, dynamic>{
          'roles': <dynamic>[
            <String, dynamic>{
              'roleCode': 'CLUB_OPERATOR',
              'name': '运营管理员',
              'scopeType': 'CLUB',
            },
          ],
          'assignments': <dynamic>[],
        }, clubId: 1),
        isNull,
      );
    });

    test('成员名缺失用 id 兜底;version<0 → 该行跳过', () {
      final RoleScopeData? data = RoleScopeData.tryFromJson(<String, dynamic>{
        'roles': <dynamic>[roleJson()],
        'assignments': <dynamic>[
          <String, dynamic>{
            'id': 11,
            'targetMemberId': 12,
            'memberName': ' ',
            'roleCode': 'CLUB_CO_OWNER',
            'roleName': '副主理人',
            'scopeType': 'CLUB',
            'scopeId': 1,
            'version': 3,
          },
          <String, dynamic>{
            'id': 12,
            'targetMemberId': 13,
            'roleCode': 'CLUB_CO_OWNER',
            'scopeType': 'CLUB',
            'scopeId': 1,
            'version': -1,
          },
        ],
      }, clubId: 1);
      expect(data!.assignments, hasLength(1));
      expect(data.assignments.single.memberName, '成员 #12');
    });

    test('RoleOption.allowed 的分档', () {
      expect(RoleOption.allowed('CLUB_CO_OWNER', eventScoped: false), isTrue);
      expect(RoleOption.allowed('EVENT_LEAD', eventScoped: false), isFalse);
      expect(RoleOption.allowed('EVENT_LEAD', eventScoped: true), isTrue);
      expect(RoleOption.allowed('CLUB_OPERATOR', eventScoped: true), isFalse);
    });
  });

  group('notify:预览与人数', () {
    NotificationPreview? preview(Map<String, dynamic> json) =>
        NotificationPreview.tryFromJson(json);

    test('合法形状:站内可用、订阅号不可用、不下发手机号', () {
      expect(
        preview(<String, dynamic>{
          'recipientCount': 12,
          'phoneIncluded': false,
          'inApp': 'AVAILABLE',
          'wechatSubscription': 'UNAVAILABLE',
        }),
        isNotNull,
      );
    });

    test('手机号越界 / 渠道状态不符 / 人数非法 → null', () {
      expect(
        preview(<String, dynamic>{
          'recipientCount': 12,
          'phoneIncluded': true,
          'inApp': 'AVAILABLE',
          'wechatSubscription': 'UNAVAILABLE',
        }),
        isNull,
      );
      expect(
        preview(<String, dynamic>{
          'recipientCount': 12,
          'phoneIncluded': false,
          'inApp': 'UNAVAILABLE',
          'wechatSubscription': 'UNAVAILABLE',
        }),
        isNull,
      );
      expect(
        preview(<String, dynamic>{
          'recipientCount': -1,
          'phoneIncluded': false,
          'inApp': 'AVAILABLE',
          'wechatSubscription': 'UNAVAILABLE',
        }),
        isNull,
      );
      expect(preview(<String, dynamic>{'recipientCount': 0}), isNull);
    });

    test('人数算不出来 → 该分组不给数(而不是 0)', () {
      final AudienceCounts? counts = AudienceCounts.tryFromJson(
        <String, dynamic>{
          'counts': <String, dynamic>{'ALL_MEMBERS': null, 'ADMINS': 3},
        },
      );
      expect(counts, isNotNull);
      expect(counts!.counts['ALL_MEMBERS'], isNull);
      expect(counts.counts['ADMINS'], 3);
    });

    test('发送回执必须带正整数 id;人数字段缺失按 0 —— 但 id 缺了就是坏回执', () {
      expect(
        NotificationCampaign.tryFromJson(<String, dynamic>{
          'id': 88,
          'totalCount': 12,
          'successCount': 10,
          'failedCount': 2,
        }),
        isNotNull,
      );
      expect(
        NotificationCampaign.tryFromJson(<String, dynamic>{
          'totalCount': 12,
          'successCount': 10,
          'failedCount': 2,
        }),
        isNull,
      );
    });
  });

  group('幂等键', () {
    test('requestId 带前缀且两次不重复', () {
      final String first = ClubOpsApi.newRequestId('club-role');
      final String second = ClubOpsApi.newRequestId('club-role');
      expect(first, startsWith('club-role'));
      expect(first, isNot(second));
    });
  });
}
