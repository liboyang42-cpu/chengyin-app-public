import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

TopicDetail _fixture() => TopicDetail.fromJson(<String, dynamic>{
  'id': 12,
  'name': '静安微旅行',
  'subtitle': '沿着城市的隐秘线索往前走',
  'description': '一条连接老建筑与新生活的路线。',
  'imgUrl': 'https://example.com/cover.jpg',
  'imgArr': 'https://example.com/a.jpg,https://example.com/b.jpg',
  'averageRating': 4.4,
  'totalTime': 5400,
  'startDate': '2026-08-01 00:00:00',
  'endDate': '2026-10-07 00:00:00',
  'totalMileage': 6.8,
  'registrationMerchantCount': 1,
  'audioUrl': 'https://example.com/guide.mp3',
  'audioDuration': 88,
  'locationCount': 1,
  'templateCount': 1,
  'productType': 2,
  'perkSellableCapacity': 30,
  'omsTicketList': <dynamic>[
    <String, dynamic>{
      'id': 99,
      'name': '周六午后场',
      'startTime': '2026-09-05 14:00:00',
      'endTime': '2026-09-05 17:00:00',
      'meetingPoint': '静安公园南门',
      'refundRule': '出发前 24 小时可退',
      'price': 69,
      'remainingInventory': 8,
    },
  ],
  'commentList': <dynamic>[
    <String, dynamic>{
      'memberNickname': '小夏',
      'createTime': '2026-08-20',
      'rating': 5,
      'contents': '路线节奏很好。',
    },
  ],
  'chaptersList': <dynamic>[
    <String, dynamic>{
      'id': 1,
      'name': '第一章 · 梧桐深处',
      'description': '从公园走到老弄堂',
      'nodes': <dynamic>[
        <String, dynamic>{
          'id': 3,
          'name': '静安公园',
          'description': '从这里开始',
          'address': '南京西路 1649 号',
          'latitude': 31.223,
          'longitude': 121.445,
          'businessTime': '全天开放',
          'cmsMemberTemplate': <String, dynamic>{
            'id': 31,
            'title': '寻找建筑细节',
            'players': '1-4 人',
            'duration': 15,
          },
          'registrationMerchantList': <dynamic>[
            <String, dynamic>{
              'memberId': 55,
              'mmsMerchant': <String, dynamic>{
                'name': '巷口咖啡',
                'businessTime': '10:00-20:00',
              },
            },
          ],
        },
      ],
    },
  ],
});

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(12).overrideWith((ref) async => _fixture()),
      ].cast(),
      child: const MaterialApp(home: TopicDetailPage(topicId: 12)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('路线详情使用 Apple 原生一级导航且保留页内大标题', (tester) async {
    await _pump(tester);

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.text('路线详情'), findsOneWidget);
  });

  test('详情读模型保留小程序五项指标、场次、玩法、品牌与评价', () {
    final detail = _fixture();
    expect(detail.averageRating, 4.4);
    expect(detail.totalHoursText, '1.5');
    expect(detail.openPeriodText, '8.1-10.7');
    expect(detail.totalMileage, 6.8);
    expect(detail.tickets.single.sessionTimeText, '09-05 14:00–17:00');
    expect(detail.chapters.single.nodes.single.template?.title, '寻找建筑细节');
    expect(detail.merchants.single.name, '巷口咖啡');
    expect(detail.comments.single.contents, '路线节奏很好。');
  });

  testWidgets('首屏指标与详情模块顺序完整，保留三视图', (tester) async {
    await _pump(tester);

    expect(find.text('评价'), findsOneWidget);
    expect(find.text('预计探索'), findsOneWidget);
    expect(find.text('开放时间'), findsOneWidget);
    expect(find.text('总里程'), findsOneWidget);
    expect(find.text('参与商家'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('路线节点'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('主题音频讲解'), findsOneWidget);
    expect(find.text('节点介绍'), findsOneWidget);
    expect(find.text('场次'), findsOneWidget);
    expect(find.text('阵容/商家'), findsOneWidget);
    expect(find.text('投票'), findsOneWidget);
    expect(find.textContaining('路线节奏很好。'), findsOneWidget);
  });

  testWidgets('路线节点视图含地图预览与节点说明，路线视图保留地点卡', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('路线节点'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topic-route-map')), findsOneWidget);
    expect(find.textContaining('从这里开始'), findsOneWidget);
    expect(find.text('寻找建筑细节'), findsOneWidget);

    await tester.tap(find.text('路线'));
    await tester.pumpAndSettle();
    expect(find.textContaining('全天开放'), findsOneWidget);
    expect(find.textContaining('南京西路 1649 号'), findsOneWidget);
  });
}
