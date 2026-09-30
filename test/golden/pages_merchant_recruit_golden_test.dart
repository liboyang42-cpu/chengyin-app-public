// 商家招商承接链路的整页快照。
//
// ★ 逻辑和文案都验过了,但"长什么样"没验 —— 本轮新建的三个页面
//   (承接页 / 报名编辑 / 主办方审申请)一张图都还没看过。
//
// ★★ 必须用 merchantGoldenTheme:这三条路由都包了 _merchantLight,
//   用暗色主题拍出来的是**没人会看到的画面**,基准图会变成假证据。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_merchant_recruit_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/chapter_application.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_state.dart';
import 'package:chengyin_app/feature/merchant/merchant_registration_edit_page.dart';
import 'package:chengyin_app/feature/merchant/topic_chapter_applications_page.dart';
import 'golden_theme.dart';

const int kTopic = 42;

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: merchantGoldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(
    WidgetTester tester, Widget app, String goldenPath,
    // ★ 只有需要多摆一张点位卡的那条用例调高:整页是可滚动的,
    //   画布矮了会把最后一行场次裁掉 —— 那条"人数未知 ≠ 0 人"本来就是
    //   故意摆上去给人看的。别为了省事把四条用例一起改高(会平白换掉四张图)。
    {Size size = const Size(390, 1100)}) async {
  setGoldenViewport(tester, size);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

RecruitChapter _chapter() => RecruitChapter.fromJson(<String, dynamic>{
      'id': 7,
      'name': '第一章 · 咖啡与街角',
      'category': '咖啡',
      'required': 1,
      'recruitStatus': <String, dynamic>{
        'termsMode': 'PERK',
        'perkMinValue': 30,
        'maxMerchant': 4,
        'remainingMerchantCount': 2,
        'allowedValidationMethods': '1,4',
        'maxNodeXp': 30,
        'state': 'OPEN',
      },
    });

void main() {
  testWidgets('商家承接页:章节承接(有申请、有点位、有场次)',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          merchantRecruitProvider(kTopic).overrideWith((ref) async =>
              RecruitState(
                mode: RecruitMode.chapterRecruit,
                topicName: '梧桐区寻味',
                chapters: <RecruitChapter>[_chapter()],
                applications: <ChapterApplication>[
                  ChapterApplication.fromJson(<String, dynamic>{
                    'id': 100,
                    'topicId': kTopic,
                    'chapterId': 7,
                    'chapterName': '第一章 · 咖啡与街角',
                    'status': 1,
                  }),
                ],
                nodes: <MyChapterNode>[
                  // ★ 已通过的点位才摆两张码 —— 现场码(出示给玩家扫,秒级过期)
                  //   与海报码(贴店里长期用,可存相册)是**两张不同的码**,
                  //   端点也各是各的。驳回的点位摆一张扫了没用的码,
                  //   只会让商家以为现场已经能接待了。
                  MyChapterNode.fromJson(<String, dynamic>{
                    'id': 6,
                    'name': '静安咖啡',
                    'address': '南京西路 88 号',
                    'nodeAuditStatus': 1,
                  }),
                  MyChapterNode.fromJson(<String, dynamic>{
                    'id': 5,
                    'name': '南京西路店',
                    'address': '南京西路 1 号 2 层',
                    'nodeAuditStatus': 2,
                    'nodeAuditReason': '门头照太糊,换一张白天拍的',
                  }),
                ],
              )),
          merchantUpcomingRunsProvider(kTopic).overrideWith(
              (ref) async => <UpcomingRun>[
                    UpcomingRun.fromJson(<String, dynamic>{
                      'ticketId': 1,
                      'startTime': '2026-08-22 10:00:00',
                      'clubName': '夜行者俱乐部',
                      'paidCount': 8,
                      'teamStatus': 'FORMED',
                      'nodeOrder': 3,
                      'nodeTotal': 5,
                      'arrivalStart': '2026-08-22 14:00:00',
                      'arrivalEnd': '2026-08-22 15:30:00',
                    }),
                    // ★ 第二行故意缺人数与到店窗口 —— 图上要能看出
                    //   「人数未知」和「0 人」长得不一样。
                    UpcomingRun.fromJson(<String, dynamic>{
                      'ticketId': 2,
                      'startTime': '2026-08-23 09:30:00',
                    }),
                  ]),
        ],
        const MerchantRecruitPage(topicId: kTopic),
      ),
      'goldens/merchant_recruit_chapters.png',
      size: const Size(390, 1290),
    );
  });

  testWidgets('商家承接页:经典定向报名(没查出报没报过)',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          merchantRecruitProvider(kTopic).overrideWith((ref) async =>
              RecruitState(
                mode: RecruitMode.nodeRegistration,
                topicName: '老城厢定向',
                registered: null,
                topicChapters: <TopicChapter>[
                  TopicChapter(id: 1, title: '第一章', nodes: <TopicNode>[
                    TopicNode(id: 11, name: '豫园东门'),
                    TopicNode(id: 12, name: '福佑路口'),
                  ]),
                ],
              )),
          merchantUpcomingRunsProvider(kTopic)
              .overrideWith((ref) async => <UpcomingRun>[]),
        ],
        const MerchantRecruitPage(topicId: kTopic),
      ),
      'goldens/merchant_recruit_node_registration.png',
    );
  });

  testWidgets('报名编辑页:被驳回,表单已填满', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          merchantRegistrationDetailProvider(9).overrideWith((ref) async =>
              MerchantRegistrationDetail.fromJson(<String, dynamic>{
                'id': 9,
                'topicId': kTopic,
                'topicName': '梧桐区寻味',
                'nodeName': '第三站 · 街角',
                'status': 2,
                'reason': '现场图看不出可用空间,补一张全景',
                'addressName': '南京西路店',
                'address': '南京西路 1 号 2 层',
                'longitude': '121.4552',
                'latitude': '31.2304',
                'activityDesc': '二层有 20 个位子,可闭店 2 小时,允许拍摄。',
                'limitNum': 20,
                'picUrl': 'https://example.com/a.jpg',
              })),
        ],
        const MerchantRegistrationEditPage(registrationId: 9),
      ),
      'goldens/merchant_registration_edit.png',
    );
  });

  testWidgets('主办方:章节承接申请待审', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          topicChapterApplicationsProvider(kTopic)
              .overrideWith((ref) async => <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 1,
                      'merchantName': '拐角咖啡',
                      'chapterName': '第一章 · 咖啡与街角',
                      'status': 0,
                      'source': 0,
                      'message': '我们二层可以闭店配合,周末客流大',
                    },
                    <String, dynamic>{
                      'id': 2,
                      'merchantName': '小满花店',
                      'chapterName': '第二章 · 巷弄',
                      'status': 1,
                      'source': 1,
                    },
                    // ★ 状态没下发的一行:图上要能看出它「状态未知」且没有按钮。
                    <String, dynamic>{
                      'id': 3,
                      'merchantName': '旧书阁',
                      'chapterName': '第三章 · 旧物',
                    },
                  ]),
          invitableMerchantsProvider(kTopic)
              .overrideWith((ref) async => <Map<String, dynamic>>[]),
        ],
        const TopicChapterApplicationsPage(topicId: kTopic),
      ),
      'goldens/merchant_chapter_applications_owner.png',
    );
  });
}
