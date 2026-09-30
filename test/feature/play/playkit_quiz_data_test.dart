import 'dart:ui' show Offset, Size;

import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 问答 / 判定族五屏的数据层与载荷换算。
///
/// ★ 判据是**小程序真源**,不是这里的实现:
/// - 动作名与字段名:`utils/playkit-view.js#ACTION_OF` / `#serverPayload`
///   与 `tests/fixtures/playkit-server-actions.json`(那份夹具后端也在读同一份);
/// - 投影字段名:`utils/playkit-view.js#pickPlayKit` 的五个分支;
/// - 刻度算法:`pages/play/components/playkit-estimate/index.js#stepFor/buildTicks`。
void main() {
  group('qa:submit → SUBMIT_QA', () {
    test('打字题报 input,选项题报 optionId —— 按模式只给其中一个', () {
      expect(
        qaSubmitPayload(mode: PlayKitQaMode.type, input: '1908'),
        <String, Object?>{'input': '1908'},
      );
      expect(
        qaSubmitPayload(mode: PlayKitQaMode.pick, optionId: 'a'),
        <String, Object?>{'optionId': 'a'},
      );
    });

    test('★拍照档不在一层直发的路径里 —— 传 shot 直接抛', () {
      expect(
        () => qaSubmitPayload(mode: PlayKitQaMode.shot),
        throwsArgumentError,
      );
      // 它是一个独立的动作名,而且**不在服务端动作表里**(两步链的第一步)。
      expect(kQaShootAction, 'qa:shoot');
      expect(kQaSubmitAction, 'SUBMIT_QA');
      expect(kQaShootAction, isNot(kQaSubmitAction));
    });
  });

  group('字段名 / 单位换算', () {
    test('estimate:组件报 guess,服务端收 {value}', () {
      expect(estimateSubmitPayload(42), <String, Object?>{'value': 42});
    });

    test('branch:走向由服务端按 optionId 判,下标不带', () {
      expect(branchChoosePayload('left'), <String, Object?>{'optionId': 'left'});
    });

    test('pricepair:带这张海报自己的 id', () {
      expect(pricePairSubmitPayload('b'), <String, Object?>{'pickId': 'b'});
    });

    test('★hidden:百分比(0–100)→ 比例(0–1),四位小数', () {
      expect(
        hiddenSubmitPayload(30, 40),
        <String, Object?>{'x': 0.3, 'y': 0.4},
      );
      expect(hiddenSubmitPayload(12.5, 80), <String, Object?>{'x': 0.125, 'y': 0.8});
      expect(ratioOf(33.33333), 0.3333);
      expect(ratioOf(-1), 0);
      expect(ratioOf(200), 1);
      expect(ratioOf(double.nan), 0);
    });
  });

  group('★ 夹具 playkit-server-actions.json 里本批六条逐条复现', () {
    // 后端侧 PlaykitActionPayloadContractTest 读的是同一份夹具:两边一起绿才叫对得上。
    test('每条的动作名与载荷都对得上', () {
      // (动作名, 组件抛出的载荷, 夹具里后端认的载荷)
      final List<(String, Map<String, Object?>, Map<String, Object?>)> cases =
          <(String, Map<String, Object?>, Map<String, Object?>)>[
            (kEstimateSubmitAction, estimateSubmitPayload(42), <String, Object?>{'value': 42}),
            (kPricePairSubmitAction, pricePairSubmitPayload('b'), <String, Object?>{'pickId': 'b'}),
            (kHiddenSubmitAction, hiddenSubmitPayload(30, 40), <String, Object?>{'x': 0.3, 'y': 0.4}),
            (kBranchChooseAction, branchChoosePayload('left'), <String, Object?>{'optionId': 'left'}),
            (kQaSubmitAction, qaSubmitPayload(mode: PlayKitQaMode.type, input: '1908'), <String, Object?>{'input': '1908'}),
            (kQaSubmitAction, qaSubmitPayload(mode: PlayKitQaMode.pick, optionId: 'a'), <String, Object?>{'optionId': 'a'}),
          ];
      expect(cases.length, 6, reason: '夹具里本批六条:少一条就是少一条链');
      for (final (String action, Map<String, Object?> produced, Map<String, Object?> want) in cases) {
        expect(produced, want, reason: '$action 的载荷与夹具对不上');
      }
      expect(
        cases.map(((String, Map<String, Object?>, Map<String, Object?>) c) => c.$1),
        <String>['SUBMIT_ESTIMATE', 'SUBMIT_PRICE_PAIR', 'SUBMIT_HIDDEN_OBJECT', 'CHOOSE', 'SUBMIT_QA', 'SUBMIT_QA'],
        reason: '动作名逐条对夹具,顺序也是',
      );
    });
  });

  group('找东西的坐标', () {
    const Size scene = Size(300, 400);

    test('图内的点按百分比报,越界返回 null(不夹回 100 再发)', () {
      expect(percentInScene(const Offset(150, 200), scene)!.x, 50);
      expect(percentInScene(const Offset(150, 200), scene)!.y, 50);
      expect(percentInScene(const Offset(0, 0), scene)!.x, 0);
      // 出了图 = 这一下不算。夹回 100 是把「点在图外面」伪装成「点在图角上」。
      expect(percentInScene(const Offset(301, 200), scene), isNull);
      expect(percentInScene(const Offset(150, -1), scene), isNull);
    });

    test('量不到图的位置(还没布局)时也返回 null', () {
      expect(percentInScene(const Offset(1, 1), Size.zero), isNull);
    });
  });

  group('estimate 滚筒算法(与小程序 stepFor/buildTicks 同口径)', () {
    test('常见量程一格一个数', () {
      expect(estimateStepFor(0, 1000), 1);
      expect(estimateStepFor(0, 2000), 1);
    });

    test('超宽量程才跳格(2000 以内一格一个数)', () {
      expect(estimateStepFor(0, 2001), 10);
      expect(estimateStepFor(0, 20000), 10);
      expect(estimateStepFor(0, 100000), 1000);
    });

    test('★上限一定落在刻度表里(不然滑到底选不到量程上限)', () {
      final List<num> ticks = buildEstimateTicks(0, 1000);
      expect(ticks.first, 0);
      expect(ticks.last, 1000);
      final List<num> wide = buildEstimateTicks(0, 123456);
      expect(wide.last, 123456);
      // 跳格之后仍然带得动:数目远小于量程本身
      expect(wide.length, lessThan(200));
    });

    test('开局停在量程正中', () {
      final List<num> ticks = buildEstimateTicks(0, 1000);
      expect(estimateInitialIndex(ticks), ticks.length ~/ 2);
      expect(estimateInitialIndex(const <num>[]), 0);
    });

    test('屏上印的数:整数不带小数点', () {
      expect(estimateNumberText(500), '500');
      expect(estimateNumberText(500.0), '500');
      expect(estimateNumberText(12.5), '12.5');
    });
  });

  group('投影字段名(照 pickPlayKit 的五个分支)', () {
    test('qa:mode/options(id+label)/finished/passed/lastFeedback', () {
      final PlayKitQaData data = PlayKitQaData.fromKit(<String, Object?>{
        'mode': 'PICK',
        'title': '这家店开在哪一年?',
        'lead': '先看看门口的铜牌',
        'options': <Object?>[
          <String, Object?>{'id': 'a', 'label': '1908'},
          <String, Object?>{'id': 'b', 't': '1912'},
          <String, Object?>{'id': 'c', 'label': '1920'},
          // 没有 id 也没有文案的脏数据不当成一条选项
          <String, Object?>{},
        ],
        'maxTries': 3,
        'finished': true,
        'passed': false,
        'lastFeedback': '不对。',
      });
      expect(data.mode, PlayKitQaMode.pick);
      expect(data.options.length, 3);
      expect(data.options.first.id, 'a');
      expect(data.options[1].label, '1912', reason: '组件那一层叫 t,两种写法都要收');
      expect(data.options.last.label, '1920');
      expect(data.feedback, '不对。');
      expect(data.finished, isTrue);
      expect(data.passed, isFalse);
      // 三个选项封顶两次错:第三次不是机会是走过场
      expect(data.triesCap, 2);
    });

    test('qa:shot 的大字回落题干,题干不再重复', () {
      final PlayKitQaData data = PlayKitQaData.fromKit(<String, Object?>{
        'mode': 'SHOT',
        'title': '在这棵树下拍一张',
      });
      expect(data.mode, PlayKitQaMode.shot);
      expect(data.headline, '在这棵树下拍一张');
    });

    test('branch:只吃 currentStep,terminal 就是终点', () {
      final PlayKitBranchData data = PlayKitBranchData.fromKit(<String, Object?>{
        'currentStep': <String, Object?>{
          'id': 'start',
          'title': '雨停了',
          'body': '巷口有两条路。',
          'terminal': false,
          'options': <Object?>[
            <String, Object?>{'id': 'left', 'label': '往左'},
            <String, Object?>{'id': 'right', 'label': '往右'},
          ],
        },
      });
      expect(data.title, '雨停了');
      expect(data.body, '巷口有两条路。');
      expect(data.options.map((PlayKitQuizOption o) => o.id), <String>['left', 'right']);
      expect(data.ended, isFalse);
    });

    test('estimate:题面叫 question,次数叫 maxAttempts', () {
      final PlayKitEstimateData data = PlayKitEstimateData.fromKit(<String, Object?>{
        'question': '这一锅大概多少克?',
        'unit': '克',
        'min': 0,
        'max': 1000,
        'maxAttempts': 2,
      });
      expect(data.title, '这一锅大概多少克?');
      expect(data.unit, '克');
      expect(data.maxTries, 2);
      expect(data.ticks.last, 1000);
    });

    test('pricePair:名字与说明在图上、判定不给', () {
      final PlayKitPricePairData data = PlayKitPricePairData.fromKit(<String, Object?>{
        'title': '哪杯是真的?',
        'items': <Object?>[
          <String, Object?>{'id': 'a', 'name': '左杯', 'note': '奶泡更细'},
          <String, Object?>{'name': '右杯'},
        ],
        'maxTries': 2,
        'attempts': 1,
        'finished': false,
      });
      expect(data.items.length, 2);
      expect(data.items.first.id, 'a');
      expect(data.items.last.id, 'i1', reason: '没有 id 时按序补一个,判定仍按服务端回的 id');
      expect(data.items.first.note, '奶泡更细');
      expect(data.finished, isFalse);
    });

    test('hidden:foundIds 标已找到,全找齐才算过', () {
      final PlayKitHiddenData data = PlayKitHiddenData.fromKit(<String, Object?>{
        'title': '找到那只猫',
        'targets': <Object?>[
          <String, Object?>{'id': 't1', 'label': '三花猫'},
          <String, Object?>{'id': 't2', 'label': '黑猫'},
        ],
        'total': 2,
        'foundIds': <Object?>['t1'],
      });
      expect(data.foundCount, 1);
      expect(data.targets.first.found, isTrue);
      expect(data.targets.last.found, isFalse);
      expect(data.allFound, isFalse);
      // 空段:total 0 → 不算过(「全找齐」不是「什么都没找」)
      expect(PlayKitHiddenData.fromKit(const <String, Object?>{}).allFound, isFalse);
    });
  });
}
