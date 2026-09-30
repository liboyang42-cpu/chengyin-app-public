import 'dart:convert';

import 'package:chengyin_app/feature/prefab/prefab_story_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('场景流转(真源 story-engine.js SCENES/advance)', () {
    test('初状态:序章、hp 10、luck 2、四个技能基准值', () {
      const PrefabState s = PrefabState();
      expect(s.scene, 'prologue');
      expect(s.step, 0);
      expect(s.hp, 10);
      expect(s.luck, 2);
      expect(s.skills, <String, int>{
        'rule': 2,
        'window': 2,
        'heart': 2,
        'precision': 1,
      });
    });

    test('advance 按 13 幕顺序推进、step 归零,末幕 flow 原地不动', () {
      PrefabState s = const PrefabState().withStep(4);
      for (int i = 0; i < kPrefabScenes.length - 1; i++) {
        s = s.advance();
        expect(s.scene, kPrefabScenes[i + 1]);
        expect(s.step, 0, reason: '换幕必须把 step 清零($i)');
      }
      expect(s.scene, 'flow');
      expect(s.advance().scene, 'flow');
    });

    test('withStep 负数按 0(真源 Math.max(0, …))', () {
      expect(const PrefabState().withStep(-3).step, 0);
    });
  });

  group('check(2d6 + 技能 ≥ 难度)', () {
    test('取前两颗、夹到 1..6、缺的补 1', () {
      final PrefabCheckResult r = const PrefabState().check('rule', 9, <int>[
        7,
        0,
        5,
      ]);
      expect(r.dice, <int>[6, 1]);
      expect(r.roll, 7);
      // rule=2 → 7+2=9 ≥ dc 9。
      expect(r.score, 9);
      expect(r.ok, isTrue);
    });

    test('只给一颗 → 另一颗按 1 补', () {
      final PrefabCheckResult r = const PrefabState().check('heart', 10, <int>[
        6,
      ]);
      expect(r.dice, <int>[6, 1]);
      // heart=2 → 9 < 10。
      expect(r.ok, isFalse);
    });
  });

  group('applyProfile(措辞分类加技能)', () {
    test('出生地说「想不起来」加 precision,梦想说「画家」加 heart', () {
      final PrefabState s = const PrefabState().applyProfile(
        const PrefabProfile(name: '阿澄', place: '想不起来', dream: '画家'),
      );
      expect(s.skills['precision'], 2);
      expect(s.skills['heart'], 3);
      expect(s.profile.name, '阿澄');
    });

    test('两个措辞落同一技能 → 加两点', () {
      final PrefabState s = const PrefabState().applyProfile(
        const PrefabProfile(name: '阿澄', place: '山边的小镇', dream: '去很远的地方'),
      );
      // window 基准 2 → +1 +1。
      expect(s.skills['window'], 4);
    });

    test('空措辞落兜底 window', () {
      final PrefabState s = const PrefabState().applyProfile(
        const PrefabProfile(name: '阿澄'),
      );
      // place 兜底 window(+1),dream 兜底 heart(+1)。
      expect(s.skills['window'], 3);
      expect(s.skills['heart'], 3);
    });
  });

  group('gain(资源夹界)', () {
    test('hp 不越过 0/10,luck 不越过 0/4,dreams 不为负', () {
      const PrefabState s = PrefabState(hp: 1, luck: 3, dreams: 0);
      expect(s.gain(const PrefabGain(hp: -5)).hp, 0);
      expect(s.gain(const PrefabGain(hp: 20)).hp, 10);
      expect(s.gain(const PrefabGain(luck: 9)).luck, 4);
      expect(s.gain(const PrefabGain(dreams: -5)).dreams, 0);
    });

    test('念头去重、空念头不进', () {
      final PrefabState s = const PrefabState()
          .gain(const PrefabGain(thought: 'afternoon'))
          .gain(const PrefabGain(thought: 'afternoon'))
          .gain(const PrefabGain(thought: ''));
      expect(s.thoughts, <String>['afternoon']);
    });
  });

  group('observe / photoCount', () {
    test('空文本与重复文本不进台账', () {
      final PrefabState s = const PrefabState()
          .observe('窗', '有人在遛狗')
          .observe('窗', ' 有人在遛狗 ')
          .observe('窗', '');
      expect(s.observations.length, 1);
      expect(s.observations.single.text, '有人在遛狗');
    });

    test('只数非空照片', () {
      final PrefabState s = const PrefabState()
          .withPhoto('hall', 'https://x/1.jpg')
          .withPhoto('sign', '');
      expect(s.photoCount, 1);
    });
  });

  group('restore(真源版本闸)', () {
    test('坏 JSON / 非对象 / 未知场景 / 未知版本一律回初状态', () {
      expect(PrefabState.restore('{{{').scene, 'prologue');
      expect(PrefabState.restore('[1,2]').scene, 'prologue');
      expect(
        PrefabState.restore('{"version":2,"scene":"nope"}').scene,
        'prologue',
      );
      expect(
        PrefabState.restore('{"version":3,"scene":"birth"}').scene,
        'prologue',
      );
    });

    test('v1 老档合进 v2 且 step 归零', () {
      final PrefabState s = PrefabState.restore(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'scene': 'birth',
          'step': 3,
          'hp': 5,
          'profile': <String, dynamic>{'name': '老档'},
        }),
      );
      expect(s.scene, 'birth');
      expect(s.step, 0);
      expect(s.hp, 5);
      expect(s.profile.name, '老档');
      // 缺省字段回默认,不是 0。
      expect(s.luck, 2);
    });

    test('v2 往返:save() 再 restore 不丢状态', () {
      final PrefabState original = const PrefabState(scene: 'work')
          .withStep(2)
          .choose('boss', 2)
          .withPhoto('window', 'https://x/w.jpg')
          .observe('馆', '一片云')
          .gain(const PrefabGain(thought: 'precise'))
          .copyWith(
            job: '程序员',
            sticker: const PrefabSticker(label: '未加载地图', x: 150, y: 388),
            synced: true,
          );
      final PrefabState restored = PrefabState.restore(original.save());
      expect(restored.scene, 'work');
      expect(restored.step, 2);
      expect(restored.picks['boss'], 2);
      expect(restored.photos['window'], 'https://x/w.jpg');
      expect(restored.observations.single.text, '一片云');
      expect(restored.thoughts, <String>['precise']);
      expect(restored.job, '程序员');
      expect(restored.sticker?.label, '未加载地图');
      expect(restored.synced, isTrue);
    });

    test('profile 整键替换(真源 Object.assign 语义),不与旧值拼接', () {
      final PrefabState s = PrefabState.restore(
        jsonEncode(<String, dynamic>{
          'version': 2,
          'scene': 'register',
          'profile': <String, dynamic>{'name': '只回名字'},
        }),
      );
      expect(s.profile.name, '只回名字');
      expect(s.profile.place, '');
    });
  });

  group('入口判定与存档 key(真源 index.js:62 / onLoad)', () {
    test('isPrefabLifeTopic 只认「预制人生」及「预制人生 · …」', () {
      expect(isPrefabLifeTopic('预制人生'), isTrue);
      expect(isPrefabLifeTopic(' 预制人生 · 上海首演 '), isTrue);
      expect(isPrefabLifeTopic('预制人生2'), isFalse);
      expect(isPrefabLifeTopic('城市定向 · 预制人生'), isFalse);
      expect(isPrefabLifeTopic(null), isFalse);
      expect(isPrefabLifeTopic(''), isFalse);
    });

    test('activityId 优先,双缺落 preview', () {
      expect(
        prefabStorageKey(activityId: 77, topicId: 23),
        'prefab_life_v1_77',
      );
      expect(prefabStorageKey(topicId: 23), 'prefab_life_v1_23');
      expect(prefabStorageKey(), 'prefab_life_v1_preview');
    });
  });

  group('梦卡片组(真源 dreamCards)', () {
    test('dream1 十张、dream2 十二张、dream3 四张', () {
      expect(prefabDreamCards('dream1', const PrefabState()).length, 10);
      expect(prefabDreamCards('dream2', const PrefabState()).length, 12);
      expect(prefabDreamCards('dream3', const PrefabState()).length, 4);
      expect(prefabDreamCards('birth', const PrefabState()), isEmpty);
    });

    test('用户拍过的窗/手机/头像顶替对应卡的图', () {
      final PrefabState s = const PrefabState()
          .withPhoto('window', 'https://x/win.jpg')
          .withPhoto('phone', 'https://x/phone.jpg')
          .copyWith(profile: const PrefabProfile(avatar: 'https://x/me.jpg'));
      final List<PrefabDreamCard> cards = prefabDreamCards('dream1', s);
      // 第九张(倒数第二)才是「你自己看过的那个窗外」。
      expect(cards[8].src, 'https://x/win.jpg');
      final List<PrefabDreamCard> dream2 = prefabDreamCards('dream2', s);
      expect(
        dream2.any((PrefabDreamCard c) => c.src == 'https://x/win.jpg'),
        isTrue,
      );
      final List<PrefabDreamCard> dream3 = prefabDreamCards('dream3', s);
      expect(
        dream3.any((PrefabDreamCard c) => c.src == 'https://x/phone.jpg'),
        isTrue,
      );
      expect(
        dream3.any((PrefabDreamCard c) => c.src == 'https://x/me.jpg'),
        isTrue,
      );
    });
  });

  test('场景头三件套与真源 _sceneMeta 逐字(抽两幕)', () {
    expect(kPrefabSceneMeta['prologue']!.kicker, '预制人生 · 序章');
    expect(kPrefabSceneMeta['prologue']!.title, '开始吧');
    expect(kPrefabSceneMeta['career']!.kicker, '好像只是眨了一下眼');
    expect(kPrefabSceneMeta['career']!.cosmos, '眨眼');
  });

  test('结局 6 条带占比(真源 ENDINGS)', () {
    expect(kPrefabEndings.length, 6);
    expect(kPrefabEndings.first[0], '标准版本');
    expect(kPrefabEndings.last[0], '回收');
    expect(kPrefabEndings.last[3], '5%');
  });
}
