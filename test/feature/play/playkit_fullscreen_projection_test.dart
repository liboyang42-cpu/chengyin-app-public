import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_fullscreen_payload.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整屏决定类五件套的**投影**与**宿主层单位换算**判据。
///
/// 真源是小程序 `utils/playkit-view.js` 的 `pickPlayKit` 五个分支与
/// `serverPayload` 的换算表。这两层错了都不报错:
/// · 投影漏一个字段 = 那个玩法在 App 里没有数据可演;
/// · 换算漏一条 = 服务端读不到字段按 0 判,**永远不通过**。
void main() {
  group('projectPlayKit:五个整屏决定类', () {
    test('coinFlip:结果面走 selectedKey,两面的标签与要做的事走 choices', () {
      final List<PlayKitCard> cards = projectPlayKit(<String, Object?>{
        'coinFlip': <String, Object?>{
          'kicker': '抛一次，认结果',
          'side': 'HEADS',
          'flipped': true,
          'heads': <String, Object?>{'label': '正面', 'action': '做 20 个深蹲'},
          'tails': <String, Object?>{'label': '反面', 'action': '喝一杯水'},
        },
      });
      expect(cards, hasLength(1));
      final PlayKitCard card = cards.single;
      expect(card.kind, PlayKitKind.coinFlip);
      expect(card.eyebrow, '抛一次，认结果');
      expect(card.selectedKey, 'HEADS');
      expect(card.complete, isTrue);
      expect(card.choices, hasLength(2));
      expect(card.choices.first.label, '正面');
      expect(card.choices.first.payload['do'], '做 20 个深蹲');
    });

    test('coinFlip:没有结果时不给面 —— 组件不猜、不本地摇', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'coinFlip': <String, Object?>{'kicker': ''},
      }).single;
      expect(card.selectedKey, '');
      expect(card.complete, isFalse);
      expect(card.choices.first.label, '正面');
      expect(card.choices[1].label, '反面');
    });

    test('diceRoll:点数走 selectedKey(逗号串),颗数走 maxLength,六面走 choices', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'diceRoll': <String, Object?>{
          'kicker': '掷到几就做第几件事',
          'faces': <Object?>['a', 'b', 'c', 'd', 'e', 'f'],
          'pips': <Object?>[5, 4],
          'diceCount': 2,
          'rolled': true,
        },
      }).single;
      expect(card.kind, PlayKitKind.diceRoll);
      expect(card.selectedKey, '5,4');
      expect(card.maxLength, 2, reason: '两颗那一档只报点数和,不索引六个面');
      expect(card.choices, hasLength(6));
      expect(card.choices[3].label, 'd');
      expect(card.complete, isTrue);
    });

    test('diceRoll:一颗时 maxLength=1,没摇时不带点数', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'diceRoll': <String, Object?>{'diceCount': 1},
      }).single;
      expect(card.maxLength, 1);
      expect(card.selectedKey, '');
    });

    test('reaction:rounds → maxLength,goalMs → durationSeconds', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'reaction': <String, Object?>{
          'kicker': '变绿就点',
          'rounds': 3,
          'goalMs': 320,
          'submitted': true,
        },
      }).single;
      expect(card.kind, PlayKitKind.reaction);
      expect(card.maxLength, 3);
      expect(card.durationSeconds, 320);
      expect(card.complete, isTrue);
    });

    test(
      'ballShake:goal → maxLength;timed ? seconds : 0 → durationSeconds',
      () {
        final PlayKitCard timed = projectPlayKit(<String, Object?>{
          'ballShake': <String, Object?>{
            'kicker': '撞够 30 次',
            'goal': 30,
            'timed': true,
            'seconds': 12,
          },
        }).single;
        expect(timed.maxLength, 30);
        expect(timed.durationSeconds, 12);
        expect(timed.detail, '12 秒内撞满');

        final PlayKitCard untimed = projectPlayKit(<String, Object?>{
          'ballShake': <String, Object?>{
            'goal': 0,
            'timed': false,
            'seconds': 12,
          },
        }).single;
        expect(untimed.maxLength, 30, reason: 'goal 缺失按原型的默认值 30');
        expect(untimed.durationSeconds, 0, reason: '不限时就是 0,不该漏进秒数');
        expect(untimed.detail, '不限时，撞满为止');
      },
    );

    test('quietHold:kicker 与 sub,时长默认 15 秒', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'quietHold': <String, Object?>{'kicker': '别出声', 'sub': '一口都别出'},
      }).single;
      expect(card.kind, PlayKitKind.quietHold);
      expect(card.eyebrow, '别出声');
      expect(card.detail, '一口都别出');
      expect(card.durationSeconds, 15);
    });

    test('只投影一个玩法:没完成的排前面(与小程序 pickPlayKit 同口径)', () {
      final List<PlayKitCard> cards = projectPlayKit(<String, Object?>{
        'quietHold': <String, Object?>{'seconds': 15},
      });
      expect(cards, hasLength(1));
      expect(cards.single.kind, PlayKitKind.quietHold);
    });

    test('★ 决定/挑战五条不落默认档:同挂别的段时唯一入口不被挤后', () {
      // 真源 `KIT_PRIORITY`:scan → coinFlip → diceRoll → reaction →
      // ballShake → quietHold → countdown → stopwatch → blindTaste。
      // 这五条曾漏登记(落 ?? 99),节点同挂任何更靠前的未完成段就被挤掉
      // 展示位 —— 而整屏的**唯一入口**「进入玩法」就挂在这张单卡上
      // (`advanced_play_sheet.dart` 只渲染 `projectPlayKit` 挑中的那一张)。
      expect(
        projectPlayKit(<String, Object?>{
          'coinFlip': <String, Object?>{'kicker': '抛一次，认结果'},
          'diyName': <String, Object?>{'title': '起名'},
        }).single.kind,
        PlayKitKind.coinFlip,
        reason: 'coinFlip(真源第 9)该排在 diyName(第 18)前面',
      );
      expect(
        projectPlayKit(<String, Object?>{
          'quietHold': <String, Object?>{'seconds': 15},
          'scan': <String, Object?>{'title': '码'},
        }).single.kind,
        PlayKitKind.scan,
        reason: 'scan(第 8)仍在该五条之前',
      );
      expect(
        projectPlayKit(<String, Object?>{
          'quietHold': <String, Object?>{'seconds': 15},
          'countdown': <String, Object?>{'seconds': 10},
        }).single.kind,
        PlayKitKind.quietHold,
        reason: 'quietHold(第 13)该在 countdown(第 14)前',
      );
    });

    test(
      '★ 五条之间按真源序:coinFlip → diceRoll → reaction → ballShake → quietHold',
      () {
        final Map<String, Object?> segs = <String, Object?>{
          'coinFlip': <String, Object?>{'kicker': '抛'},
          'diceRoll': <String, Object?>{'kicker': '掷'},
          'reaction': <String, Object?>{'goalMs': 300},
          'ballShake': <String, Object?>{'goal': 30},
          'quietHold': <String, Object?>{'seconds': 15},
        };
        // 逐段做完:每次都应轮到真源序里的下一条(完成判据见 segmentComplete)。
        const Map<String, Map<String, Object?>> doneMarks =
            <String, Map<String, Object?>>{
              'coinFlip': <String, Object?>{'flipped': true},
              'diceRoll': <String, Object?>{'rolled': true},
              'reaction': <String, Object?>{'submitted': true},
              'ballShake': <String, Object?>{'submitted': true},
              'quietHold': <String, Object?>{'submitted': true},
            };
        for (final String name in doneMarks.keys) {
          expect(
            projectPlayKit(segs).single.kind.name,
            name,
            reason: '五条之间的相对次序与 KIT_PRIORITY 不符(卡在 $name)',
          );
          segs[name] = doneMarks[name]!;
        }
      },
    );
  });

  /// 真源 `segmentComplete`(`utils/playkit-view.js:142-171`)里 **没有**
  /// silentOrder / musicCorner 这两支 —— 落到末尾 `return false`。
  ///
  /// 这两张卡原来写死 `complete: true`:`pickPlayKit` 那条「取第一个未完成的段」
  /// 会把它们跳过(同场还有别的未完成段时,玩家永远看不见这两屏)——
  /// 不报错、不打日志,只是这一屏轮不到。
  group('silentOrder / musicCorner 不判完成(真源恒 false)', () {
    test('沉默点单:与时段限定同场时,展示位仍是沉默点单', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'silentOrder': <String, Object?>{'title': '沉默点单', 'rule': '用动作点单'},
        'timeWindow': <String, Object?>{
          'title': '限时开放',
          'openFrom': '10:00',
          'openTo': '18:00',
        },
      }).single;
      expect(card.complete, isFalse);
      expect(
        card.kind,
        PlayKitKind.silentOrder,
        reason: '优先级 2 在 7 之前;判它完成 = 这一屏永远轮不到',
      );
    });

    test('治愈音乐角:同上', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'musicCorner': <String, Object?>{'title': '治愈音乐角', 'trackName': '雨声'},
        'timeWindow': <String, Object?>{
          'title': '限时开放',
          'openFrom': '10:00',
          'openTo': '18:00',
        },
      }).single;
      expect(card.complete, isFalse);
      expect(card.kind, PlayKitKind.musicCorner);
    });
  });

  group('整屏族注册表', () {
    test('★ 五件套都登记了整屏组件(漏一个 = 那个玩法打不开)', () {
      for (final PlayKitKind kind in <PlayKitKind>[
        PlayKitKind.coinFlip,
        PlayKitKind.diceRoll,
        PlayKitKind.reaction,
        PlayKitKind.ballShake,
        PlayKitKind.quietHold,
      ]) {
        expect(
          kPlayKitFullscreenBuilders.containsKey(kind),
          isTrue,
          reason: '$kind 没有整屏组件 —— 服务端下发了也打不开',
        );
        expect(kFullscreenPlayKinds, contains(kind));
      }
    });
  });

  group('宿主层单位换算(serverPayload 的 App 侧镜像)', () {
    test('★ 挑战类开表:game 由 kind 反推,组件漏带也发不出错的开表', () {
      expect(
        playKitServerPayload(
          PlayKitKind.reaction,
          'START_CHALLENGE',
          const <String, Object?>{},
        ),
        <String, Object?>{'game': 'reaction'},
      );
      expect(
        playKitServerPayload(
          PlayKitKind.ballShake,
          'START_CHALLENGE',
          const <String, Object?>{'game': 'wrong'},
        ),
        <String, Object?>{'game': 'ballShake'},
      );
      expect(
        playKitServerPayload(
          PlayKitKind.quietHold,
          'START_CHALLENGE',
          const <String, Object?>{},
        ),
        <String, Object?>{'game': 'quietHold'},
      );
    });

    test('本层还不认识的 kind 原样透传 —— 覆写成空 game 会判「还没开始」', () {
      // countdown / stopwatch 由计时批各自补;这一层先把组件报的 game 透传出去,
      // 不能因为自己不认识就压成 ''(那条开表会被服务端当无效请求)。
      expect(
        playKitServerPayload(
          PlayKitKind.countdown,
          'START_CHALLENGE',
          const <String, Object?>{'game': 'countdown'},
        ),
        <String, Object?>{'game': 'countdown'},
      );
    });

    test('★ reaction 报 times(毫秒数组)→ 服务端收 roundsMs', () {
      expect(
        playKitServerPayload(
          PlayKitKind.reaction,
          'SUBMIT_REACTION',
          const <String, Object?>{
            'times': <int>[250, 210, 330],
          },
        ),
        <String, Object?>{
          'roundsMs': <int>[250, 210, 330],
        },
      );
    });

    test('★ quiethold 报 heldSeconds(秒)→ 服务端收 heldMs(毫秒)', () {
      expect(
        playKitServerPayload(
          PlayKitKind.quietHold,
          'SUBMIT_QUIET_HOLD',
          const <String, Object?>{'heldSeconds': 7},
        ),
        <String, Object?>{'heldMs': 7000},
      );
      expect(
        playKitServerPayload(
          PlayKitKind.quietHold,
          'SUBMIT_QUIET_HOLD',
          const <String, Object?>{'heldSeconds': 2.6},
        ),
        <String, Object?>{'heldMs': 2600},
      );
    });

    test('ballshake 报 hits,原样(它本来就按服务端口径报)', () {
      expect(
        playKitServerPayload(
          PlayKitKind.ballShake,
          'SUBMIT_BALL_SHAKE',
          const <String, Object?>{'hits': 31},
        ),
        <String, Object?>{'hits': 31},
      );
    });

    test('★ 抛硬币 / 掷骰子不带参数:结果服务端算,客户端说了不算', () {
      expect(
        playKitServerPayload(
          PlayKitKind.coinFlip,
          'FLIP_COIN',
          const <String, Object?>{'face': 'HEADS'},
        ),
        isEmpty,
      );
      expect(
        playKitServerPayload(
          PlayKitKind.diceRoll,
          'ROLL_DICE',
          const <String, Object?>{
            'values': <int>[6, 6],
          },
        ),
        isEmpty,
      );
    });

    test('挑战类 game 名只认驼峰那三个,其余给空', () {
      expect(playKitChallengeGameOf(PlayKitKind.reaction), 'reaction');
      expect(playKitChallengeGameOf(PlayKitKind.ballShake), 'ballShake');
      expect(playKitChallengeGameOf(PlayKitKind.quietHold), 'quietHold');
      expect(playKitChallengeGameOf(PlayKitKind.coinFlip), '');
    });
  });
}
