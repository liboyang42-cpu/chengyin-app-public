// Wave-B 玩法说明(B35/B36 列表 · B37/B38/B39 详情)与模板( B45 引导 ·
// B46 命名 · B57/B58 详情)。
//
// 每条都对小程序 shot-matrix 的 state:
//   · B36 是**资讯为空**态 —— 页面把整块「了解更多」藏掉,不留一个空标题分区。
//   · B39 是**缺参**态(id<=0):不拉接口、只给「返回玩法列表」一个出口(零假重试)。
//   · B38/B58 是 loading:provider 永不完成,骨架/转圈才是真画面。
//   · B45 的卡片可以缺省(真源同样不拦创建),所以只喂 1 张卡也能拍。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_wave_b_guide_template_golden_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/infomation.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/feature/account/infomation_detail_page.dart';
import 'package:chengyin_app/feature/account/play_guide_page.dart';
import 'package:chengyin_app/feature/template/template_detail_page.dart';
import 'package:chengyin_app/feature/template/template_intro_page.dart';
import 'package:chengyin_app/feature/template/template_name_page.dart';

import 'golden_theme.dart';

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

Future<void> _shot(WidgetTester tester, String goldenPath) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

const Infomation _guide1 = Infomation(
  id: 1,
  title: '第一次玩怎么开始',
  subtitle: '从挑玩法到出发只要三步',
  contents: '选一种玩法,买票或开通行证,到了点位按提示打卡。',
);

const Infomation _guide2 = Infomation(
  id: 2,
  title: '72小时城市漫游',
  subtitle: '慢慢走也算数',
  contents: '漫游没有终点,点亮城市迷雾就是你的记录。',
);

PlayTemplate _template() => const PlayTemplate(
  id: 1,
  title: '城市线索路线',
  description: '沿外滩寻找建筑细节,一路走一路解。',
  players: '2-6',
  duration: 90,
  difficulty: '轻松',
  ruleInstructions: '按顺序到访每个点位,到点后在点位页打卡。',
  requiredMaterials: '一台能扫码的手机',
  usageLocation: '外滩源一带',
  validationMethod: 1,
  storyText: '这条路是给晚上有空的人写的。',
);

void main() {
  testWidgets('B35 玩法说明:资讯列表', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationsProvider.overrideWith(
          (Ref ref) async => <Infomation>[_guide1, _guide2],
        ),
      ], const PlayGuidePage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('了解更多'), findsOneWidget);
    await _shot(tester, 'goldens/page_play_guide_list.png');
  });

  testWidgets('B36 玩法说明:资讯为空 → 三态之一(标题仍在 + 空态文案)', (
    WidgetTester tester,
  ) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationsProvider.overrideWith((Ref ref) async => <Infomation>[]),
      ], const PlayGuidePage()),
    );
    await tester.pumpAndSettle();
    // main #191 起标题恒显、空态出「暂无玩法说明」(对齐真源 infomation.wxml:68-80,
    // 旧行为是整块静默消失);本断言随 main 更新,基线一并重录。
    expect(find.text('了解更多'), findsOneWidget);
    expect(find.text('暂无玩法说明'), findsOneWidget);
    await _shot(tester, 'goldens/page_play_guide_empty.png');
  });

  testWidgets('B37 玩法详情:正文', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationDetailProvider(1).overrideWith((Ref ref) async => _guide1),
      ], const InfomationDetailPage(id: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一次玩怎么开始'), findsOneWidget);
    await _shot(tester, 'goldens/page_infomation_detail.png');
  });

  testWidgets('B38 玩法详情:加载中', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        infomationDetailProvider(
          1,
        ).overrideWith((Ref ref) => Completer<Infomation>().future),
      ], const InfomationDetailPage(id: 1)),
    );
    await tester.pump();
    await _shot(tester, 'goldens/page_infomation_detail_loading.png');
  });

  testWidgets('B39 玩法详情:缺参(id<=0)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[], const InfomationDetailPage(id: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('返回玩法列表'), findsOneWidget);
    await _shot(tester, 'goldens/page_infomation_detail_missing_param.png');
  });

  testWidgets('B45 模板创建引导:带推荐卡', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        templateIntroCardsProvider.overrideWith(
          (Ref ref) async => <PublishTemplate>[
            PublishTemplate(
              id: 1,
              title: '经典定向',
              imgUrl: '',
              players: '2-6',
              duration: 90,
              raw: <String, dynamic>{'rule_instructions': '按顺序走完所有点位。'},
            ),
          ],
        ),
      ], const TemplateIntroPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('把你玩过的一段路'), findsOneWidget);
    await _shot(tester, 'goldens/page_template_intro.png');
  });

  testWidgets('B46 模板命名页', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(<dynamic>[], const TemplateNamePage()));
    await tester.pumpAndSettle();
    await _shot(tester, 'goldens/page_template_name.png');
  });

  testWidgets('B57 模板详情:正文', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        templateDetailProvider(1).overrideWith((Ref ref) async => _template()),
      ], const TemplateDetailPage(id: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('规则说明'), findsOneWidget);
    await _shot(tester, 'goldens/page_template_detail.png');
  });

  testWidgets('B58 模板详情:加载中', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(<dynamic>[
        templateDetailProvider(
          1,
        ).overrideWith((Ref ref) => Completer<PlayTemplate>().future),
      ], const TemplateDetailPage(id: 1)),
    );
    await tester.pump();
    await _shot(tester, 'goldens/page_template_detail_loading.png');
  });
}
