// 4-B 主题运营的模型层形状纪律(负控):「算不出来」与「是零」、「没配」与
// 「无需验证」、「回执坏了」与「没权限」必须分开,坏形状一律返回 null/空串,
// 不拿 0 或 '无需验证' 兜底。
//
// 逐条对齐小程序 pages/club/{topic-detail,topic-story}(@90e66d70):
//   - topic-detail 的状态推断是临时口径:有 rejectReason 但没有 auditStatus
//     必须也落「未通过」,否则被拒主题会显示成已确认、主键变成「开始准备」;
//   - ended 也出核销区(已下架的主题照样可能有已付款未核销的票);
//   - topic-story 的玩法徽标:只有 1/3 两类核验方式存在「答案」,其余挂「· 无答案」;
//   - 步行段是前端用经纬度算的直线估算,拿不到坐标就整行不画(不编数字);
//   - 候补是玩家侧策略:两个字段不自洽 = 回执坏了,返回 null 而不是猜。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/data/models/topic.dart';

TopicChapter _chapter({
  int id = 1,
  String title = '古城',
  int? totalTime,
  String? description,
  List<TopicNode> nodes = const <TopicNode>[],
}) => TopicChapter(
  id: id,
  title: title,
  nodes: nodes,
  description: description,
  totalTime: totalTime,
);

TopicNode _node({
  required int id,
  String name = '钟楼',
  String? address,
  String? businessTime,
  double? latitude,
  double? longitude,
  List<String> images = const <String>[],
  TopicTemplate? template,
}) => TopicNode(
  id: id,
  name: name,
  address: address,
  businessTime: businessTime,
  latitude: latitude,
  longitude: longitude,
  images: images,
  template: template,
);

