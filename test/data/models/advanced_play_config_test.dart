import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/advanced_play_config.dart';
import 'package:chengyin_app/data/models/node_game_catalog.dart';

/// 逐条对账真源 `chengyinhub-xcx/utils/publish/advanced-game-config.js` 与其
/// `tests/unit/advanced-game-config*.test.js`。这份测的是「创作端配出来的 payload
/// 后端认不认、玩家端读不读得回」—— 数据契约,不依赖画面。
void main() {
  group('defaultConfig / serialize', () {
    test('默认配置:一段都没启用 → serialize 返回空串', () {
      expect(serializeAdvancedConfig(defaultAdvancedConfig()), '');
    });

    test('启用一段 → serialize 出该段且能 parse 回来', () {
      final m = defaultAdvancedConfig();
      (m['coinFlip'] as Map<String, Object?>)['enabled'] = true;
      (((m['coinFlip'] as Map)['heads']) as Map)['action'] = '这杯店家请';
      (((m['coinFlip'] as Map)['tails']) as Map)['action'] = '这杯你请';
      final raw = serializeAdvancedConfig(m);
      expect(raw, isNotEmpty);
      final back = parseAdvancedConfig(raw);
      expect(back.error, '');
      expect(
        ((back.value['coinFlip'] as Map)['heads'] as Map)['action'],
        '这杯店家请',
      );
    });

    test('未知段透传:normalize/serialize 不吞掉名单外的段', () {
      final m = defaultAdvancedConfig();
      m['someFutureKit'] = <String, Object?>{'enabled': true, 'x': 1};
      final raw = serializeAdvancedConfig(m);
      final back = parseAdvancedConfig(raw);
      expect(back.value['someFutureKit'], isNotNull);
      expect(advExtraKeys(m), contains('someFutureKit'));
    });
  });

  group('normalize(存盘前清洗)', () {
    test('未启用的段原样保留,不清洗', () {
      final m = defaultAdvancedConfig();
      m['blindTaste'] = <String, Object?>{
        'enabled': false,
        'title': '',
        'options': <Object?>[
          <String, Object?>{'key': 'A', 'label': '留着'},
        ],
      };
      final n = normalizeAdvancedConfig(m);
      // 未启用 → blindTaste 保持原样(title 空串仍在,options 不被重排)
      expect((n['blindTaste'] as Map)['title'], '');
    });

    test('启用盲品:空串字段删键,options 规整为 key/label', () {
      final m = defaultAdvancedConfig();
      m['blindTaste'] = <String, Object?>{
        'enabled': true,
        'title': '先尝再猜',
        'steps': '',
        'hint': '   ',
        'xp': '3',
        'answerKey': ' A ',
        'options': <Object?>[
          <String, Object?>{'key': 'A', 'label': '果酸', 'extra': 'x'},
          <String, Object?>{'key': 'B', 'label': ''},
          <String, Object?>{'key': '', 'label': ''},
        ],
      };
      final n = normalizeAdvancedConfig(m)['blindTaste'] as Map;
      expect(n.containsKey('steps'), isFalse, reason: '空串 steps 应删键');
      expect(n.containsKey('hint'), isFalse, reason: '空白 hint 应删键');
      expect(n['xp'], 3);
      expect(n['answerKey'], 'A');
      final options = n['options'] as List;
      // 第三个 key+label 全空 → 被过滤;第二个有 key 保留
      expect(options.length, 2);
      expect(options.first.containsKey('extra'), isFalse);
    });

    test('弹球关掉限时 → seconds 删键', () {
      final m = defaultAdvancedConfig();
      m['ballShake'] = <String, Object?>{
        'enabled': true,
        'goal': 20,
        'timed': false,
        'seconds': 12,
        'xp': 0,
      };
      final n = normalizeAdvancedConfig(m)['ballShake'] as Map;
      expect(n.containsKey('seconds'), isFalse);
    });

    test('骰子:颗数夹回 1/2,faces 补齐 6,多余截断', () {
      final m = defaultAdvancedConfig();
      m['diceRoll'] = <String, Object?>{
        'enabled': true,
        'diceCount': 5,
        'faces': <Object?>['a', 'b'],
      };
      final n = normalizeAdvancedConfig(m)['diceRoll'] as Map;
      expect(n['diceCount'], 1);
      expect((n['faces'] as List).length, 6);
      expect(n['faces'][3], '');
    });

    test('找东西半径一律系统值 0.08(商家填什么都不算)', () {
      final m = defaultAdvancedConfig();
      m['hiddenObject'] = <String, Object?>{
        'enabled': true,
        'title': '找猫',
        'imageUrl': '/local/cat.png',
        'xp': 0,
        'hotspots': <Object?>[
          <String, Object?>{'id': 's1', 'label': '窗台', 'x': 0.5, 'y': 0.5, 'r': 0.9},
          <String, Object?>{'id': 's2', 'label': '柜台', 'x': 0.1, 'y': 0.1},
          <String, Object?>{'id': 's3', 'label': '门后', 'x': 0.9, 'y': 0.9},
        ],
      };
      final ho = normalizeAdvancedConfig(m)['hiddenObject'] as Map;
      for (final spot in ho['hotspots'] as List) {
        expect((spot as Map)['r'], kHotspotRadius);
      }
    });
  });

  group('validate(边界,逐条对齐真源报错文案)', () {
    String v(Map<String, Object?> Function(Map<String, Object?> m) setup,
        {AdvancedValidateOpts opts = const AdvancedValidateOpts()}) {
      final m = setup(defaultAdvancedConfig());
      return validateAdvancedConfig(normalizeAdvancedConfig(m), opts: opts);
    }

    test('计时:10 秒至 24 小时', () {
      expect(
        v((m) {
          (m['timer'] as Map)['enabled'] = true;
          (m['timer'] as Map)['durationSeconds'] = 5;
          return m;
        }),
        '计时时长须为 10 秒至 24 小时',
      );
      expect(
        v((m) {
          (m['timer'] as Map)['enabled'] = true;
          (m['timer'] as Map)['durationSeconds'] = 3600;
          return m;
        }),
        '',
      );
    });

    test('抛硬币:正反面的 action 必填', () {
      expect(
        v((m) {
          (m['coinFlip'] as Map)['enabled'] = true;
          return m;
        }),
        '正面要做什么不能为空',
      );
    });

    test('骰子:六面都不能为空', () {
      expect(
        v((m) {
          (m['diceRoll'] as Map)['enabled'] = true;
          return m;
        }),
        '掷骰子第 1 面不能为空',
      );
    });

    test('倒计时:到点文案必填 + 时长范围', () {
      expect(
        v((m) {
          (m['countdown'] as Map)['enabled'] = true;
          (m['countdown'] as Map)['seconds'] = 90;
          return m;
        }),
        '到点时说什么不能为空',
      );
      expect(
        v((m) {
          (m['countdown'] as Map)['enabled'] = true;
          (m['countdown'] as Map)['seconds'] = 3;
          (m['countdown'] as Map)['doneText'] = '时间到';
          return m;
        }),
        '倒计时时长须为 5 至 3600 秒',
      );
    });

    test('精准停表:目标/容差/次数三档边界', () {
      expect(
        v((m) {
          (m['stopwatch'] as Map)['enabled'] = true;
          (m['stopwatch'] as Map)['targetSeconds'] = 10;
          (m['stopwatch'] as Map)['toleranceMs'] = 300;
          (m['stopwatch'] as Map)['tries'] = 3;
          return m;
        }),
        '',
      );
      expect(
        v((m) {
          (m['stopwatch'] as Map)['enabled'] = true;
          (m['stopwatch'] as Map)['toleranceMs'] = 10;
          return m;
        }),
        '精准停表容差须为 50 至 5000 毫秒',
      );
    });

    test('变色就点:达标毫秒下限 120', () {
      expect(
        v((m) {
          (m['reaction'] as Map)['enabled'] = true;
          (m['reaction'] as Map)['rounds'] = 3;
          (m['reaction'] as Map)['goalMs'] = 60;
          return m;
        }),
        '达标毫秒须为 120 至 2000',
      );
    });

    test('盲品:正确答案必须是其中一个选项', () {
      expect(
        v((m) {
          final bt = m['blindTaste'] as Map;
          bt['enabled'] = true;
          bt['title'] = '先尝再猜';
          bt['answerKey'] = 'Z';
          bt['options'] = <Object?>[
            <String, Object?>{'key': 'A', 'label': '果酸'},
            <String, Object?>{'key': 'B', 'label': '焦糖'},
          ];
          return m;
        }),
        '盲品正确答案必须是其中一个选项',
      );
    });

    test('盲品:采用公共库时 answerKey 空放行', () {
      final m = defaultAdvancedConfig();
      m['blindTaste'] = <String, Object?>{
        'enabled': true,
        'title': '先尝再猜',
        'answerKey': '',
        'options': <Object?>[
          <String, Object?>{'key': 'A', 'label': '果酸'},
          <String, Object?>{'key': 'B', 'label': '焦糖'},
        ],
      };
      expect(
        validateAdvancedConfig(
          normalizeAdvancedConfig(m),
          opts: const AdvancedValidateOpts(adoptedFromLibrary: true),
        ),
        '',
      );
    });

    test('估数:容差不能超过量程一半', () {
      expect(
        v((m) {
          (m['estimate'] as Map)['enabled'] = true;
          (m['estimate'] as Map)['title'] = '多少颗';
          (m['estimate'] as Map)['min'] = 0;
          (m['estimate'] as Map)['max'] = 100;
          (m['estimate'] as Map)['answer'] = 50;
          (m['estimate'] as Map)['tolerance'] = 60;
          return m;
        }),
        '估数容差不能超过量程的一半',
      );
    });

    test('计步:目标步数 100–100000', () {
      expect(
        v((m) {
          (m['steps'] as Map)['enabled'] = true;
          (m['steps'] as Map)['goal'] = 50;
          return m;
        }),
        '计步目标须为 100 至 100000 步',
      );
    });

    test('竞猜:截止时间须为 0–23 整点', () {
      expect(
        v((m) {
          (m['predict'] as Map)['enabled'] = true;
          (m['predict'] as Map)['question'] = '哪种卖得多';
          (m['predict'] as Map)['closeAtHour'] = 25;
          (m['predict'] as Map)['options'] = <Object?>[
            <String, Object?>{'key': 'A', 'label': '耶加'},
            <String, Object?>{'key': 'B', 'label': '曼特宁'},
          ];
          return m;
        }),
        '竞猜截止时间须为 0 到 23 点之间的整点',
      );
    });

    test('时段限定:起止相同判歧义', () {
      expect(
        v((m) {
          (m['timeWindow'] as Map)['enabled'] = true;
          (m['timeWindow'] as Map)['openFrom'] = '20:00';
          (m['timeWindow'] as Map)['openTo'] = '20:00';
          return m;
        }),
        '开放时段的起止不能相同',
      );
    });

    test('schemaVersion 不匹配 → 版本不受支持', () {
      final m = defaultAdvancedConfig();
      m['schemaVersion'] = 99;
      expect(validateAdvancedConfig(m), '高级玩法配置版本不受支持');
    });
  });

  group('node-game-catalog:选择玩法的整条链路', () {
    test('applyToConfig 只开选中段、关掉其余玩法段,qa 写 mode', () {
      var adv = defaultAdvancedConfig();
      adv = advApplyToConfig(adv, 'qaPick')!;
      expect((adv['qa'] as Map)['enabled'], true);
      expect((adv['qa'] as Map)['mode'], 'PICK');
      expect((adv['coinFlip'] as Map)['enabled'], false);
      // 选中后 detect 能认回来
      expect(advDetectGame(adv), 'qaPick');
      expect(advFindGame('qaPick')!.validationMethod, 3);
    });

    test('estimate 玩法把 validationMethod 顶到 8(老链路通关口径)', () {
      final adv = advApplyToConfig(defaultAdvancedConfig(), 'estimate')!;
      expect((adv['estimate'] as Map)['enabled'], true);
      expect(advFindGame('estimate')!.validationMethod, 8);
    });

    test('bingo 不占段(主题级),选它不改动任何 gameplay 段', () {
      final adv = advApplyToConfig(defaultAdvancedConfig(), 'bingo')!;
      for (final s in kGameSections) {
        expect((adv[s] as Map)['enabled'], isFalse, reason: s);
      }
      expect(advDetectGame(adv), '');
    });

    test('supportsTimer:决定类不能限时,挑战类可以', () {
      expect(advSupportsTimer('coin'), isFalse);
      expect(advSupportsTimer('countdown'), isTrue);
      expect(advSupportsTimer(''), isTrue, reason: '没选玩法照旧');
    });

    test('detectGame 认不出来的旧配置 → 空(显示成没选玩法)', () {
      expect(advDetectGame(defaultAdvancedConfig()), '');
      expect(advDetectGame(null), '');
    });
  });

  test('七个 DECIDE 玩法:填 → serialize → parse,内容一个字不丢', () {
    final m = defaultAdvancedConfig();
    (m['coinFlip'] as Map)['enabled'] = true;
    (m['coinFlip'] as Map)['kicker'] = '抛一次,认结果';
    ((m['coinFlip'] as Map)['heads'] as Map)['action'] = '这杯店家请';
    ((m['coinFlip'] as Map)['tails'] as Map)['action'] = '这杯你请';
    (m['diceRoll'] as Map)['enabled'] = true;
    (m['diceRoll'] as Map)['diceCount'] = 2;
    (m['diceRoll'] as Map)['faces'] =
        List<Object?>.generate(6, (i) => '第 ${i + 1} 件事');
    (m['countdown'] as Map)['enabled'] = true;
    (m['countdown'] as Map)['doneText'] = '时间到。';
    final back = parseAdvancedConfig(serializeAdvancedConfig(m));
    expect(back.error, '');
    final cf = back.value['coinFlip'] as Map;
    expect((cf['heads'] as Map)['action'], '这杯店家请');
    expect((back.value['diceRoll'] as Map)['diceCount'], 2);
    expect(((back.value['diceRoll'] as Map)['faces'] as List)[5], '第 6 件事');
    expect((back.value['countdown'] as Map)['doneText'], '时间到。');
  });
}
