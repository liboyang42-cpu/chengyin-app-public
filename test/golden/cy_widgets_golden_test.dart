// 组件视觉快照(golden)。
//
// ★ 为什么需要:历史上 AMapFoundation 不支持 arm64 模拟器,App 跑不起来,
//   此前所有「UI 对齐」只能靠读代码判断,**没人真正看过渲染结果**。
//   golden test 是 headless 渲染,不需要模拟器 —— 这是当前唯一能
//   看到真实像素的途径。
//
// 生成/更新基准图:flutter test --update-goldens test/golden
// 之后基准图会落在 test/golden/goldens/ 下,可直接打开查看。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'golden_theme.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';

Widget _wrap(Widget child, {double width = 360}) {
  return MaterialApp(
    theme: goldenTheme(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.all(CyTokens.pageX),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('基础件总览', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(360, 620));
    await tester.pumpWidget(
      _wrap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CyPageTitle('我的票夹', subtitle: '探店日的票都在这里'),
            const CySectionTitle('区块标题'),
            SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                const CyChip(label: '全部', selected: true),
                SizedBox(width: CyTokens.space2),
                CyChip(label: '待使用', selected: false, onTap: () {}),
                SizedBox(width: CyTokens.space2),
                const CyChip(label: '禁用', selected: false),
              ],
            ),
            SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                const CyTag(label: '探店日'),
                SizedBox(width: CyTokens.space2),
                const CyTag(label: '品牌', brand: true),
                SizedBox(width: CyTokens.space4),
                const CyAvatar(fallback: '城', size: 40),
                SizedBox(width: CyTokens.space2),
                const CyBadge(count: 3),
                SizedBox(width: CyTokens.space2),
                const CyBadge(),
              ],
            ),
            SizedBox(height: CyTokens.space3),
            const Card(
              child: Column(
                children: <Widget>[
                  CyCell(title: '单行条目', subtitle: null),
                  CyCell(title: '双行条目', subtitle: '副标题说明文字'),
                ],
              ),
            ),
            SizedBox(height: CyTokens.space3),
            FilledButton(onPressed: () {}, child: const Text('主行动')),
            SizedBox(height: CyTokens.space2),
            OutlinedButton(onPressed: () {}, child: const Text('次要动作')),
            SizedBox(height: CyTokens.space2),
            const FilledButton(onPressed: null, child: Text('禁用态')),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/widgets_overview.png'),
    );
  });

  testWidgets('三态:空 / 骨架', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(360, 420));
    await tester.pumpWidget(
      _wrap(
        const StatusView(
          message: '还没有购买过的票',
          sub: '去首页报名探店日,买到的票会出现在这里。',
          icon: Icons.confirmation_number_outlined,
          large: true,
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/empty_state.png'),
    );

    // 骨架屏带呼吸动画,快照会取到随机帧 —— 不纳入 golden,
    // 它的正确性由「只画结构、不放占位文字」这条设计约束保证。
  });
}
