import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_gap_logic.dart';

PlayNode _node({bool arrived = false, bool selfReported = false, bool done = false}) =>
    PlayNode.fromJson(<String, dynamic>{
      'nodeId': 1, 'name': 'x', 'address': '', 'sortId': 1,
      'arrived': arrived, 'selfReported': selfReported, 'done': done,
    });

void main() {
  test('三步的文案与顺序固定', () {
    final s = onsiteSteps(_node());
    expect(s.map((e) => e.title).toList(), <String>[
      '扫描门店码 · 记录到店时间',
      '拍摄现场凭证 · 到店后显示拍摄要求',
      '商家核销 · 核销那一刻才算服务开始',
    ]);
  });

  test('亮灯与 arrived/selfReported/done 一一对应', () {
    expect(onsiteSteps(_node()).map((e) => e.done).toList(), <bool>[false, false, false]);
    expect(onsiteSteps(_node(arrived: true)).map((e) => e.done).toList(), <bool>[true, false, false]);
    expect(onsiteSteps(_node(arrived: true, selfReported: true)).map((e) => e.done).toList(),
        <bool>[true, true, false]);
    expect(onsiteSteps(_node(arrived: true, selfReported: true, done: true)).map((e) => e.done).toList(),
        <bool>[true, true, true]);
  });

  test('★负控:显示态与交互判据同源 —— 已亮的步数 == 下一个待办交互的序号', () {
    // 这条钉住「显示与行为不许漂移」:三步里已完成的数量,决定 playNodeInteractionFor 返回哪一个
    for (final n in <PlayNode>[
      _node(),
      _node(arrived: true),
      _node(arrived: true, selfReported: true),
    ]) {
      final int lit = onsiteSteps(n).where((e) => e.done).length;
      final PlayNodeInteraction want = <PlayNodeInteraction>[
        PlayNodeInteraction.freeArrivalScan,
        PlayNodeInteraction.freeProofPhoto,
        PlayNodeInteraction.freeMerchantCode,
      ][lit];
      expect(playNodeInteractionFor(mode: 2, node: n), want,
          reason: '亮了 $lit 步,下一步就该是 $want —— 两处判据漂了这里会红');
    }
  });
}
