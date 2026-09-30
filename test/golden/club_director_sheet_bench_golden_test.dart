// a5-ios27-director-96 外观取证 bench:导演台 sheet 族呈现基线。
//
// ★ 为什么钉这张:执行机磁盘 avail <20Gi 起不了模拟器,真机/模拟器截图这条路
//   走不通。按 a5-ios27-configurator(PR #413)/ team-marker-95(bench295c)先例,
//   用「可入库 bench」离屏渲染取视觉证据(回执≠观测,但无图更不算验证)。
//
// 这里只渲导演台**纯展示层**(SheetFrame / RowList / Chips / SectionTitle /
// TextField / UnknownBar)—— 用静态数据喂,不挂 clubDirectorProvider,
// 与写状态机/push 接线解耦(那部分由 club_director_*_test.dart 覆盖)。
// 覆盖本轮两处外观补差:UnknownBar 两枚安全出口钮的 44pt 热区、
// RowList 的 warning/muted 值色与 details 三行。
//
// 更新基准:flutter test --update-goldens test/golden/club_director_sheet_bench_golden_test.dart

import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_director_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

void main() {
  testWidgets('导演台 sheet 族:展示层材质/值色/热区基线', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 844));
    final TextEditingController reason = TextEditingController(
      text: '现场站点临时管控，玩家已到齐',
    );

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const ClubDirectorSectionTitle('选择成员'),
        const ClubDirectorRowList(
          rows: <ClubDirectorRow>[
            ClubDirectorRow(
              id: '1:11',
              title: '阿哲',
              subtitle: '领队 · 已确认',
              value: '正常推进',
            ),
            ClubDirectorRow(
              id: '2:22',
              title: '第二队',
              subtitle: '卡在第 3 站',
              value: '异常',
              valueTone: 'warning',
              details: <ClubDirectorRowDetail>[
                (label: '卡点节点', text: '南京西路'),
                (label: '提示层级', text: '二级提示'),
                (label: '最近有效事件', text: '待确认'),
              ],
            ),
            ClubDirectorRow(
              id: '3:33',
              title: '小满',
              subtitle: '未分配角色',
              value: '未接受',
              valueTone: 'muted',
            ),
          ],
          selectable: true,
          selectedId: '1:11',
        ),
        const ClubDirectorSectionTitle('分配固定角色'),
        ClubDirectorChips(
          options: const <({String id, String label})>[
            (id: 'LEADER', label: '领队'),
            (id: 'MEDIC', label: '医疗'),
            (id: 'CAMERA', label: '摄影'),
          ],
          value: 'MEDIC',
          onChanged: (_) {},
        ),
        ClubDirectorTextField(
          controller: reason,
          label: '现场原因（必填）',
          placeholder: '写明为什么要手动解锁，会进审计记录',
        ),
        ClubDirectorUnknownBar(
          state: const ClubDirectorState(
            activityId: 1,
            writeState: ClubDirectorWriteState.unknownWrite,
            writeMessage: '结果待核对，请勿重复操作',
            canRetryUnknownWrite: true,
          ),
          onReconcile: () {},
          onRetry: () {},
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ClubDirectorSheetFrame(
              title: '角色分配',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  0,
                  CyTokens.pageX,
                  CyTokens.space5,
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_director_sheet_bench.png'),
    );
  });
}
