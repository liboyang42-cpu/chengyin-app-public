// 买票主链三页的整页视觉快照(活动列表 / 活动详情 / 主题详情)。
//
// ★ 为什么值得拍:组件快照只证明「零件」对,证明不了整页布局对 —— 卡与卡
//   的间距节奏、长标题截断、封面兜底、底部报名条的主次比例(1:2)只有整页
//   渲染才看得出来,而这正是玩家买票的必经路径。
//
// ★ 封面怎么进快照:测试环境禁网,Image.network 直接走 errorBuilder 会全屏
//   兜底,「有封面」与「无封面」在快照里无法分辨。这里先把内存 PNG 预填进
//   ImageCache(NetworkImage 的 key 按 url 相等,Image.network 命中缓存即出图、
//   不发请求),让两种状态真实可辨。
//
// ★ 主题走 golden_theme.dart 的 [goldenTheme] 而不是 AppTheme.dark():按钮的
//   textStyle 是裸 TextStyle(family=null),测试环境回退内置测试字体 ⇒ 按钮文案
//   会全是方框,看不出超长中文有没有撑爆。真机上 null 走系统字体本就正确,
//   所以那是测试环境缺陷,补在测试侧、不动 lib/。详见 golden_theme.dart。
//
// 更新基准图:flutter test --update-goldens test/golden

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

// 假封面 url:只在 ImageCache 里存在,不会真发网络请求。
const String _coverA = 'https://cdn.chengyinhub.com/covers/list-a.jpg';
const String _coverB = 'https://cdn.chengyinhub.com/covers/list-b.jpg';
const String _coverC = 'https://cdn.chengyinhub.com/covers/list-c.jpg';
const String _coverT = 'https://cdn.chengyinhub.com/covers/topic-a.jpg';

/// 把一张纯色内存图以 [url] 为 key 预填进 ImageCache。
/// 之后该 url 的 Image.network 命中缓存直接出图,不进网络、不落 errorBuilder。
///
/// ⚠️ 为什么用 Picture.toImage 而不是生成 PNG 再解码:`ImmutableBuffer.fromUint8List`
/// 走真实异步解码路径,在 testWidgets 的 FakeAsync 区里永不完成(实测挂死)。
/// Picture.toImage 则直接产出 ui.Image,绕开解码,快照里呈现为一块纯色封面。
Future<void> _seedCover(String url, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, 48, 36),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(48, 36);
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image, scale: 1.0)),
    ),
  );
}

// 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,
// 这里靠推断即可,少一个 import 少一处版本耦合。
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

