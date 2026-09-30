// fixture 造的是**语义边界**不是漂亮数据:已到店未核销(arrived=true、done=false)+
// 有 npc + 有 perk + hasGame:true + ruleInstructions 三条 + requiredMaterials +
// 有坐标 + 有 openStatus + businessTime,
// 让五段(章节头/小瘾说 · 店铺卡+导航行 · 游戏 · 到店三步 · 本店权益)一屏之内齐全。
// ★ arrived 与 done 是**两步**:叙事段(硬闸 visibleFor)只认 arrived,
//   常态必须 arrived=true、done=false;第二张才把 done 也置 true。
// 第二张钉「已核销态」:arrived/selfReported/done 全 true ⇒ 三步全绿、CTA 禁用、卡片整张灰掉。
//
// CardDetailPage 按 sessionKey+nodeId 从 playSessionProvider 现读节点,不接快照——
// 所以喂数据走 override playApiProvider(假 PlayApi 返回 fixture),让真 controller 跑。
// 照抄 test/feature/play/free_explore_onsite_progress_test.dart 的假 API 写法。
//
// 更新基准图:flutter test --update-goldens test/golden/page_free_explore_detail_golden_test.dart
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

const PlaySessionKey _key = (activityId: 55, topicId: null);

class _Api implements PlayApi {
  _Api(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ★ fixture 喂的是 `/api/play/nodes` 的**原始 JSON**,整条走 PlayNodesResult.fromJson。
/// 用构造函数直接造模型对象会绕过解析层,后端键名与模型对不上就完全隐形 ——
/// duration(第 2 轮)与章节 meta/title/cover(第 3 轮)都是这么漏出去的。
/// 章节键照后端:name / imgArr / description / audioUrl,**没有** meta/title/cover;
/// 眉标「第 N 章」按数组下标生成,所以这里摆两章,让本节点落在第 2 章。
Map<String, dynamic> _payload({required bool arrived, required bool done}) {
  return <String, dynamic>{
    'topicId': 9,
    'mode': 2,
    'playable': true,
    'total': 4,
    'doneCount': done ? 1 : 0,
    'chapters': <dynamic>[
      <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
      <String, dynamic>{'chapterId': 200, 'name': '旧书与唱片'},
    ],
    'nodes': <dynamic>[
      <String, dynamic>{
        'nodeId': 12,
        'name': '长乐路旧物店',
        'address': '长乐路 88 号',
        'sortId': 2,
        'done': done,
        'longitude': 121.45,
        'latitude': 31.21,
        'imgUrl': 'https://picsum.photos/seed/fx-detail/600/800',
        'merchantId': 71,
        // ★ arrived 与 done 是两步:叙事常态是「已到店未核销」
        //   (arrived=true、done=false),硬闸 visibleFor 只认 arrived。
        'arrived': arrived,
        'selfReported': done,
        'hookText': '老板收唱片二十年,最爱聊六七十年代的爵士。',
        'businessTime': '11:00-20:00',
        'openStatus': '营业中',
        'chapterId': 200,
        'npc': <String, dynamic>{'name': '阿旧', 'greeting': '欢迎光临,随便挑挑。'},
        'perk': <String, dynamic>{
          'name': '一张黑胶唱片九折',
          'redeemRule': '出示卡片,店内任选一张黑胶享九折',
          // ★ 后端真实形状:CoopPerk.validEnd 是 @JsonFormat(pattern="yyyy-MM-dd") 的
          //   Date,只发日期、不带时区。原来写成带 Z 的 ISO 时刻是自造形状,
          //   配上当时用 toLocal() 的格式化,在这台 PDT 机器上把「12/30」烤进了基线。
          'validEnd': '2026-12-31',
        },
        'hasGame': true,
        'gameTitle': '猜年代小游戏',
        // 叙事钩子:到店后节点下发的 storyText,GameSection 叙事优先展示它。
        'storyText': '阿旧收唱片二十年,每一张黑胶背后都藏着一段城市记忆。',
        'duration': 10,
        'difficulty': '简单',
        'players': '1 人',
        'requiredMaterials': '一双耳朵',
        'ruleInstructions': '店主放一段唱片\n猜出发行年代所在的十年\n答对得一枚探索值',
      },
    ],
  };
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> payload) async {
  final _Api api = _Api(payload);
  // 不还原尺寸会渗到同一批次里后跑的别的测试(card_detail_page_test 那条就写了)。
  setGoldenViewport(tester, const Size(390, 1900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: const CardDetailPage(
          sessionKey: _key,
          nodeId: 12,
          onPrimary: _noop,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop(PlayNode node) {}

void main() {
  testWidgets('★ 卡片详情常态:已到店未核销 · npc/perk/游戏/坐标齐全', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _payload(arrived: true, done: false));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_detail.png'),
    );
  });

  testWidgets('★ 卡片详情已核销态:三步全绿 · CTA 禁用 · 卡片整张灰掉', (WidgetTester tester) async {
    await _pump(tester, _payload(arrived: true, done: true));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_detail_done.png'),
    );
  });
}
