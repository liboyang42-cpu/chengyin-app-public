import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 问答 / 判定族五段进 `projectPlayKit` 之后的那张卡。
///
/// ★ 判据是小程序 `utils/playkit-view.js`:
/// - 完成口径 = `segmentComplete`(qa:finished / branch:currentStep.terminal /
///   estimate:submitted / pricePair:finished / hiddenObject:找齐);
/// - 优先级 = `KIT_PRIORITY`(qa · branch · estimate · pricePair · hiddenObject
///   排在那批展示型之前);
/// - 原始段要跟着卡片走 —— 整屏组件只从 `PlayKitFullscreenContext` 取数据,
///   不许自己去读 provider。
void main() {
  group('五段都能投影出卡片,并带上原始段', () {
    test('qa:finish 才算完,细节是三种模式里的一种', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'qa': <String, Object?>{'mode': 'PICK', 'title': '开在哪一年?', 'finished': false},
      }).single;
      expect(card.kind, PlayKitKind.qa);
      expect(card.title, '开在哪一年?');
      expect(card.detail, '选择作答');
      expect(card.complete, isFalse);
      expect(card.kit['mode'], 'PICK');
    });

    test('branch:走到 terminal 就是走完', () {
      PlayKitCard card = projectPlayKit(<String, Object?>{
        'branch': <String, Object?>{
          'currentStep': <String, Object?>{'title': '雨停了', 'body': '巷口有两条路。', 'terminal': false},
        },
      }).single;
      expect(card.kind, PlayKitKind.branch);
      expect(card.title, '雨停了');
      expect(card.detail, '巷口有两条路。');
      expect(card.complete, isFalse);

      card = projectPlayKit(<String, Object?>{
        'branch': <String, Object?>{
          'currentStep': <String, Object?>{'body': '你走到了河堤。', 'terminal': true},
        },
      }).single;
      expect(card.complete, isTrue);
      expect(card.title, '分支剧情', reason: '这一步没有标题就回落成段名');
    });

    test('estimate:答过了就算完(猜不中也算,别卡住玩家)', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'estimate': <String, Object?>{'question': '多少克?', 'unit': '克', 'submitted': true},
      }).single;
      expect(card.kind, PlayKitKind.estimate);
      expect(card.title, '多少克?');
      expect(card.complete, isTrue);
    });

    test('pricePair:已试几次说清楚,finished 才算完', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'pricePair': <String, Object?>{'title': '哪杯是真的?', 'maxTries': 3, 'attempts': 1},
      }).single;
      expect(card.kind, PlayKitKind.pricePair);
      expect(card.detail, '已试 1 / 3 次');
      expect(card.complete, isFalse);
    });

    test('hiddenObject:有确定答案,必须全找齐才算过', () {
      PlayKitCard card = projectPlayKit(<String, Object?>{
        'hiddenObject': <String, Object?>{'title': '找到那只猫', 'total': 2, 'foundIds': <Object?>['t1']},
      }).single;
      expect(card.kind, PlayKitKind.hiddenObject);
      expect(card.detail, '已找到 1 / 2');
      expect(card.complete, isFalse);

      card = projectPlayKit(<String, Object?>{
        'hiddenObject': <String, Object?>{'title': '找到那只猫', 'total': 2, 'foundIds': <Object?>['t1', 't2']},
      }).single;
      expect(card.complete, isTrue);
    });
  });

  group('优先级(与小程序 KIT_PRIORITY 同序)', () {
    test('qa 排在展示型前面:同一节点挂着两段时先弹问答', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'qa': <String, Object?>{'title': '题'},
        'dailySign': <String, Object?>{'lines': <Object?>['签']},
      }).single;
      expect(card.kind, PlayKitKind.qa);
    });

    test('做完的那段让位给还没做完的', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'qa': <String, Object?>{'title': '题', 'finished': true},
        'dailySign': <String, Object?>{'lines': <Object?>['签']},
      }).single;
      expect(card.kind, PlayKitKind.dailySign);
    });

    test('★分支走到终点同样让位(终点没有选项,再弹一次也没得选)', () {
      final PlayKitCard card = projectPlayKit(<String, Object?>{
        'branch': <String, Object?>{
          'currentStep': <String, Object?>{'body': '你走到了河堤。', 'terminal': true},
        },
        'dailySign': <String, Object?>{'lines': <Object?>['签']},
      }).single;
      expect(card.kind, PlayKitKind.dailySign);
    });

    test('qa 排在 branch 前、hiddenObject 排在这一族最后', () {
      expect(
        projectPlayKit(<String, Object?>{
          'qa': <String, Object?>{'title': '题'},
          'branch': <String, Object?>{'currentStep': <String, Object?>{'title': '剧情'}},
        }).single.kind,
        PlayKitKind.qa,
      );
      expect(
        projectPlayKit(<String, Object?>{
          'hiddenObject': <String, Object?>{'title': '找'},
          'estimate': <String, Object?>{'question': '猜'},
        }).single.kind,
        PlayKitKind.estimate,
      );
    });
  });

  test('★五段都登记成整屏族,注册表里也都有组件', () {
    const List<PlayKitKind> quizKinds = <PlayKitKind>[
      PlayKitKind.qa,
      PlayKitKind.branch,
      PlayKitKind.estimate,
      PlayKitKind.pricePair,
      PlayKitKind.hiddenObject,
    ];
    for (final PlayKitKind kind in quizKinds) {
      expect(kFullscreenPlayKinds, contains(kind), reason: '$kind 必须走整屏宿主');
      expect(
        kPlayKitFullscreenBuilders.containsKey(kind),
        isTrue,
        reason: '$kind 没有组件 —— 玩家做到这一站会停住',
      );
    }
  });
}