void main() {
  group('ClubTopicStatus.resolve:推断顺序不许优化', () {
    test('有 rejectReason 但没 auditStatus → 未通过(不是已确认)', () {
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{'rejectReason': '封面不合规'}),
        ClubTopicStatus.rejected,
      );
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{'auditStatus': 2}),
        ClubTopicStatus.rejected,
      );
    });

    test('审核中不许降级成已确认', () {
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{'auditStatus': 0}),
        ClubTopicStatus.reviewing,
      );
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{'auditStatus': 1}),
        ClubTopicStatus.reviewing,
      );
      expect(ClubTopicStatus.reviewing.primaryDisabled, isTrue);
      expect(ClubTopicStatus.reviewing.showsVerify, isFalse);
    });

    test('进行中按 selfPublished 分运行/自玩,两者文案同为「结束活动」', () {
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{
          'startedAt': '2026-09-17 09:00:00',
        }),
        ClubTopicStatus.running,
      );
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{
          'status': 'running',
          'selfPublished': true,
        }),
        ClubTopicStatus.selfRun,
      );
      expect(ClubTopicStatus.running.primaryText, '结束活动');
      expect(ClubTopicStatus.selfRun.primaryText, '结束活动');
    });

    test('结束态:endedAt / status=ended 都算,且必须出核销区', () {
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{
          'endedAt': '2026-09-16 20:00:00',
        }),
        ClubTopicStatus.ended,
      );
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{'status': 'ended'}),
        ClubTopicStatus.ended,
      );
      // 已经下架的主题照样可能有已付款未核销的票要退。
      expect(ClubTopicStatus.ended.showsVerify, isTrue);
      expect(ClubTopicStatus.ended.primaryText, '查看结算报告');
    });

    test('preparingAt → 准备中;什么都没有 → 已确认', () {
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{
          'preparingAt': '2026-09-17 08:00:00',
        }),
        ClubTopicStatus.preparing,
      );
      expect(
        ClubTopicStatus.resolve(<String, dynamic>{}),
        ClubTopicStatus.confirmed,
      );
      expect(ClubTopicStatus.confirmed.primaryText, '开始准备');
      expect(ClubTopicStatus.rejected.primaryText, '修改并重新提交');
      expect(ClubTopicStatus.reviewing.showsRejectReason, isFalse);
      expect(ClubTopicStatus.rejected.showsRejectReason, isTrue);
    });
  });

  group('核验方式码表:没配 ≠ 无需验证', () {
    test('null / 空串 / 坏码都走 fallback,不落「无需验证」', () {
      expect(validationMethodLabel(null), '');
      expect(validationMethodLabel(''), '');
      expect(validationMethodLabel('abc'), '');
      expect(validationMethodLabel(99), '');
      expect(validationMethodLabel(null, fallback: '拍照打卡'), '拍照打卡');
    });

    test('码 0 才是无需验证;字符串码也认', () {
      expect(validationMethodLabel(0), '无需验证');
      expect(validationMethodLabel('0'), '无需验证');
      expect(validationMethodLabel('3'), '选项问答');
      expect(validationMethodLabel(1), '文字作答');
    });

    test('只有 1/3 两类存在「答案」', () {
      expect(kAnswerableValidationMethods, containsAll(<int>[1, 3]));
      expect(kAnswerableValidationMethods, isNot(contains(0)));
      expect(kAnswerableValidationMethods, isNot(contains(2)));
    });
  });

  group('章节标题与时长、步行估算', () {
    test('已经是「第X章」不重复编号', () {
      expect(topicChapterTitle('第三章 古城', 5), '第三章 古城');
      expect(topicChapterTitle('古城', 0), '第一章 · 古城');
      expect(topicChapterTitle('', 0), '第一章');
      expect(topicChapterTitle('', 9), '第十章');
      // 超出中文数字表就退数字,不编「第十一章」之外的怪词。
      expect(topicChapterTitle('', 10), '第11章');
      // 首尾空白不算名字。
      expect(topicChapterTitle('   ', 2), '第三章');
    });

    test('时长三态 + 算不出来给空串', () {
      expect(topicDurationText(200), '3h 20min');
      expect(topicDurationText(180), '3h');
      expect(topicDurationText(20), '20min');
      expect(topicDurationText('95'), '1h 35min');
      expect(topicDurationText(0), '');
      expect(topicDurationText(-30), '');
      expect(topicDurationText(null), '');
      expect(topicDurationText('待定'), '');
    });

    test('步行段:有坐标才算,且最少 1min;缺坐标/零坐标不画', () {
      final String tiny = topicWalkText(
        <String, dynamic>{'latitude': 31.2300, 'longitude': 121.4700},
        <String, dynamic>{'latitude': 31.230005, 'longitude': 121.4700},
      );
      expect(tiny, '1min 步行');
      final String real = topicWalkText(
        <String, dynamic>{'latitude': 31.2300, 'longitude': 121.4700},
        <String, dynamic>{'latitude': 31.2400, 'longitude': 121.4800},
      );
      expect(real, endsWith('步行'));
      expect(real, isNot(contains('0min')));
      expect(topicWalkText(<String, dynamic>{}, <String, dynamic>{}), '');
      expect(
        topicWalkText(
          <String, dynamic>{'latitude': 0, 'longitude': 0},
          <String, dynamic>{'latitude': 31.23, 'longitude': 121.47},
        ),
        '',
      );
      expect(
        topicWalkText(
          <String, dynamic>{'latitude': '31.23', 'longitude': '121.47'},
          <String, dynamic>{'latitude': '31.24', 'longitude': '121.48'},
        ),
        endsWith('步行'),
      );
    });
  });

  group('ClubTopicOverview:公开投影的陈列形状', () {
    Map<String, dynamic> raw({
      Object? nodeCount = 7,
      Object? storyReady = true,
      Object? gameConfiguredCount = 3,
      List<Map<String, dynamic>> activities = const <Map<String, dynamic>>[],
    }) => <String, dynamic>{
      'id': 12,
      'name': '静安夜行',
      'auditStatus': 1,
      'startDate': '2026-09-01 19:00:00',
      'endDate': '2026-09-30 22:00:00',
      'nodeCount': nodeCount,
      'storyReady': storyReady,
      'gameConfiguredCount': gameConfiguredCount,
      'activityList': activities,
    };

    test('坏回执返回 null,不给半个对象', () {
      expect(ClubTopicOverview.tryFromJson(null), isNull);
      expect(
        ClubTopicOverview.tryFromJson(<String, dynamic>{'id': 0, 'name': 'x'}),
        isNull,
      );
      expect(ClubTopicOverview.tryFromJson(<String, dynamic>{'id': 3}), isNull);
    });

    test('站点数为 0 时不画「玩法 0/0」', () {
      final ClubTopicOverview zero = ClubTopicOverview.tryFromJson(
        raw(nodeCount: 0, storyReady: false, gameConfiguredCount: 0),
      )!;
      expect(zero.statusChips, isEmpty);
      final ClubTopicOverview normal = ClubTopicOverview.tryFromJson(raw())!;
      expect(
        normal.statusChips.map((({String text, bool success}) c) => c.text),
        containsAll(<String>['剧情已写', '玩法 3/7']),
      );
    });

    test('soleActivityId 只在恰好一场时给,多场不猜', () {
      expect(ClubTopicOverview.tryFromJson(raw())!.soleActivityId, isNull);
      expect(
        ClubTopicOverview.tryFromJson(
          raw(
            activities: <Map<String, dynamic>>[
              <String, dynamic>{'id': 41, 'name': '周六场'},
            ],
          ),
        )!.soleActivityId,
        41,
      );
      expect(
        ClubTopicOverview.tryFromJson(
          raw(
            activities: <Map<String, dynamic>>[
              <String, dynamic>{'id': 41, 'name': '周六场'},
              <String, dynamic>{'id': 42, 'name': '周日场'},
            ],
          ),
        )!.soleActivityId,
        isNull,
      );
    });

    test('日期区间:两头都有写区间,只缺一头写一头,坏日期不写', () {
      expect(
        ClubTopicOverview.tryFromJson(raw())!.dateRangeText,
        '9月1日 – 9月30日',
      );
      expect(
        ClubTopicOverview.tryFromJson(<String, dynamic>{
          'id': 12,
          'name': 'x',
          'startDate': '2026-09-01 19:00:00',
        })!.dateRangeText,
        '9月1日',
      );
      expect(
        ClubTopicOverview.tryFromJson(<String, dynamic>{
          'id': 12,
          'name': 'x',
          'startDate': '待定',
        })!.dateRangeText,
        '',
      );
    });

    test('核销数缺席当 0,但状态胶囊不与数字纠缠', () {
      final ClubTopicOverview o = ClubTopicOverview.tryFromJson(raw())!;
      final ClubTopicManageStats absent = ClubTopicManageStats.tryFromJson(
        <String, dynamic>{},
      )!;
      expect(o.verifyModeText, '玩家可到店核销');
      expect(
        absent.verifyMetrics.map((({String label, int value}) m) => m.value),
        <int>[0, 0, 0],
        reason: '三个数缺席当 0,不是崩',
      );
    });

    test('本场人数/站数只认管理向统计,详情里的同名键不参与(拍板1)', () {
      final ClubTopicOverview o = ClubTopicOverview.tryFromJson(
        raw(nodeCount: 7),
      )!;
      const ClubTopicManageStats stats = ClubTopicManageStats(
        canDirect: true,
        canManageSessions: true,
        canViewVerify: true,
        nodeCount: 4,
        sessionHeadcount: 9,
        pendingVerifyCount: 2,
        verifiedByMeCount: 1,
      );
      expect(o.chipsOf(stats), <String>['本场 9 人']);
      expect(
        o.structureTextOf(stats),
        '4 站',
        reason: '站数走统计那 4,不认详情的 7;章数与玩法由详情给',
      );
      expect(
        stats.verifyMetrics.map(
          (({String label, int value}) m) => '${m.label}${m.value}',
        ),
        <String>['待核销2', '我已核销1', '本场总人数9'],
      );
    });

    test('三个身份不兜底:false / 0 / 字段缺席都算没权限', () {
      final ClubTopicManageStats none = ClubTopicManageStats.tryFromJson(
        <String, dynamic>{'canDirect': false, 'canManageSessions': 0},
      )!;
      expect(none.canDirect, isFalse);
      expect(none.canManageSessions, isFalse);
      expect(none.canViewVerify, isFalse, reason: '字段缺席 = 没有那块界面,不是「大概是吧」');
      expect(
        ClubTopicManageStats.tryFromJson(<String, dynamic>{
          'canDirect': true,
        })!.canDirect,
        isTrue,
      );
      expect(ClubTopicManageStats.tryFromJson(null), isNull);
      expect(ClubTopicManageStats.tryFromJson(<dynamic>[]), isNull);
    });
  });

  group('TopicSetting / TopicEndResult', () {
    test('章节承接:未开放不显示「N 家」,开放了才显示', () {
      final TopicSetting setting = TopicSetting.tryFromJson(<String, dynamic>{
        'topicName': '静安夜行',
        'canManage': true,
        'chapters': <Map<String, dynamic>>[
          <String, dynamic>{'chapterId': 1, 'name': '第一章', 'recruiting': false},
          <String, dynamic>{
            'chapterId': 2,
            'name': '第二章',
            'recruiting': true,
            'category': '咖啡',
            'merchantCount': 3,
          },
          <String, dynamic>{
            'chapterId': 3,
            'name': '第三章',
            'recruiting': true,
            'merchantCount': 0,
          },
        ],
      })!;
      expect(setting.chapters[0].recruitingText, '未开放');
      expect(setting.chapters[1].recruitingText, '咖啡 · 3 家');
      expect(setting.chapters[2].recruitingText, '不限品类 · 0 家');
      expect(setting.canManage, isTrue);
      expect(setting.chapters[0].finished, isFalse);
      expect(
        TopicSetting.tryFromJson(<String, dynamic>{})!.canManage,
        isFalse,
        reason: '字段缺席不许当有权限',
      );
    });

    test('结束回执:人工单 > 退款单 > 无可退,失败场次照实说', () {
      const TopicEndResult manual = TopicEndResult(
        refundedOrders: 5,
        manualOrders: 2,
        failedSessions: <String>['9月20日 场次'],
      );
      expect(manual.summaryText, '2 笔需人工处理');
      expect(manual.hasFailures, isTrue);
      expect(
        const TopicEndResult(
          refundedOrders: 3,
          manualOrders: 0,
          failedSessions: <String>[],
        ).summaryText,
        '已结束，退款 3 笔',
      );
      expect(
        const TopicEndResult(
          refundedOrders: 0,
          manualOrders: 0,
          failedSessions: <String>[],
        ).summaryText,
        '已结束，无可退订单',
      );
    });
  });

  group('开放设置:回读缺字段 = 没保存成', () {
    test('ClubOpenSettings 三个字段缺一不可', () {
      expect(ClubOpenSettings.tryFromJson(<String, dynamic>{}), isNull);
      expect(
        ClubOpenSettings.tryFromJson(<String, dynamic>{
          'publicVisible': 1,
          'memberPostAllowed': 0,
        }),
        isNull,
      );
      final ClubOpenSettings ok = ClubOpenSettings.tryFromJson(
        <String, dynamic>{
          'publicVisible': 1,
          'memberPostAllowed': 0,
          'merchantUndertakeOpen': 1,
        },
      )!;
      expect(ok.publicVisible, isTrue);
      expect(ok.memberPostAllowed, isFalse);
      expect(ok.merchantUndertakeOpen, isTrue);
    });

    test('单个开关回读只认自己那个字段', () {
      expect(
        ClubOpenSettingValue.tryFromJson('publicVisible', <String, dynamic>{}),
        isNull,
      );
      expect(
        ClubOpenSettingValue.tryFromJson('publicVisible', <String, dynamic>{
          'memberPostAllowed': 1,
        }),
        isNull,
      );
      final ClubOpenSettingValue v = ClubOpenSettingValue.tryFromJson(
        'publicVisible',
        <String, dynamic>{'publicVisible': 0},
      )!;
      expect(v.key, 'publicVisible');
      expect(v.enabled, isFalse);
    });
  });

  group('招商台与成员名单', () {
    test('未确认商家不展示手机号,说的是「还没确认」', () {
      final RecruitOverviewNode unconfirmed = RecruitOverviewNode.tryFromJson(
        <String, dynamic>{'nodeId': 5, 'name': '城墙', 'merchantName': '甲店'},
      )!;
      expect(unconfirmed.confirmed, isFalse);
      expect(unconfirmed.maskedPhone, '');
      expect(unconfirmed.contactText, '未确认，暂无联系方式');

      final RecruitOverviewNode confirmed = RecruitOverviewNode.tryFromJson(
        <String, dynamic>{
          'nodeId': 6,
          'name': '钟楼',
          'merchantName': '乙店',
          'phone': '18000000000',
        },
      )!;
      expect(confirmed.maskedPhone, '180****0000');
      expect(confirmed.contactText, '180****0000');
    });

    test('OPEN 的站点还在招商,不进已承接名单', () {
      final RecruitOverview overview = RecruitOverview.tryFromJson(
        <String, dynamic>{
          'nodes': <Map<String, dynamic>>[
            <String, dynamic>{'nodeId': 1, 'name': 'A', 'state': 'OPEN'},
            <String, dynamic>{'nodeId': 2, 'name': 'B', 'state': 'ACCEPTED'},
          ],
        },
      )!;
      expect(overview.nodes.length, 2);
      expect(
        overview.undertaken.map((RecruitOverviewNode n) => n.nodeId),
        <int>[2],
      );
      expect(
        RecruitOverview.tryFromJson(<String, dynamic>{'nodes': '坏了'}),
        isNull,
      );
    });

    test('名单摊平:session 时间落到每一行,缺名字给「这位成员」', () {
      final TopicCustomers data = TopicCustomers.tryFromJson(<String, dynamic>{
        'soldCount': 12,
        'pendingCount': 5,
        'verifiedCount': 7,
        'sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'timeText': '9月20日 14:00',
            'rows': <Map<String, dynamic>>[
              <String, dynamic>{'key': 'u1', 'displayName': '阿明'},
            ],
          },
          <String, dynamic>{
            'rows': <Map<String, dynamic>>[
              <String, dynamic>{'displayName': ''},
            ],
          },
        ],
      })!;
      expect(data.rows.length, 2);
      expect(data.rows[0].timeText, '9月20日 14:00');
      expect(data.rows[0].initial, '阿');
      expect(data.rows[1].key, 's1-r0');
      expect(data.rows[1].displayName, '这位成员');
      expect(data.rows[1].timeText, '时间待定');
      expect(
        data.stats.map((({String text, String tone}) s) => s.text),
        <String>['已售 12', '待核销 5', '已核销 7'],
      );
    });
  });

  group('剧情与玩法陈列:buildTopicStoryChapters', () {
    test('无模板的站点只进路线不进玩法,序号跨章连续', () {
      final List<TopicStoryChapter> chapters = buildTopicStoryChapters(
        <TopicChapter>[
          _chapter(
            id: 1,
            title: '古城',
            totalTime: 200,
            nodes: <TopicNode>[
              _node(id: 11, name: '钟楼', businessTime: '09:00'),
              _node(
                id: 12,
                name: '城墙',
                template: TopicTemplate(
                  id: 101,
                  title: '登城答题',
                  validationMethod: 1,
                ),
              ),
            ],
          ),
          _chapter(
            id: 2,
            title: '夜市',
            nodes: <TopicNode>[
              _node(
                id: 21,
                name: '小吃街',
                template: TopicTemplate(
                  id: 201,
                  title: '找味道',
                  validationMethod: 0,
                ),
              ),
            ],
          ),
        ],
      );

      expect(chapters[0].title, '第一章 · 古城');
      expect(chapters[0].meta, '3h 20min · 2 站');
      expect(chapters[0].stops.map((TopicStoryStop s) => s.seq), <int>[1, 2]);
      expect(chapters[0].plays.length, 1);
      expect(chapters[0].plays.first.badge, '文字作答');
      expect(chapters[0].plays.first.hasAnswer, isTrue);
      expect(chapters[0].plays.first.meta, contains('第 2 站 城墙'));

      // 码 0 = 无需验证,玩法卡退化成单键并挂「· 无答案」。
      expect(chapters[1].plays.single.badge, '无需验证 · 无答案');
      expect(chapters[1].plays.single.hasAnswer, isFalse);
      expect(chapters[1].stops.single.seq, 3, reason: '序号跨章连续');
      expect(chapters[1].title, '第二章 · 夜市');
    });

    test('空章节不给时长,给「未开放 · 待招商」', () {
      final List<TopicStoryChapter> chapters = buildTopicStoryChapters(
        <TopicChapter>[_chapter(id: 1, title: '待招商', totalTime: 0)],
      );
      expect(chapters.single.meta, '未开放 · 待招商');
      expect(chapters.single.stops, isEmpty);
      expect(chapters.single.plays, isEmpty);
    });

    test('步行段只从章内第二站开始画', () {
      final List<TopicStoryChapter> chapters = buildTopicStoryChapters(
        <TopicChapter>[
          _chapter(
            id: 1,
            nodes: <TopicNode>[
              _node(id: 11, latitude: 31.2300, longitude: 121.4700),
              _node(id: 12, latitude: 31.2400, longitude: 121.4800),
            ],
          ),
        ],
      );
      expect(chapters.single.stops[0].walkText, '');
      expect(chapters.single.stops[1].walkText, endsWith('步行'));
    });

    test('模板标题缺席时落站点名,不落空卡', () {
      final List<TopicStoryChapter> chapters = buildTopicStoryChapters(
        <TopicChapter>[
          _chapter(
            id: 1,
            nodes: <TopicNode>[
              _node(
                id: 11,
                name: '钟楼',
                template: const TopicTemplate(
                  id: 101,
                  title: '',
                  validationMethod: 1,
                ),
              ),
            ],
          ),
        ],
      );
      expect(chapters.single.plays.single.title, '钟楼');
      expect(chapters.single.plays.single.templateId, 101);
    });
  });

  group('候补状态:玩家侧真状态,不许猜', () {
    Map<String, dynamic> raw({
      String state = 'NONE',
      String eligibility = 'ELIGIBLE',
      Object? joinAllowed = true,
      Object? id,
      Object? registrationId,
      String offerToken = '',
      String offerExpiresAt = '',
    }) => <String, dynamic>{
      'state': state,
      'eligibilityState': eligibility,
      'waitlistJoinAllowed': joinAllowed,
      if (id != null) 'id': id,
      if (registrationId != null) 'registrationId': registrationId,
      'offerToken': offerToken,
      'offerExpiresAt': offerExpiresAt,
    };

    test('两个字段不自洽 → 坏回执(null),不猜哪边是真的', () {
      expect(
        EventWaitlistStatus.tryFromJson(
          raw(eligibility: 'ELIGIBLE', joinAllowed: false),
        ),
        isNull,
      );
      expect(
        EventWaitlistStatus.tryFromJson(
          raw(eligibility: 'BLOCKED', joinAllowed: true),
        ),
        isNull,
      );
    });

    test('状态串 / eligibility 不在枚举里 → null', () {
      expect(EventWaitlistStatus.tryFromJson(raw(state: 'MYSTERY')), isNull);
      expect(
        EventWaitlistStatus.tryFromJson(raw(eligibility: 'MAYBE')),
        isNull,
      );
      expect(EventWaitlistStatus.tryFromJson(<String, dynamic>{}), isNull);
    });

    test('OFFERED 缺 token 或过期时间 → null;有 id 的状态缺 id → null', () {
      expect(
        EventWaitlistStatus.tryFromJson(
          raw(state: 'OFFERED', id: 9, offerExpiresAt: '2026-09-17T12:00:00'),
        ),
        isNull,
      );
      expect(EventWaitlistStatus.tryFromJson(raw(state: 'WAITING')), isNull);
      expect(
        EventWaitlistStatus.tryFromJson(
          raw(state: 'CLAIMED', id: 9, registrationId: 88),
        ),
        isNotNull,
      );
      expect(
        EventWaitlistStatus.tryFromJson(raw(state: 'CLAIMED', id: 9)),
        isNull,
      );
    });

    test('canJoin 是五条合取:满员 + ELIGIBLE + 放行 + 可重排 + 不忙', () {
      final EventWaitlistStatus status = EventWaitlistStatus.tryFromJson(
        raw(state: 'CANCELLED', id: 9),
      )!;
      expect(status.canJoin(ticketSoldOut: true), isTrue);
      expect(status.canJoin(ticketSoldOut: false), isFalse);
      expect(status.canJoin(ticketSoldOut: true, busy: true), isFalse);
      final EventWaitlistStatus waiting = EventWaitlistStatus.tryFromJson(
        raw(state: 'WAITING', id: 9),
      )!;
      expect(
        waiting.canJoin(ticketSoldOut: true),
        isFalse,
        reason: '已在队列里不能再排队',
      );
    });

    test('offerActive:过期 / 超 121 分钟上限 / 解析不了都 fail-closed', () {
      final DateTime now = DateTime(2026, 9, 17, 12, 0);
      EventWaitlistStatus offered(String expiresAt) =>
          EventWaitlistStatus.tryFromJson(
            raw(
              state: 'OFFERED',
              id: 9,
              offerToken: 't',
              offerExpiresAt: expiresAt,
            ),
          )!;
      expect(
        offered(
          now.add(const Duration(minutes: 30)).toIso8601String(),
        ).offerActive(now: now),
        isTrue,
      );
      expect(
        offered(
          now.subtract(const Duration(minutes: 1)).toIso8601String(),
        ).offerActive(now: now),
        isFalse,
      );
      expect(
        offered(
          now.add(const Duration(minutes: 200)).toIso8601String(),
        ).offerActive(now: now),
        isFalse,
        reason: '不能拿异常长的过期时间扩张付款窗口',
      );
      expect(offered('不是时间').offerActive(now: now), isFalse);
      expect(
        EventWaitlistStatus.tryFromJson(
          raw(state: 'WAITING', id: 9),
        )!.offerActive(now: now),
        isFalse,
      );
    });

    test('不可加入时的说明按 eligibility 分话术', () {
      String message(String eligibility) => EventWaitlistStatus.tryFromJson(
        raw(eligibility: eligibility, joinAllowed: false),
      )!.eligibilityMessage;
      expect(message('NOT_MEMBER'), '仅俱乐部正常成员可加入候补');
      expect(message('WAITLIST_CLOSED'), '本场候补已关闭');
      expect(message('ALREADY_REGISTERED'), '你已有该票种的有效报名');
      expect(message('NO_SERIES'), '本活动未配置候补');
      expect(message('BLOCKED'), '你当前无法参与该俱乐部');
    });
  });

  group('主理人看答案的回执', () {
    test('提示逐条过滤空串;题面/答案/反馈缺席是空串不是 null 崩', () {
      final TopicNodeAnswer answer = TopicNodeAnswer.tryFromJson(
        <String, dynamic>{
          'question': '这座塔建于哪一年？',
          'answerReveal': '1896',
          'hints': <Object?>['先看碑文', '', '  ', '再数楼层'],
          'feedbackText': '再想想',
        },
      )!;
      expect(answer.answerReveal, '1896');
      expect(answer.hints, <String>['先看碑文', '再数楼层']);
      final TopicNodeAnswer bare = TopicNodeAnswer.tryFromJson(
        <String, dynamic>{},
      )!;
      expect(bare.question, '');
      expect(bare.answerReveal, '');
      expect(bare.hints, isEmpty);
      expect(TopicNodeAnswer.tryFromJson(null), isNull);
    });
  });
}
