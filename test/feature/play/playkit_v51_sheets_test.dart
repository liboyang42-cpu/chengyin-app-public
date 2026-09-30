import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_daily_sign_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_silent_order_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_step_row.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_steps_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter_test/flutter_test.dart';

/// v5.1 半屏壳剩下三件(`silentOrder` / `dailySign` / `steps`)的**界面契约**。
///
/// 判据来自真源各组件自己的注释与 `utils/playkit-view.js` 的
/// `ACTION_OF` / `serverPayload` / `buildSteps` / `buildDailySign`。
/// 这里钉的是两类东西:
/// ① **接线** —— 组件在册、在产、壳的形态与真源一致;
/// ② **不该做的事** —— 没有来源的步数不提交、没刮开不写留言、判定不在这一屏。
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  PlayKitFullscreenContext ctx(
    PlayKitKind kind,
    Map<String, Object?> kit, {
    String title = '',
    String detail = '',
    String eyebrow = '',
    bool enabled = true,
    bool acting = false,
    bool complete = false,
    ValueChanged<PlayKitAction>? onAction,
  }) => PlayKitFullscreenContext(
    card: PlayKitCard(
      kind: kind,
      title: title,
      detail: detail,
      eyebrow: eyebrow,
      complete: complete,
      kit: kit,
    ),
    enabled: enabled,
    acting: acting,
    onAction: onAction,
  );

  group('① 接线:三件都在册,壳的形态按真源分', () {
    test('注册表里有这三件', () {
      expect(hasPlayKitComponent(PlayKitKind.silentOrder), isTrue);
      expect(hasPlayKitComponent(PlayKitKind.dailySign), isTrue);
      expect(hasPlayKitComponent(PlayKitKind.steps), isTrue);
    });

    test('只有 dailySign 是整屏 —— 另两件真源的壳是 cy-sheet', () {
      // playkit-dailysign/index.wxml 自带 .ds__nav(页头 + 日期)
      expect(playKitWantsFullscreen(PlayKitKind.dailySign), isTrue);
      expect(playKitWantsFullscreen(PlayKitKind.silentOrder), isFalse);
      expect(playKitWantsFullscreen(PlayKitKind.steps), isFalse);
    });

    test('投影把原始段挂到卡上(通用字段装不下题面)', () {
      final List<PlayKitCard> cards = projectPlayKit(<String, Object?>{
        'silentOrder': <String, Object?>{'title': '安静点单', 'rule': '只比划'},
      });
      expect(cards, hasLength(1));
      expect(cards.single.kind, PlayKitKind.silentOrder);
      expect(cards.single.kit['rule'], '只比划');
    });
  });

  group('② silentOrder · 沉默点单', () {
    testWidgets('没给见证码地址 → 「见证码生成中」,不补一张假码', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(PlayKitSilentOrderView(data: ctx(PlayKitKind.silentOrder, <String, Object?>{}))),
      );
      expect(find.text('见证码生成中'), findsOneWidget);
      expect(find.text('见证码 · 店员猜中后扫这里'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('正计时从服务端给的 elapsedSeconds 续,每秒 +1', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitSilentOrderView(
            data: ctx(PlayKitKind.silentOrder, <String, Object?>{'elapsedSeconds': 12}),
          ),
        ),
      );
      expect(find.text('已表演 00:12'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('已表演 00:13'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('认输:抛 giveup,并把正计时停住', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitSilentOrderView(
            data: ctx(PlayKitKind.silentOrder, <String, Object?>{}, onAction: log.add),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('已表演 00:01'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playkit-silent-order-giveup')));
      await tester.pump();
      expect(log, hasLength(1));
      expect(log.single.action, 'giveup');
      final String frozen = tester
          .widget<Text>(find.textContaining('已表演'))
          .data!;
      await tester.pumpWidget(const SizedBox());
      expect(frozen, '已表演 00:01');
    });

    testWidgets('负控:宿主忙的时候认输按不动', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitSilentOrderView(
            data: ctx(PlayKitKind.silentOrder, <String, Object?>{}, enabled: false),
          ),
        ),
      );
      expect(
        tester
            .widget<CyNativeButton>(find.byKey(const Key('playkit-silent-order-giveup')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('③ dailySign · 今日城市签', () {
    test('票面字段逐条对齐 buildDailySign', () {
      final PlayKitDailySignTicket ticket = PlayKitDailySignTicket.fromSegment(
        <String, Object?>{
          'address': '苏州河 · 乍浦路桥',
          'serial': 7,
          'lines': <Object?>['七点才开', '', '别去早了'],
          'signer': '',
          'claimedDate': '2026-09-18',
          'myText': '豆浆在左手边',
        },
        now: DateTime(2026, 9, 18, 9, 5),
      );
      expect(ticket.dateLabel, '09 / 18');
      expect(ticket.serialLabel, 'NO. 0007');
      // 空行要丢掉 —— 真源 lines 是「服务端断好行的数组」,空串会占一行
      expect(ticket.lines, <String>['七点才开', '别去早了']);
      expect(ticket.textMax, 40);
      expect(ticket.claimed, isTrue);
      expect(ticket.myText, '豆浆在左手边');
      // 签名为空时组件自己标「这一站的发起人」,那是标签不是数据
      expect(ticket.signer, isEmpty);
      expect(PlayKitDailySignTicket.openTimeLabel(DateTime(2026, 9, 18, 9, 5)), '09:05');
    });

    testWidgets('没下发签文 → 不出刮层,也不出现空雾', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(PlayKitDailySignView(data: ctx(PlayKitKind.dailySign, <String, Object?>{}))),
      );
      expect(find.text('留给你的一句'), findsNothing);
      expect(find.text('直接揭示'), findsNothing);
      expect(find.text('这一站的发起人'), findsOneWidget);
    });

    testWidgets('三段式:没刮开没有输入框;刮开后写不了字就不能提交', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitDailySignView(
            data: ctx(
              PlayKitKind.dailySign,
              <String, Object?>{'lines': <Object?>['七点才开']},
              onAction: log.add,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('playkit-daily-sign-note')), findsNothing);
      expect(find.text('刮开 TA 留给你的那句'), findsOneWidget);

      await tester.tap(find.text('直接揭示'));
      await tester.pump();
      expect(find.text('留给你的一句'), findsOneWidget);
      expect(find.text('也给下一个来这里的人留一句'), findsOneWidget);
      // 写了字才能「留下」(真源 _syncStep 的唯一一条规则)
      expect(
        tester
            .widget<CyNativeButton>(find.byKey(const Key('playkit-daily-sign-accept')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('提交的载荷是 CLAIM_DAILY_SIGN{text, photoUrl}', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitDailySignView(
            data: ctx(
              PlayKitKind.dailySign,
              <String, Object?>{'lines': <Object?>['七点才开']},
              onAction: log.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('直接揭示'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('playkit-daily-sign-note')),
        '豆浆在左手边',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('playkit-daily-sign-accept')));
      await tester.pump();
      expect(log, hasLength(1));
      expect(log.single.action, 'CLAIM_DAILY_SIGN');
      expect(log.single.payload['text'], '豆浆在左手边');
      expect(log.single.payload['photoUrl'], '');
    });

    testWidgets('已留过 → 只读回看:没有输入框,也没有第二颗 CTA', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitDailySignView(
            data: ctx(PlayKitKind.dailySign, <String, Object?>{
              'claimedDate': '2026-09-18',
              'myText': '豆浆在左手边',
              'lines': <Object?>['七点才开'],
            }),
          ),
        ),
      );
      expect(find.text('你留给下一个人的'), findsOneWidget);
      expect(find.text('豆浆在左手边'), findsOneWidget);
      expect(find.byKey(const Key('playkit-daily-sign-note')), findsNothing);
      expect(find.byKey(const Key('playkit-daily-sign-accept')), findsNothing);
      expect(find.text('留下了，下一个来的人会看到'), findsOneWidget);
    });
  });

  group('④ steps · 计步挑战', () {
    test('纯逻辑:CO₂ 四舍五入 / 还差多少的三档措辞', () {
      expect(playKitStepsCo2Gram(4286), 129);
      expect(playKitStepsCo2Label(4286), '已减排 129g CO₂ · 约等于一杯奶茶的吸管');
      expect(playKitStepsCo2Gram(-5), 0);
      expect(
        playKitStepsRemainLabel(steps: 4286, goal: 6000, xp: 20),
        '再走 1,714 步,爪印落章 + 20 XP',
      );
      // 没配 XP 就不报「+ 0 XP」
      expect(playKitStepsRemainLabel(steps: 4286, goal: 6000), '再走 1,714 步,爪印落章');
      expect(playKitStepsRemainLabel(steps: 6000, goal: 6000), '已达标,爪印已落章');
    });

    testWidgets('千分位读数 + 目标 + 图标步骤行', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitStepsView(
            data: ctx(PlayKitKind.steps, <String, Object?>{
              'todaySteps': 4286,
              'goal': 6000,
              'xp': 20,
            }),
          ),
        ),
      );
      expect(find.text('4,286'), findsOneWidget);
      expect(find.text('/ 6,000 步'), findsOneWidget);
      // 图标步骤行(真源 utils/playkit-steps.js 的 STEPS.steps)
      expect(find.text('走起来'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('落章'), findsOneWidget);
      expect(find.text('再走 1,714 步,爪印落章 + 20 XP'), findsOneWidget);
    });

    testWidgets('负控:没有步数来源,就没有「刷新步数」这颗提交钮', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitStepsView(
            data: ctx(PlayKitKind.steps, <String, Object?>{'todaySteps': 100, 'goal': 6000}),
          ),
        ),
      );
      expect(find.text('刷新步数'), findsNothing);
      expect(find.byType(CyNativeButton), findsNothing);
      expect(find.textContaining('App 不会伪造步数提交'), findsOneWidget);
    });

    testWidgets('空态:服务端一个字段都没给也不崩,读数是 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(PlayKitStepsView(data: ctx(PlayKitKind.steps, <String, Object?>{}))),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('/ 0 步'), findsOneWidget);
    });
  });

  group('⑤ 图标步骤行(真源 utils/playkit-steps.js)', () {
    test('只登记真源里真正有渲染位的两个 kind', () {
      expect(playKitStepIcons(PlayKitKind.blindTaste), hasLength(3));
      expect(playKitStepIcons(PlayKitKind.steps), hasLength(3));
      // 真源表里还有 6 种,但 App 侧没有渲染位 —— 不进来当死数据
      expect(playKitStepIcons(PlayKitKind.dailySign), isEmpty);
      expect(playKitStepIcons(PlayKitKind.silentOrder), isEmpty);
    });

    test('读屏文案:服务端那句优先,拿不到才用标签拼', () {
      expect(playKitStepsA11y(PlayKitKind.steps, '走够 6000 步'), '走够 6000 步');
      expect(playKitStepsA11y(PlayKitKind.steps), '玩法步骤:1 走起来,2 刷新,3 落章');
      expect(playKitStepsA11y(PlayKitKind.dailySign), '');
    });
  });
}
