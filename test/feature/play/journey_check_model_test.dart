import 'package:chengyin_app/data/models/play_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与小程序 `utils/playkit-view.js`(pickJourneyCheck / checkReceiptView)和
/// `playkit-journey-check/index.js`(canReroll / TIER_LABEL)同一口径的纯算法用例。
void main() {
  group('JourneyCheckProblem.fromEncounter(真源 pickJourneyCheck)', () {
    test('allowedActions 不含 check → 没有检定,不弹任何东西', () {
      expect(
        JourneyCheckProblem.fromEncounter(<String, dynamic>{
          'allowedActions': <String>['checkin'],
          'check': <String, dynamic>{'checkId': 9, 'skill': '观察'},
        }),
        isNull,
      );
    });

    test('checkId 缺失/空白 → 同样不算有检定(拿不到 checkId 就不算)', () {
      for (final Object? id in <Object?>[null, '', '   ']) {
        expect(
          JourneyCheckProblem.fromEncounter(<String, dynamic>{
            'allowedActions': <String>['check'],
            'check': <String, dynamic>{'checkId': id, 'skill': '观察'},
          }),
          isNull,
        );
      }
    });

    test('encounter 为 null / 视图脏数据 → 静默判空,不抛', () {
      expect(JourneyCheckProblem.fromEncounter(null), isNull);
      expect(
        JourneyCheckProblem.fromEncounter(<String, dynamic>{
          'allowedActions': 'not-a-list',
          'check': <String, dynamic>{'checkId': 9},
        }),
        isNull,
      );
    });

    test('题面逐字段搬公开面:mods 的 held 决定"这条算不算数"', () {
      final JourneyCheckProblem? p = JourneyCheckProblem.fromEncounter(
        <String, dynamic>{
          'allowedActions': <String>['checkin', 'check'],
          'check': <String, dynamic>{
            'checkId': 9,
            'skill': '观察',
            'tier': 'hard',
            'advantage': true,
            'disadvantage': false,
            'mods': <dynamic>[
              <String, dynamic>{'label': '下雨', 'value': -2, 'held': true},
              <String, dynamic>{'label': '陌生店面', 'value': 1, 'held': false},
            ],
          },
        },
      );
      expect(p, isNotNull);
      expect(p!.checkId, '9');
      expect(p.skill, '观察');
      expect(p.tier, 'hard');
      expect(p.advantage, isTrue);
      expect(p.disadvantage, isFalse);
      expect(p.mods, hasLength(2));
      expect(p.mods[0].label, '下雨');
      expect(p.mods[0].value, -2);
      expect(p.mods[0].active, isTrue);
      expect(p.mods[1].active, isFalse);
    });
  });

  group('JourneyCheckReceipt.fromJson(真源 checkReceiptView)', () {
    test('结算前:没有 text/failCostLabel 也不猜;缺省读数保持 null', () {
      final JourneyCheckReceipt r = JourneyCheckReceipt.fromJson(
        <String, dynamic>{
          'tier': 'hard',
          'dc': '3',
          'dice': <dynamic>[4, '2'],
          'kept': 6,
          'total': 6,
          'success': true,
          'nat': '',
          'rerolled': false,
          'settled': false,
          'mods': <dynamic>[
            <String, dynamic>{'label': '下雨', 'value': -2, 'applied': true},
          ],
        },
      );
      expect(r.dc, 3, reason: '后端可能把数字发成字符串');
      expect(r.dice, <int>[4, 2]);
      expect(r.kept, 6);
      expect(r.success, isTrue);
      expect(r.settled, isFalse);
      expect(r.text, isEmpty);
      expect(r.failCostLabel, isEmpty);
      expect(r.hp, isNull, reason: '缺省不拿 0 冒充"扣光了"');
      expect(r.luck, isNull);
      expect(r.mods.single.active, isTrue, reason: '回执里的 applied 点亮同一支笔');
    });

    test('空对象也不炸:全部落到可渲染的缺省', () {
      final JourneyCheckReceipt r = JourneyCheckReceipt.fromJson(
        <String, dynamic>{},
      );
      expect(r.dice, isEmpty);
      expect(r.kept, isNull);
      expect(r.total, 0);
      expect(r.success, isFalse);
    });
  });

  group('canReroll / 难度档(真源 canReroll / TIER_LABEL)', () {
    JourneyCheckReceipt receipt({
      bool settled = false,
      bool rerolled = false,
      int? luck = 1,
    }) {
      return JourneyCheckReceipt.fromJson(<String, dynamic>{
        'settled': settled,
        'rerolled': rerolled,
        'luck': luck,
      });
    }

    test('掷过、未结算、没重掷过且幸运有剩才给重掷', () {
      expect(journeyCheckCanReroll(null), isFalse);
      expect(journeyCheckCanReroll(receipt()), isTrue);
      expect(journeyCheckCanReroll(receipt(settled: true)), isFalse);
      expect(journeyCheckCanReroll(receipt(rerolled: true)), isFalse);
      expect(journeyCheckCanReroll(receipt(luck: 0)), isFalse);
      expect(
        journeyCheckCanReroll(receipt(luck: null)),
        isFalse,
        reason: 'luck 缺省时不猜',
      );
    });

    test('三档中文;未知档原样透出;空档兜「标准」', () {
      expect(journeyCheckTierLabel('easy'), '简单');
      expect(journeyCheckTierLabel('MEDIUM'), '标准');
      expect(journeyCheckTierLabel('hard'), '困难');
      expect(journeyCheckTierLabel('mythic'), 'mythic');
      expect(journeyCheckTierLabel(''), '标准');
    });
  });
}
