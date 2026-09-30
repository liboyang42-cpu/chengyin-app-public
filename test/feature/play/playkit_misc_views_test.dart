import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_bingo_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_predict_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_random_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_scan_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 节点玩法模板族最后四件(predict / random / scan / bingo)的**界面契约**。
///
/// 判据逐条对着 `utils/playkit-view.js` 的 `ACTION_OF` / `serverPayload` /
/// `segmentComplete`,以及各组件自己的守卫。这里钉的是「少一条不会报错、
/// 只是玩家做完那一下什么也没发生」的那类东西 —— 动作名、载荷、以及**负控**
/// (不该发的时候一条都不许发、不该开的相机一次都不许开)。
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
    bool complete = false,
    ValueChanged<PlayKitAction>? onAction,
  }) => PlayKitFullscreenContext(
    card: PlayKitCard(kind: kind, title: '', detail: '', complete: complete, kit: kit),
    enabled: enabled,
    acting: acting,
    onAction: onAction,
  );

  group('① predict · 竞猜', () {
    testWidgets('没押之前一条动作都不发;押定发 SUBMIT_PREDICT{optionKey}', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitPredictView(
            data: ctx(PlayKitKind.predict, <String, Object?>{
              'question': '押哪家能挺过这个冬天?',
              'options': <Object?>[
                <String, Object?>{'key': 'a', 'label': '左边的店'},
                <String, Object?>{'key': 'b', 'label': '右边的店'},
              ],
            }, onAction: log.add),
          ),
        ),
      );
      expect(find.text('押哪家能挺过这个冬天?'), findsOneWidget);
      expect(log, isEmpty, reason: '还没押定之前,一条动作都不许发');

      await tester.tap(find.byKey(const Key('playkit-predict-option-0')));
      await tester.pump();
      expect(log, isEmpty, reason: '选中一张卡只是本地状态,还不是「押」');

      await tester.tap(find.byKey(const Key('playkit-predict-cta')));
      await tester.pump();
      expect(log.map((PlayKitAction a) => a.action).toList(), <String>['SUBMIT_PREDICT']);
      // 真源 serverPayload:`predict:submit → { optionKey: d.key }` —— 带 key,不带下标
      expect(log.single.payload, <String, Object?>{'optionKey': 'a'});
      expect(find.text('已经押了'), findsOneWidget);
    });

    testWidgets('负控:服务端说押过了(complete)就不再发第二次', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitPredictView(
            data: ctx(
              PlayKitKind.predict,
              <String, Object?>{
                'question': '押哪家?',
                'myOptionKey': 'a',
                'options': <Object?>[
                  <String, Object?>{'key': 'a', 'label': '左边的店'},
                ],
              },
              complete: true,
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-predict-cta')));
      await tester.pump();
      expect(
        log,
        isEmpty,
        reason: '上一批 ② 的同类问题:服务端说做过了还发第二次,玩家会以为刚才那下没生效',
      );
    });

    testWidgets('负控:宿主忙(enabled=false)时按了也不发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitPredictView(
            data: ctx(
              PlayKitKind.predict,
              <String, Object?>{
                'question': '押哪家?',
                'options': <Object?>[
                  <String, Object?>{'key': 'a', 'label': '左边的店'},
                ],
              },
              enabled: false,
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-predict-option-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('playkit-predict-cta')));
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('揭晓:没中时把答案和押注都写出来', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitPredictView(
            data: ctx(PlayKitKind.predict, <String, Object?>{
              'question': '押哪家?',
              'myOptionKey': 'a',
              'settleStatus': 1,
              'settledOption': 'b',
              'won': false,
              'options': <Object?>[
                <String, Object?>{'key': 'a', 'label': '左边的店'},
                <String, Object?>{'key': 'b', 'label': '右边的店'},
              ],
            }),
          ),
        ),
      );
      expect(find.text('没猜中'), findsOneWidget);
      expect(find.text('答案是「右边的店」，你押的是「左边的店」。'), findsOneWidget);
    });

    testWidgets('空态:没有选项时说清怎么才会有,不摆空转盘', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(PlayKitPredictView(data: ctx(PlayKitKind.predict, <String, Object?>{'question': '押哪家?'}))),
      );
      expect(find.textContaining('还没有选项'), findsOneWidget);
      expect(find.text('就押这个'), findsOneWidget);
    });
  });

  group('② random · 抽卡', () {
    testWidgets('盖着的牌:翻开它发 DRAW,且**不带任何参数**', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(PlayKitKind.random, <String, Object?>{
              'drawn': <Object?>[
                <String, Object?>{'id': 'd0', 'label': '第一关', 'content': '把门口的花浇了'},
              ],
              'drawCount': 3,
            }, onAction: log.add),
          ),
        ),
      );
      // 还有两张盖着:牌面写「?」
      expect(find.text('?'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('playkit-random-draw')));
      await tester.pump();
      expect(log.single.action, 'DRAW');
      expect(
        log.single.payload,
        isEmpty,
        reason: '真源 serverPayload:`random:draw → {}` —— 抽哪一件由服务端按权重定,客户端说了不算',
      );
    });

    testWidgets('负控:抽满之后不再发 DRAW', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(
              PlayKitKind.random,
              <String, Object?>{
                'drawn': <Object?>[
                  <String, Object?>{'id': 'd0', 'label': '第一关', 'content': '正文'},
                ],
                'drawCount': 1,
              },
              complete: true,
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-random-draw')));
      await tester.pump();
      expect(log, isEmpty, reason: '服务端说抽满了,再发就是空请求');
    });

    testWidgets('负控:宿主忙时按了也不发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(
              PlayKitKind.random,
              <String, Object?>{'drawCount': 3},
              enabled: false,
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-random-draw')));
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('负控:换一张只是本地翻牌,一条动作都不发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(PlayKitKind.random, <String, Object?>{'drawCount': 3}, onAction: log.add),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-random-next')));
      await tester.pumpAndSettle();
      expect(log, isEmpty, reason: '换一张在真源里也是本地动作(onNext 不发请求)');
    });

    testWidgets('已翻开的牌:点开只读详情,不发动作', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(
              PlayKitKind.random,
              <String, Object?>{
                'drawn': <Object?>[
                  <String, Object?>{'id': 'd0', 'label': '第一关', 'content': '把门口的花浇了'},
                ],
                'drawCount': 1,
              },
              complete: true,
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-random-draw')));
      await tester.pump();
      expect(find.text('回到牌堆'), findsOneWidget);
      expect(find.text('把门口的花浇了'), findsOneWidget);
      expect(log, isEmpty, reason: '翻开已抽到的卡只是读卡背,不是抽卡');
    });

    testWidgets('手势:右滑够阈值 = 翻开(发 DRAW);左滑 = 换一张(不发)', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitRandomView(
            data: ctx(PlayKitKind.random, <String, Object?>{'drawCount': 3}, onAction: log.add),
          ),
        ),
      );
      // 阈值 = 卡宽 22%(卡宽 260 → 57.2)
      await tester.drag(find.byKey(const Key('playkit-random-deck')), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(log.map((PlayKitAction a) => a.action), <String>['DRAW']);

      await tester.drag(find.byKey(const Key('playkit-random-deck')), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(log.length, 1, reason: '左滑只是换一张,不发请求');
    });
  });

  group('③ scan · 扫码', () {
    testWidgets('读到码发 SUBMIT_SCAN{code}', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      int opened = 0;
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{'title': '扫一下门口的码'}, onAction: log.add),
            scanCode: () async {
              opened++;
              return 'CY-123';
            },
          ),
        ),
      );
      expect(find.text('扫一下门口的码'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-scan-frame')));
      // 扫描线未扫到码时是无限循环,pumpAndSettle 永远等不到静止 ——
      // 只冲 future + 重建所需的帧。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(opened, 1);
      expect(log.single.action, 'SUBMIT_SCAN');
      expect(log.single.payload, <String, Object?>{'code': 'CY-123'});
    });

    testWidgets('负控:取消扫码不发动作(那是玩家改主意,不是出事)', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{}, onAction: log.add),
            scanCode: () async => null,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-scan-frame')));
      // 扫描线未扫到码时是无限循环,pumpAndSettle 永远等不到静止 ——
      // 只冲 future + 重建所需的帧。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(log, isEmpty);
    });

    testWidgets('扫完、宿主回填 reply 之后扫描线停转(不留空转 ticker)', (WidgetTester tester) async {
      Widget build(Map<String, Object?> kit) => host(
        PlayKitScanView(
          data: ctx(PlayKitKind.scan, kit),
          scanCode: () async => 'CY-123',
        ),
      );
      await tester.pumpWidget(build(<String, Object?>{}));
      await tester.pump();
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason: '还没扫到时,扫描线本来就在跑(它是「在找」的表达)',
      );

      // 宿主把服务端段换成「已扫」那一版:线不该再空转。
      await tester.pumpWidget(build(<String, Object?>{'reply': '扫过了，收好你的票'}));
      // 走完一帧 + 让停表真正落下来(对照组:还在跑的线过 1s 也仍是 1)。
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: '线已经不在屏上了,继续 repeat 只是烧 ticker',
      );
    });

    testWidgets('负控:已经扫过就不开相机、也不发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      int opened = 0;
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{'reply': '扫过了，收好你的票'}, onAction: log.add),
            scanCode: () async {
              opened++;
              return 'CY-123';
            },
          ),
        ),
      );
      expect(find.text('扫过了，收好你的票'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-scan-frame')));
      await tester.pumpAndSettle();
      expect(opened, 0, reason: '真源 onScan 的守卫:三样回复来一个就不再扫');
      expect(log, isEmpty);
    });

    testWidgets('负控:宿主忙时不开相机、也不发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      int opened = 0;
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{}, enabled: false, onAction: log.add),
            scanCode: () async {
              opened++;
              return 'CY-123';
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-scan-frame')));
      // 扫描线未扫到码时是无限循环,pumpAndSettle 永远等不到静止 ——
      // 只冲 future + 重建所需的帧。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(opened, 0);
      expect(log, isEmpty);
    });

    testWidgets('语音条:宿主没接播放就不画播放键(不摆按下去没声音的假按钮)', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{
              'kind': '语音',
              'audioUrl': 'https://example.com/a.mp3',
              'reply': '听完再进店',
            }),
          ),
        ),
      );
      expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);
      expect(find.text('听完再进店'), findsOneWidget);

      final List<bool> toggles = <bool>[];
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{
              'kind': '语音',
              'audioUrl': 'https://example.com/a.mp3',
              'reply': '听完再进店',
            }),
            onVoiceToggle: toggles.add,
          ),
        ),
      );
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-scan-voice')));
      await tester.pump();
      expect(toggles, <bool>[true]);
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    });

    testWidgets('图片回复:没有图时给出占位,不摆破图', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitScanView(
            data: ctx(PlayKitKind.scan, <String, Object?>{'kind': '图片', 'reply': '这张给你'}),
          ),
        ),
      );
      expect(find.text('扫完给的那张图'), findsOneWidget);
      expect(find.text('这张给你'), findsOneWidget);
    });
  });

  group('④ bingo · 九宫格(本地 kind,不发服务端动作)', () {
    testWidgets('按已亮位序记进度,点未亮的格子给出怎么亮', (WidgetTester tester) async {
      final List<int> taps = <int>[];
      await tester.pumpWidget(
        host(
          PlayKitBingoView(
            data: ctx(PlayKitKind.bingo, <String, Object?>{}),
            title: '本週的格子',
            cellSpecs: const <Map<String, Object?>>[
              <String, Object?>{'t': '门口', 'how': '到店扫码'},
            ],
            labels: const <String>['喝一杯', '拍照'],
            filledPositions: const <int>[0, 1],
            onCellTap: taps.add,
          ),
        ),
      );
      expect(find.text('已完成 2 / 9'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-bingo-cell-4')));
      await tester.pumpAndSettle();
      expect(taps, <int>[4]);
      expect(find.textContaining('这一格装的是'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-bingo-panel-ok')));
      await tester.pumpAndSettle();
      expect(find.text('知道了'), findsNothing);
    });

    testWidgets('扫码格说清为什么只认扫码', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitBingoView(
            data: ctx(PlayKitKind.bingo, <String, Object?>{}),
            title: '本週的格子',
            cellSpecs: const <Map<String, Object?>>[
              <String, Object?>{'t': '门口', 'how': '到店扫码'},
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-bingo-cell-0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS 可以伪造'), findsOneWidget);
    });

    testWidgets('负控:已亮的格子不再弹说明,也不回调', (WidgetTester tester) async {
      final List<int> taps = <int>[];
      await tester.pumpWidget(
        host(
          PlayKitBingoView(
            data: ctx(PlayKitKind.bingo, <String, Object?>{}),
            title: '本週的格子',
            labels: const <String>['喝一杯'],
            filledPositions: const <int>[0],
            onCellTap: taps.add,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('playkit-bingo-cell-0')));
      await tester.pumpAndSettle();
      expect(taps, isEmpty, reason: '那一格的事已经做完了(真源 onCell 的守卫)');
      expect(find.text('知道了'), findsNothing);
    });

    testWidgets('横幅:连成一条线才出,没连上不出', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitBingoView(
            data: ctx(PlayKitKind.bingo, <String, Object?>{}),
            title: '本週的格子',
            labels: const <String>['甲', '乙', '丙'],
            filledPositions: const <int>[0, 1, 2],
            lineReward: '一杯手冲',
          ),
        ),
      );
      expect(find.text('连成一条线 · 一杯手冲'), findsOneWidget);
    });
  });
}