void main() {
  testWidgets('买票主链·活动列表:4 卡含超长标题与无封面', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 1700));
    await _seedCover(_coverA, const Color(0xFF2F4A6B));
    await _seedCover(_coverB, const Color(0xFF5B3A6B));
    await _seedCover(_coverC, const Color(0xFF3A6B4F));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          activityListProvider.overrideWith((ref) async => <Activity>[
            Activity(
              id: 1,
              name: '静安探店日 · 第一期',
              status: 2,
              description: '和一群陌生人一起探索静安的小马路',
              imgUrl: _coverA,
              addressName: '静安寺地铁站 1 号口',
              minAmount: 49.9,
              startDate: '2026-08-24 14:00:00',
            ),
            Activity(
              id: 2,
              name: '一个特别特别长的活动标题用来检验卡片标题是否单行截断并正确显示省略号且不会溢出布局',
              status: 3,
              description: '超长标题配超长副标题也要一行截断,检验副标题的省略处理是否正确',
              imgUrl: _coverB,
              addressName: '长乐路',
              minAmount: null,
              startDate: '2026-08-24 14:00:00',
            ),
            // 无封面:imgUrl 为 null,应走 .cover-error 兜底。
            Activity(
              id: 3,
              name: '徐汇滨江夜跑 · 免费场',
              status: 2,
              description: '无封面活动,应显示封面兜底占位',
              address: '徐汇滨江步道',
              minAmount: 0,
              startDate: '2026-08-24 14:00:00',
            ),
            Activity(
              id: 4,
              name: '普陀夜市寻味',
              status: 2,
              description: '夜市专场,有起价',
              imgUrl: _coverC,
              addressName: '环球港北广场',
              minAmount: 99.0,
              startDate: '2026-08-24 14:00:00',
            ),
          ]),
        ],
        // ★ now 必须注入固定值:三档判据(F1 修复)是拿 startDate/endDate 跟
        //   「现在」比的。不注入的话这张基准图会随日子漂 —— fixture 的活动哪天
        //   从「进行中」滑走,基线就自己红一次,和代码无关。
        ActivityListPage(now: DateTime(2026, 9, 1)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_buy_activity_list.png'),
    );
  });

  testWidgets('买票主链·活动详情:封面 + 元信息 + 票种 + 底部条', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 940));
    await _seedCover(_coverA, const Color(0xFF2F4A6B));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          // ★ 显式声明这张基线渲染的是**未持票**的人:底部条因此只有主行动,
          //   没有「开始游玩」(那个按钮只对持有该活动有效票的人显示)。
          //   不 override 的话会打到真 dio,在测试环境抛 MissingPluginException。
          myJoinedActivitiesProvider.overrideWith(
            (ref) async => <MyRegistration>[],
          ),
          activityDetailProvider(7).overrideWith(
            (ref) async => ActivityDetail(
              id: 7,
              name: '静安探店日 · 第一期',
              description: '跟着城市地图,穿过弄堂与梧桐,在街角的咖啡店、面馆和书店里,'
                  '完成一整天的探店收集。\n全程约 6 小时,适合第一次来静安的人。',
              imgUrl: _coverA,
              addressName: '静安寺地铁站',
              address: '南京西路 1601 号',
              registrationCount: 128,
              viewCount: 356,
              commentCount: 12,
              tickets: <ActivityTicket>[
                ActivityTicket(id: 11, name: '早鸟单人票', price: 49.9),
                ActivityTicket(id: 12, name: '双人同行票', price: 88),
              ],
            ),
          ),
        ],
        const ActivityDetailPage(activityId: 7),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_buy_activity_detail.png'),
    );
  });

  testWidgets('买票主链·主题详情:封面 + 名称 + 简介 + 章节节点', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 840));
    await _seedCover(_coverT, const Color(0xFF6B4A2F));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          topicDetailProvider(21).overrideWith(
            (ref) async => TopicDetail(
              id: 21,
              name: '城市漫步 · 静安微旅行',
              introduction: '用一天的时间,沿着梧桐树荫走过静安寺、愚园路与巨鹿路,'
                  '收集散落街角的故事。',
              picUrl: _coverT,
              chapters: <TopicChapter>[
                TopicChapter(
                  id: 211,
                  title: '第一章 · 晨·静安寺',
                  nodes: <TopicNode>[
                    TopicNode(id: 2111, name: '静安寺地铁站'),
                    TopicNode(id: 2112, name: '静安公园'),
                  ],
                ),
                TopicChapter(
                  id: 212,
                  title: '第二章 · 午·愚园路',
                  nodes: <TopicNode>[
                    TopicNode(id: 2121, name: '愚园路 1088 弄'),
                    TopicNode(id: 2122, name: '钱学森旧居'),
                    TopicNode(id: 2123, name: '江苏路地铁站'),
                  ],
                ),
              ],
            ),
          ),
        ],
        const TopicDetailPage(topicId: 21),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_buy_topic_detail.png'),
    );
  });

  testWidgets('买票主链·主题详情:章节为空(空态兜底)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 700));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          topicDetailProvider(22).overrideWith(
            (ref) async => TopicDetail(
              id: 22,
              name: '筹备中的新路线',
              picUrl: null,
              chapters: <TopicChapter>[],
            ),
          ),
        ],
        const TopicDetailPage(topicId: 22),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_buy_topic_empty.png'),
    );
  });

  testWidgets('买票主链·活动列表:我报名的(状态胶囊)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 1340));
    await _seedCover(_coverB, const Color(0xFF5B3A6B));
    await tester.pumpWidget(
      _app(
        <dynamic>[
          // 初始 tab 是「全部活动」,依赖 activityListProvider;不 override 会
          // 走真实网络 → 永久 loading → CySkeleton 呼吸动画 → pumpAndSettle 永不落。
          activityListProvider.overrideWith((ref) async => <Activity>[]),
          myJoinedActivitiesProvider.overrideWith((ref) async => <MyRegistration>[
            MyRegistration.fromJson(<String, dynamic>{
              'id': 51,
              'ownerType': 2,
              'ownerId': 7,
              'registrationStatus': 2,
              'verificationStatus': 0,
              'participateDate': '2026-08-24 14:00',
              'cmsActivity': <String, dynamic>{
                'name': '静安探店日 · 第一期',
                'imgUrl': _coverB,
                'productType': 2,
              },
            }),
            MyRegistration.fromJson(<String, dynamic>{
              'id': 52,
              'ownerType': 2,
              'ownerId': 8,
              'registrationStatus': 1,
              'verificationStatus': 0,
              'participateDate': '2026-08-30 10:00',
              'cmsActivity': <String, dynamic>{
                'name': '徐汇咖啡巡礼 · 待支付',
                'productType': 2,
              },
            }),
            MyRegistration.fromJson(<String, dynamic>{
              'id': 53,
              'ownerType': 2,
              'ownerId': 9,
              'registrationStatus': 2,
              'verificationStatus': 1,
              'participateDate': '2026-08-10 15:00',
              'cmsActivity': <String, dynamic>{
                'name': '普陀夜市寻味',
                'imgUrl': _coverB,
                'productType': 2,
              },
            }),
          ]),
        ],
        ActivityListPage(now: DateTime(2026, 9, 1)),
      ),
    );
    await tester.pumpAndSettle();
    // 四档对齐小程序 tabs(进行中/即将/已结束/我的)后,这一档从「我报名的」改叫「我的」。
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_buy_activity_joined.png'),
    );
  });
}
