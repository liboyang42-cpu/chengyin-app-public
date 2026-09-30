import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_data.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 问答 / 判定族五屏的**界面契约**。
///
/// 判据逐条对着 `pages/play/components/playkit-{qa,branch,estimate,pricepair,hidden}/
/// index.wxml` 的结构与 `utils/playkit-view.js#serverPayload`:
/// 1. 结果由服务端定 —— 组件不判对错、不算走向、不自己改分;
/// 2. 载荷字段名/单位换算在组件里做完(组件报玩家读的,服务端收判定用的);
/// 3. 拍照是两步 —— `qa:shoot` 绝不塞进 `SUBMIT_QA` 一步直发。
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  PlayKitFullscreenContext ctx(
    PlayKitKind kind,
    Map<String, Object?> kit, {
    bool enabled = true,
    bool acting = false,
    ValueChanged<PlayKitAction>? onAction,
  }) => PlayKitFullscreenContext(
    card: PlayKitCard(kind: kind, title: '', detail: '', kit: kit),
    enabled: enabled,
    acting: acting,
    onAction: onAction,
  );

  List<PlayKitAction> record() {
    final List<PlayKitAction> actions = <PlayKitAction>[];
    return actions;
  }

  group('① 问答 qa —— 三种模式共用一屏', () {
    testWidgets('打字档:输入在,空输入时 CTA 不可点', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              'mode': 'TYPE',
              'title': '这家店开在哪一年?',
            }, onAction: actions.add),
          ),
        ),
      );
      expect(find.byKey(const Key('playkit-qa-input')), findsOneWidget);
      expect(find.text('这家店开在哪一年?'), findsOneWidget);
      final CyNativeButton cta = tester.widget<CyNativeButton>(
        find.byKey(const Key('playkit-qa-cta')),
      );
      expect(cta.onPressed, isNull, reason: '没打字之前没有可提交的东西');
    });

    testWidgets('打字档:提交报 input(不是 optionId)', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{'mode': 'TYPE', 'title': '年份?'}, onAction: actions.add),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('playkit-qa-input')), '1908');
      await tester.pump();
      await tester.tap(find.byKey(const Key('playkit-qa-cta')));
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_QA');
      expect(actions.single.payload, <String, Object?>{'input': '1908'});
      expect(actions.single.payload.containsKey('optionId'), isFalse);
    });

    testWidgets('选项档:选项能被读出来,点了就报 optionId,而且不给对错位', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              'mode': 'PICK',
              'title': '哪一年?',
              'options': <Object?>[
                <String, Object?>{'id': 'a', 'label': '1908'},
                <String, Object?>{'id': 'b', 'label': '1912'},
              ],
            }, onAction: actions.add),
          ),
        ),
      );
      expect(find.text('1908'), findsOneWidget);
      expect(find.text('1912'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-qa-option-b')));
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_QA');
      expect(actions.single.payload, <String, Object?>{'optionId': 'b'});
      // 选项本身即提交:那一档不画一个点了没反应的「提交」按钮。
      expect(find.byKey(const Key('playkit-qa-cta')), findsNothing);
      // 判定没回来之前,屏幕上没有「这就是对的」这种服务端才知道的东西。
      expect(find.textContaining('正确答案'), findsNothing);
      expect(find.textContaining('对的'), findsNothing);
    });

    testWidgets('选项档:判定回来后由服务端给的 passed 决定对错', (WidgetTester tester) async {
      final Map<String, Object?> kit = <String, Object?>{
        'mode': 'PICK',
        'options': <Object?>[
          <String, Object?>{'id': 'a', 'label': '1908'},
          <String, Object?>{'id': 'b', 'label': '1912'},
        ],
      };
      await tester.pumpWidget(host(PlayKitQaView(data: ctx(PlayKitKind.qa, kit))));
      await tester.tap(find.byKey(const Key('playkit-qa-option-a')));
      await tester.pump();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              ...kit,
              'finished': true,
              'passed': true,
              'lastFeedback': '就是 1908 年。',
            }),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('就是 1908 年。'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.check_mark_circled_solid), findsWidgets);
    });

    testWidgets('拍照档:大字是 shotLead(= lead || title),按下只抛 qa:shoot(不带临时路径去 SUBMIT_QA)', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              'mode': 'SHOT',
              'title': '在这棵树下拍一张',
              // 原始段里只有 lead —— `shotLead` 是小程序投影算出来的名字。
              'lead': '和这棵古树合个影',
            }, onAction: actions.add),
            photoPicker: (BuildContext context) async =>
                const PlayKitQaPhoto(path: '/tmp/qa.jpg', size: 2048),
          ),
        ),
      );
      expect(find.text('和这棵古树合个影'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-qa-cta')));
      await tester.pumpAndSettle();
      expect(actions.single.action, kQaShootAction);
      expect(actions.single.action, isNot(kQaSubmitAction));
      expect(actions.single.payload, <String, Object?>{'tempFilePath': '/tmp/qa.jpg', 'size': 2048});
    });

    testWidgets('拍照档没配 lead 时大字回落题干', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitQaView(data: ctx(PlayKitKind.qa, <String, Object?>{'mode': 'SHOT', 'title': '在这棵树下拍一张'})),
        ),
      );
      expect(find.text('在这棵树下拍一张'), findsOneWidget);
    });

    testWidgets('打字档答错清空输入框、按钮改叫「再试一次」;答对叫「继续」', (WidgetTester tester) async {
      const Map<String, Object?> kit = <String, Object?>{'mode': 'TYPE', 'title': '年份?'};
      await tester.pumpWidget(host(PlayKitQaView(data: ctx(PlayKitKind.qa, kit))));
      await tester.enterText(find.byKey(const Key('playkit-qa-input')), '1908');
      await tester.pump();
      expect(find.text('提交'), findsOneWidget);

      // 判定回来:答错(还没用完次数)—— 错答案要清掉,人不用自己先删一遍。
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              ...kit,
              'lastFeedback': '不对。把它清掉,再试一次。',
            }),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<CupertinoTextField>(find.byKey(const Key('playkit-qa-input'))).controller!.text,
        isEmpty,
      );
      expect(find.text('再试一次'), findsOneWidget);

      // 答对:字留着无所谓(格子已锁),按钮按小程序叫「继续」。
      await tester.enterText(find.byKey(const Key('playkit-qa-input')), '1908');
      await tester.pump();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              ...kit,
              'finished': true,
              'passed': true,
              'lastFeedback': '就是 1908 年。',
            }),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<CupertinoTextField>(find.byKey(const Key('playkit-qa-input'))).controller!.text,
        '1908',
      );
      expect(find.text('继续'), findsOneWidget);
    });

    testWidgets('拍照档:用户取消取图就什么都不发', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{'mode': 'SHOT', 'title': '拍一张'}, onAction: actions.add),
            photoPicker: (BuildContext context) async => null,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-qa-cta')));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
    });

    testWidgets('宿主忙(acting)时点不动,也不发第二次', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitQaView(
            data: ctx(PlayKitKind.qa, <String, Object?>{
              'mode': 'PICK',
              'options': <Object?>[
                <String, Object?>{'id': 'a', 'label': 'A'},
              ],
            }, acting: true, onAction: actions.add),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-qa-option-a')), warnIfMissed: false);
      await tester.pump();
      expect(actions, isEmpty);
    });

    testWidgets('空段不炸:没有选项就没有行,题干也还在', (WidgetTester tester) async {
      await tester.pumpWidget(host(PlayKitQaView(data: ctx(PlayKitKind.qa, const <String, Object?>{}))));
      expect(find.byType(PlayKitQaView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('② 分支 branch —— 不判对错,走向服务端说了算', () {
    const Map<String, Object?> step = <String, Object?>{
      'currentStep': <String, Object?>{
        'title': '雨停了',
        'body': '巷口有两条路。',
        'options': <Object?>[
          <String, Object?>{'id': 'left', 'label': '往左'},
          <String, Object?>{'id': 'right', 'label': '往右'},
        ],
      },
    };

    testWidgets('选项带着服务端给的 id 走', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitBranchView(data: ctx(PlayKitKind.branch, step, onAction: actions.add))));
      expect(find.text('巷口有两条路。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-branch-option-left')));
      await tester.pump();
      expect(actions.single.action, 'CHOOSE');
      expect(actions.single.payload, <String, Object?>{'optionId': 'left'});
    });

    testWidgets('选中就锁住:手快连点不会发出第二条', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitBranchView(data: ctx(PlayKitKind.branch, step, onAction: actions.add))));
      await tester.tap(find.byKey(const Key('playkit-branch-option-left')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('playkit-branch-option-right')), warnIfMissed: false);
      await tester.pump();
      expect(actions.length, 1, reason: '第二条会带着上一步的 id 发出去 —— 服务端那边是「当前步骤没有这个选项」');
    });

    testWidgets('走到终点就没有选项了', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitBranchView(
            data: ctx(PlayKitKind.branch, <String, Object?>{
              'currentStep': <String, Object?>{'body': '你走到了河堤。', 'terminal': true},
            }),
          ),
        ),
      );
      expect(find.byKey(const Key('playkit-branch-option-left')), findsNothing);
      expect(find.text('结局'), findsOneWidget, reason: '小程序这一步只有「结局」两个字');
    });

    testWidgets('禁用时点不动', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(PlayKitBranchView(data: ctx(PlayKitKind.branch, step, enabled: false, onAction: actions.add))),
      );
      await tester.tap(find.byKey(const Key('playkit-branch-option-left')), warnIfMissed: false);
      await tester.pump();
      expect(actions, isEmpty);
    });
  });

  group('③ 估数 estimate —— 滚筒只报「我停在哪个数」', () {
    testWidgets('提交报 value(组件内部叫 guess)', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(
          PlayKitEstimateView(
            data: ctx(PlayKitKind.estimate, <String, Object?>{
              'question': '这一锅多少克?',
              'unit': '克',
              'min': 0,
              'max': 1000,
            }, onAction: actions.add),
          ),
        ),
      );
      expect(find.byKey(const Key('playkit-estimate-picker')), findsOneWidget);
      expect(find.text('克'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-estimate-submit')));
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_ESTIMATE');
      // 开局停在量程正中(0–1000 → 500):停在 0 像没开始,停答案附近是作弊。
      expect(actions.single.payload, <String, Object?>{'value': 500});
    });

    testWidgets('答过了就锁住(猜不中也算完,别卡住玩家)', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitEstimateView(
            data: ctx(PlayKitKind.estimate, <String, Object?>{
              'question': '多少克?',
              'min': 0,
              'max': 1000,
              'submitted': true,
            }),
          ),
        ),
      );
      final CyNativeButton cta = tester.widget<CyNativeButton>(
        find.byKey(const Key('playkit-estimate-submit')),
      );
      expect(cta.onPressed, isNull);
      expect(find.text('这一关结束了'), findsOneWidget);
    });

    testWidgets('次数叫 maxAttempts(这一段自己的字段名),0 不画', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitEstimateView(
            data: ctx(PlayKitKind.estimate, <String, Object?>{
              'question': '多少克?',
              'min': 0,
              'max': 1000,
              'maxAttempts': 2,
            }),
          ),
        ),
      );
      expect(find.text('可以错 2 次'), findsOneWidget);

      await tester.pumpWidget(
        host(
          PlayKitEstimateView(
            data: ctx(PlayKitKind.estimate, <String, Object?>{
              'question': '多少克?',
              'min': 0,
              'max': 1000,
            }),
          ),
        ),
      );
      expect(find.textContaining('可以错'), findsNothing, reason: '0 = 不限,写出来反而像有次数');
    });
  });

  group('④ 猜图 pricePair —— 哪张是对的由服务端回', () {
    const Map<String, Object?> kit = <String, Object?>{
      'title': '哪杯是真的?',
      'items': <Object?>[
        <String, Object?>{'id': 'a', 'name': '左杯'},
        <String, Object?>{'id': 'b', 'name': '右杯'},
      ],
      'maxTries': 3,
      'attempts': 1,
    };

    testWidgets('名字在图外面,点了报 pickId', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitPricePairView(data: ctx(PlayKitKind.pricePair, kit, onAction: actions.add))));
      expect(find.text('左杯'), findsOneWidget);
      expect(find.text('还能试 2 次。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-pricepair-item-a')));
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_PRICE_PAIR');
      expect(actions.single.payload, <String, Object?>{'pickId': 'a'});
    });

    testWidgets('判定回来后只有最后点的那张带角标', (WidgetTester tester) async {
      await tester.pumpWidget(host(PlayKitPricePairView(data: ctx(PlayKitKind.pricePair, kit))));
      await tester.tap(find.byKey(const Key('playkit-pricepair-item-a')));
      await tester.pump();
      await tester.pumpWidget(
        host(
          PlayKitPricePairView(
            data: ctx(PlayKitKind.pricePair, <String, Object?>{...kit, 'finished': true, 'passed': true}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('就是它'), findsOneWidget);
    });

    testWidgets('禁用时点不动', (WidgetTester tester) async {
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(PlayKitPricePairView(data: ctx(PlayKitKind.pricePair, kit, enabled: false, onAction: actions.add))),
      );
      await tester.tap(find.byKey(const Key('playkit-pricepair-item-a')), warnIfMissed: false);
      await tester.pump();
      expect(actions, isEmpty);
    });
  });

  group('⑤ 找东西 hiddenObject —— 只报百分比,命中服务端判', () {
    const Map<String, Object?> kit = <String, Object?>{
      'title': '找到那只猫',
      'targets': <Object?>[
        <String, Object?>{'id': 't1', 'label': '三花猫'},
        <String, Object?>{'id': 't2', 'label': '黑猫'},
      ],
      'total': 2,
    };

    testWidgets('点图正中报比例(0–1),不是百分比', (WidgetTester tester) async {
      // 这一屏的全部内容就是那张图:给足高度,让整张图真的在视口里。
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit, onAction: actions.add))));
      final Rect scene = tester.getRect(find.byKey(const Key('playkit-hidden-scene')));
      await tester.tapAt(scene.center);
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_HIDDEN_OBJECT');
      final Map<String, Object?> payload = actions.single.payload;
      expect(payload['x'], closeTo(0.5, 0.01));
      expect(payload['y'], closeTo(0.5, 0.01));
      expect(find.text('三花猫'), findsOneWidget);
      expect(find.textContaining('点一下你觉得藏着的地方'), findsOneWidget);
    });

    testWidgets('点在图外那一下不算(不夹回边界再发)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit, onAction: actions.add))));
      final Rect scene = tester.getRect(find.byKey(const Key('playkit-hidden-scene')));
      // 图之外、但还在整块台面里的位置:GestureDetector 收在图上,这里点不到它。
      await tester.tapAt(Offset(scene.center.dx, scene.top - 20));
      await tester.pump();
      expect(actions, isEmpty);
    });

    testWidgets('没中的那一圈自己散掉(小程序 340ms ≈ CyMotion.slow)', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit, onAction: actions.add))));
      final Rect scene = tester.getRect(find.byKey(const Key('playkit-hidden-scene')));
      await tester.tapAt(scene.center);
      await tester.pump();
      expect(actions.single.action, 'SUBMIT_HIDDEN_OBJECT');

      // 服务端没认这一下:涟漪出来 —— 它是「找过这儿,不对」的反馈。
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit, onAction: actions.add))));
      await tester.pump();
      expect(find.byKey(const Key('playkit-hidden-miss')), findsOneWidget);

      await tester.pump(CyMotion.slow);
      await tester.pump();
      expect(find.byKey(const Key('playkit-hidden-miss')), findsNothing, reason: '涟漪散掉,不留在图上冒充标记');
    });

    testWidgets('★读屏要有非视觉的替代说明(这一屏的全部内容就是一张图)', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit))));
      expect(find.bySemanticsLabel(RegExp('找不到|没找到')), findsWidgets);
      final Finder scene = find.bySemanticsLabel(RegExp('找东西'));
      expect(scene, findsWidgets, reason: '自定义手势必须能被命名(A2)');
      handle.dispose();
    });

    testWidgets('全找齐就是过了', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitHiddenView(
            data: ctx(PlayKitKind.hiddenObject, <String, Object?>{
              ...kit,
              'foundIds': <Object?>['t1', 't2'],
              'lastFeedback': '全找到了',
            }),
          ),
        ),
      );
      expect(find.textContaining('2 / 2'), findsWidgets);
      // 一行是引擎给的小字抬头,一行是服务端那句原话
      expect(find.text('全找到了'), findsNWidgets(2));
    });

    testWidgets('禁用时点不动', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<PlayKitAction> actions = record();
      await tester.pumpWidget(
        host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, kit, enabled: false, onAction: actions.add))),
      );
      final Rect scene = tester.getRect(find.byKey(const Key('playkit-hidden-scene')));
      await tester.tapAt(scene.center);
      await tester.pump();
      expect(actions, isEmpty);
    });

    testWidgets('空段不炸:没图没目标也有占位', (WidgetTester tester) async {
      await tester.pumpWidget(host(PlayKitHiddenView(data: ctx(PlayKitKind.hiddenObject, const <String, Object?>{}))));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('playkit-hidden-scene')), findsOneWidget);
    });
  });

  group('注册表', () {
    testWidgets('五个 kind 各接到自己的那一屏', (WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      const Map<PlayKitKind, Type> want = <PlayKitKind, Type>{
        PlayKitKind.qa: PlayKitQaView,
        PlayKitKind.branch: PlayKitBranchView,
        PlayKitKind.estimate: PlayKitEstimateView,
        PlayKitKind.pricePair: PlayKitPricePairView,
        PlayKitKind.hiddenObject: PlayKitHiddenView,
      };
      want.forEach((PlayKitKind kind, Type type) {
        final Widget? built = buildPlayKitFullscreen(
          captured,
          ctx(kind, const <String, Object?>{}),
        );
        expect(built, isNotNull, reason: '$kind 没登记');
        expect(built.runtimeType, type);
      });
      // 没登记的 kind 走回落:不崩、不报错(与小程序同口径)。
      // ⚠️ 反例**当场从缝里挑**一个还没登记的 kind,不写死名字:写死的那个
      //    (coinFlip / countdown / 本批的 timeWindow,三次实测)会随着后面的
      //    批次登记而红,红的是清单不是契约。缝里一个都不剩时这一条自动让位 ——
      //    「未登记」那种状态本身也就不存在了。
      final PlayKitKind? unregistered = PlayKitKind.values
          .where(
            (PlayKitKind kind) => !kPlayKitFullscreenBuilders.containsKey(kind),
          )
          .firstOrNull;
      if (unregistered != null) {
        expect(
          buildPlayKitFullscreen(
            captured,
            ctx(unregistered, const <String, Object?>{}),
          ),
          isNull,
          reason: '$unregistered 没登记,缝要给 null 而不是崩',
        );
      }
    });
  });
}
