import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_misc_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// 节点玩法模板族最后四件(predict / random / scan / bingo)的**纯逻辑**门禁。
///
/// 判据逐条对着真源:
/// - `playkit-random/index.js`:`_gestureOf` / `_posOf` / `_themeFor` +
///   `show, cards, drawn, drawCount` 观察者的线上分支;
/// - `playkit-predict/index.js`:`revealOf` / `pickLabel` / `waitLabelOf`;
/// - `playkit-scan/index.js`:`normalizeKind`;
/// - `playkit-bingo/index.js`:`shadeOf` / `lineCount` / `LINES` / ribbon。
void main() {
  group('random · 牌堆', () {
    test('线上分支:总张数 = max(drawCount, 已抽数, 1),盖着的牌写「?」', () {
      final List<PlayKitDeckCard> deck = buildRandomDeck(
        drawn: <Map<String, Object?>>[
          <String, Object?>{'id': 'd0', 'label': '第一关', 'content': '把门口的花浇了'},
        ],
        drawCount: 3,
      );
      expect(deck.length, 3);
      expect(deck[0].opened, isTrue);
      expect(deck[0].id, 'd0');
      expect(deck[0].title, '第一关');
      expect(deck[0].body, '把门口的花浇了');
      expect(deck[1].opened, isFalse);
      expect(
        deck[1].title,
        '?',
        reason: '真标题此刻还没抽出来,服务端也不会提前给 —— 写「?」不是写空',
      );
      expect(deck[1].id, 'back1');
    });

    test('负控:服务端两样都没给时也留一张,不是空屏', () {
      expect(
        buildRandomDeck(drawn: const <Map<String, Object?>>[], drawCount: 0).length,
        1,
        reason: 'total 至少 1(真源 Math.max(..., 1));0 张会让这一屏什么都没得看',
      );
    });

    test('开局停在下一张还没翻的牌上;抽满了停在最后一张', () {
      expect(randomActiveIndex(0, 3), 0);
      expect(randomActiveIndex(1, 3), 1);
      expect(randomActiveIndex(3, 3), 2);
    });

    test('手势阈值 = 卡宽 22%(真源 _gestureOf)', () {
      // 300 * 0.22 = 66
      expect(randomGestureOf(-70, 300), PlayKitDeckGesture.next);
      expect(randomGestureOf(-66.1, 300), PlayKitDeckGesture.next);
      expect(randomGestureOf(70, 300), PlayKitDeckGesture.open);
      // 负控:不到阈值算手抖,不是甩
      expect(randomGestureOf(-60, 300), PlayKitDeckGesture.none);
      expect(randomGestureOf(60, 300), PlayKitDeckGesture.none);
      // 负控:量不到宽度就不判(真源 `if (!(width > 0)) return ''`)
      expect(randomGestureOf(-999, 0), PlayKitDeckGesture.none);
    });

    test('位置取模循环:翻到底要能接回开头', () {
      expect(randomPosOf(2, 2, 3), 0);
      expect(randomPosOf(0, 2, 3), 1);
      expect(randomPosOf(1, 2, 3), 2);
      expect(randomPosOf(0, 2, 9), -1, reason: '第 4 张起不渲染(真源 p < 3)');
      expect(randomPosOf(0, 0, 0), -1);
    });

    test('底色按卡序轮转:同一张卡每次抽到必须同色', () {
      expect(randomThemeIndexFor(0), 0);
      expect(randomThemeIndexFor(2), 2);
      expect(randomThemeIndexFor(3), 0);
      expect(randomThemeIndexFor(4), 1);
      expect(randomThemeIndexFor(-1), 0, reason: '下标越界也不能崩,按 0 张算');
    });
  });

  group('predict · 揭晓四态', () {
    const List<PlayKitPredictOption> options = <PlayKitPredictOption>[
      PlayKitPredictOption(key: 'a', label: '左边的店'),
      PlayKitPredictOption(key: 'b', label: '右边的店'),
    ];

    test('负控:没有 settleStatus → 整块不渲染(不编一句「暂无结果」)', () {
      expect(
        predictRevealOf(
          settleStatus: null,
          settledOption: '',
          won: false,
          options: options,
          myOptionKey: '',
        ),
        isNull,
      );
      expect(
        predictRevealOf(
          settleStatus: '',
          settledOption: '',
          won: false,
          options: options,
          myOptionKey: '',
        ),
        isNull,
      );
    });

    test('0 待揭晓 / 2 作废各说各的话', () {
      final PlayKitPredictRevealText wait = predictRevealOf(
        settleStatus: 0,
        settledOption: '',
        won: false,
        options: options,
        myOptionKey: 'a',
      )!;
      expect(wait.kind, PlayKitPredictReveal.wait);
      expect(wait.head, '等商家给答案');
      final PlayKitPredictRevealText voided = predictRevealOf(
        settleStatus: 2,
        settledOption: '',
        won: false,
        options: options,
        myOptionKey: 'a',
      )!;
      expect(voided.kind, PlayKitPredictReveal.voided);
      expect(voided.head, '这一轮作废了');
      expect(voided.text, contains('不发奖'));
    });

    test('1 已揭晓:中/没中按 won,文案里带出答案', () {
      final PlayKitPredictRevealText won = predictRevealOf(
        settleStatus: 1,
        settledOption: 'b',
        won: true,
        options: options,
        myOptionKey: 'b',
      )!;
      expect(won.kind, PlayKitPredictReveal.won);
      expect(won.text, '答案是「右边的店」，你押的就是它。');
      final PlayKitPredictRevealText lost = predictRevealOf(
        settleStatus: 1,
        settledOption: 'b',
        won: false,
        options: options,
        myOptionKey: 'a',
      )!;
      expect(lost.kind, PlayKitPredictReveal.lost);
      expect(lost.text, '答案是「右边的店」，你押的是「左边的店」。');
    });

    test('key 找不到就把 key 原样回去,不编「未知选项」', () {
      expect(predictPickLabel(options, 'z'), 'z');
    });

    test('waitLabel:商家没配就不写,配了逐字照真源', () {
      expect(predictWaitLabelOf('DAYS', 3), '第 3 天揭晓，到点由商家给出答案。');
      expect(predictWaitLabelOf('HOURS', 0), '由商家随时结算，到点给出答案。');
      expect(predictWaitLabelOf('DAYS', 0), '第 1 天揭晓，到点由商家给出答案。');
      expect(predictWaitLabelOf('', 0), '', reason: '没配模式时宁可不写');
    });

    test('选项解析:没有 key 的条目丢掉(服务端认 key,不认下标)', () {
      final List<PlayKitPredictOption> parsed = PlayKitPredictOption.listFrom(<Object?>[
        <String, Object?>{'key': 'a', 'label': 'A'},
        <String, Object?>{'label': '没有 key'},
        'x',
      ]);
      expect(parsed.length, 1);
      expect(parsed.single.key, 'a');
    });
  });

  group('scan · 回复形态', () {
    test('只认「语音」「图片」,认不出落文字(最保守,不会凭空要权限)', () {
      expect(normalizeScanKind('语音'), PlayKitScanKind.voice);
      expect(normalizeScanKind('图片'), PlayKitScanKind.image);
      expect(normalizeScanKind('文字'), PlayKitScanKind.text);
      expect(normalizeScanKind('VIDEO'), PlayKitScanKind.text);
      expect(normalizeScanKind(null), PlayKitScanKind.text);
      expect(normalizeScanKind(' 语音 '), PlayKitScanKind.voice);
    });
  });

  group('bingo · 棋盘', () {
    test('深浅 = (行 + 列) % 2', () {
      expect(bingoShadeIsDark(0), isFalse);
      expect(bingoShadeIsDark(1), isTrue);
      expect(bingoShadeIsDark(3), isTrue);
      expect(
        bingoShadeIsDark(4),
        isFalse,
        reason: '正中 (1+1)%2 = 0 —— 写成「行 + 序号」会把中间一整列涂黑(原型踩过)',
      );
    });

    test('八条线:三横三竖两斜,交叉各算各的', () {
      expect(bingoLineCount(List<bool>.filled(9, false, growable: false)), 0);
      final List<bool> oneRow = List<bool>.filled(9, false, growable: false)
        ..[0] = true
        ..[1] = true
        ..[2] = true;
      expect(bingoLineCount(oneRow), 1);
      final List<bool> cross = List<bool>.filled(9, false, growable: false)
        ..[0] = true
        ..[1] = true
        ..[2] = true
        ..[3] = true
        ..[6] = true;
      expect(bingoLineCount(cross), 2, reason: '第一行 + 第一列共用左上角,各算一条');
    });

    test('格子:specs 优先、labels 兜底、how 缺省「走到即亮」、扫码格按 how 判', () {
      final List<PlayKitBingoCell> cells = buildBingoCells(
        cellSpecs: const <Map<String, Object?>>[
          <String, Object?>{'t': '门口', 'how': '到店扫码'},
        ],
        labels: const <String>['甲', '乙'],
        filledPositions: const <int>[0, 1, 2],
      );
      expect(cells.length, 9);
      expect(cells[0].title, '门口');
      expect(cells[0].isScan, isTrue);
      expect(cells[0].how, '到店扫码');
      expect(cells[1].title, '乙');
      expect(cells[1].how, '走到即亮');
      expect(cells[1].isScan, isFalse);
      expect(cells[2].title, '', reason: '既没 spec 也没 label 就是空,不编「第 3 格」');
      expect(cells[0].filled, isTrue);
      expect(cells[8].filled, isFalse);
      expect(cells[0].inLine, isTrue, reason: '连成线的三格要标出来');
      expect(cells[3].inLine, isFalse);
    });

    test('横幅在真领到时才出:没连上不出,连一条出线的奖,全亮出全亮奖', () {
      expect(
        bingoRibbon(full: false, lines: 0, lineReward: '一杯', fullReward: '大礼'),
        '',
        reason: '默认摆一条灰的等于提前把奖亮出来',
      );
      expect(
        bingoRibbon(full: false, lines: 1, lineReward: '一杯', fullReward: '大礼'),
        '连成一条线 · 一杯',
      );
      expect(
        bingoRibbon(full: true, lines: 4, lineReward: '一杯', fullReward: '大礼'),
        '九格全亮 · 大礼',
      );
      expect(
        bingoRibbon(full: true, lines: 0, lineReward: '', fullReward: ''),
        '',
        reason: '商家没填奖就别编一个',
      );
    });
  });
}
