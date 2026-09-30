// 漫游首屏横滑卡族「几何 + 字级」度量门禁(a5-ios27-roam-intro-98)。
//
// 两件事:
//  1. A5 外观复核补差 —— 真源 `pages/roam/index.wxss` 的 `.intro-card` 是白卡
//     (action-primary-bg)「亮岛」,卡内只用**反色语义**(wxss:750 「白卡内的
//     浅灰图标槽 #F2F2F2」、`.intro-card__title` white-space:nowrap 单行截断)。
//     这些是白底可读性的根,不是可选装饰,钉死防回归。
//  2. roam-4 N8(P2)代码级判定 —— 合成手势连滑 6 次停在 offset≈310pt、
//     第三卡只剩 ~15pt 露出,疑「布局缺陷 vs 模拟器合成手势动量限制」。
//     布局对不对可以在 widget 层量出来:maxScrollExtent 若与
//     「3 卡总宽 − 视口宽」自洽,且滑到 max 时第三卡能完整露出,
//     则判合成手势通道限制(销账,手指复测留 b1-sim 欠账);不自洽则是布局缺陷。

import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _kBand = Key('roam-intro-cards');
const Key _kNearby = Key('roam-intro-card-nearby-teams');

/// 手机竖屏 402×874(iPhone 16 Pro 宽度),横滑卡宽度公式按屏宽取值,
/// 默认 800×600 测试画布会把「卡比视口窄」的观感测歪。
final Size _kPhone = const Size(402, 874);

Future<void> _pumpIntro(
  WidgetTester tester, {
  List<RoamIntroTopic> topics = const <RoamIntroTopic>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RoamIntroView(
              sessions: const <RoamSession>[],
              topics: topics,
              onStart: () {},
              onStartAndShoot: () {},
              onOpenRules: () {},
              onOpenHistory: () {},
              onOpenStampAlbum: () {},
              onOpenBadges: () {},
              onOpenTopic: (_) {},
              onOpenOfficialEvents: () {},
              onDiscoverShops: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

ScrollPosition _bandPosition(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(_kBand),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
}

/// 测试环境 cacheExtent=0(widget test 确定性配置),尾部未构建卡的
/// maxScrollExtent 是滑均值**估算**;真机默认 cacheExtent=500 会把三张卡
/// 全部纳入布局拿到精确值。滚到底让估算兑现成精确值再读数 —— 量的是
/// 布局真值,不是估算法。
Future<double> _scrollToTrueEnd(WidgetTester tester) async {
  double last = -1;
  for (var i = 0; i < 8 && _bandPosition(tester).pixels != last; i++) {
    last = _bandPosition(tester).pixels;
    _bandPosition(tester).jumpTo(_bandPosition(tester).maxScrollExtent);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return _bandPosition(tester).maxScrollExtent;
}

Rect _bandRect(WidgetTester tester) => tester.getRect(find.byKey(_kBand));

void main() {
  group('N8 几何测量:横滑卡带可滚到第三卡完整露出', () {
    testWidgets('maxScrollExtent 与「3 卡总宽 − 视口宽」自洽', (
      WidgetTester tester,
    ) async {
      await _pumpIntro(tester);

      // 第三卡在 offset 0 可能还没被懒构建上树,用必在树上的第二张量卡宽。
      final Size cardSize = tester.getSize(
        find.byKey(const Key('roam-intro-card-history')),
      );
      expect(
        cardSize.width,
        _kPhone.width - CyTokens.space7 * 2,
        reason: '卡宽公式 = 屏宽 − 2×space7(留出邻卡 peek)',
      );
      final double viewport = _bandRect(tester).width;
      expect(
        viewport,
        _kPhone.width - CyTokens.pageX * 2,
        reason: '卡带视口 = 屏宽 − 2×pageX(卡带不贴边,归 A5 复核口径)',
      );
      expect(
        _bandRect(tester).height,
        CyTokens.space5 * 4,
        reason: '真源 .intro-cards 定高 192rpx=96pt,复核曾量出 120pt 偏高',
      );

      // 回落卡组(自由漫游/足迹记录/附近的队伍)两两间隔 space3。
      final double contentWidth = cardSize.width * 3 + CyTokens.space3 * 2;
      expect(
        await _scrollToTrueEnd(tester),
        moreOrLessEquals(contentWidth - viewport, epsilon: 0.5),
        reason: 'maxScroll 不自洽 ⇒ 布局缺陷;自洽 ⇒ roam-4 N8 判合成手势动量限制',
      );
    });

    testWidgets('滑到 maxScrollExtent 时第三卡完整落在视口内', (WidgetTester tester) async {
      await _pumpIntro(tester);
      await _scrollToTrueEnd(tester);

      final Rect band = _bandRect(tester);
      final Rect nearby = tester.getRect(find.byKey(_kNearby));
      expect(
        nearby.right,
        lessThanOrEqualTo(band.right + 0.5),
        reason: '末卡右缘必须能贴齐视口右缘 —— 滑到头还露不全才是布局缺陷',
      );
      expect(nearby.left, greaterThanOrEqualTo(band.left));
      expect(nearby.width, _kPhone.width - CyTokens.space7 * 2);
    });

    testWidgets('offset 0 时下一卡 peek 出邻卡,证横滑可发现性仍在', (
      WidgetTester tester,
    ) async {
      await _pumpIntro(tester);
      // 「足迹记录」是第二张卡,开局就应露一截,不然用户不知道能滑。
      final Rect second = tester.getRect(
        find.byKey(const Key('roam-intro-card-history')),
      );
      final Rect band = _bandRect(tester);
      expect(second.left, lessThan(band.right));
      expect(second.right, greaterThan(band.right));
    });
  });

  group('白卡「亮岛」反色语义与字级(真源 .intro-card)', () {
    testWidgets('图标槽底是反色压暗,不是透明白(白卡上透明白=完全不可见)', (WidgetTester tester) async {
      await _pumpIntro(tester);
      final Container slot = tester.widget<Container>(
        find.descendant(
          // 三张卡同一个 _IntroCard 组件;第三卡在 offset 0 可能未上树,量必建的这张。
          of: find.byKey(const Key('roam-intro-card-history')),
          matching: find.byKey(const Key('roam-intro-card-icon-slot')),
        ),
      );
      final BoxDecoration deco = slot.decoration! as BoxDecoration;
      expect(
        deco.color,
        CyTokens.actionPrimaryFg.withValues(alpha: 0.08),
        reason:
            'wxss:750 白卡内浅灰图标槽(#F2F2F2)用反色语义实现;'
            'textPrimary 在近白卡上是 8% 白叠白,渲成「没有槽」',
      );
      expect(deco.borderRadius, BorderRadius.circular(CyTokens.radiusMd));
    });

    testWidgets('标题走 typeCardTitle 梯级且单行截断;副标题 typeCaption + 白底专用压暗色', (
      WidgetTester tester,
    ) async {
      await _pumpIntro(
        tester,
        topics: const <RoamIntroTopic>[
          RoamIntroTopic(
            title: '一条非常长的章节名称会一直长下去看它截不截断',
            subtitle: '按顺序走完整条路线',
            route: '/play/9',
            freeExplore: false,
          ),
        ],
      );

      final Text title = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('roam-intro-topic-0')),
          matching: find.text('一条非常长的章节名称会一直长下去看它截不截断'),
        ),
      );
      expect(title.style?.fontSize, CyTokens.typeCardTitle);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(
        title.maxLines,
        1,
        reason: '.intro-card__title white-space:nowrap',
      );
      expect(title.overflow, TextOverflow.ellipsis);

      final Text sub = tester.widget<Text>(
        find.descendant(
          of: find.byKey(_kNearby),
          matching: find.text('看看附近在招募的队伍'),
        ),
      );
      expect(sub.style?.fontSize, CyTokens.typeCaption);
      expect(sub.maxLines, 2, reason: '.intro-card__sub -webkit-line-clamp:2');
      expect(
        sub.style?.color,
        CyTokens.actionPrimaryFg.withValues(alpha: 0.58),
        reason: '#6B6B6B 压白底 5.3:1 达标(wxss:758 注释),不许换回 textTertiary',
      );
    });

    testWidgets('回落三卡文案逐字对齐真源 introCards(index.js:289-293)', (
      WidgetTester tester,
    ) async {
      await _pumpIntro(tester);
      expect(find.text('自由漫游'), findsOneWidget);
      expect(find.text('走到哪，雾散到哪。没有固定路线。'), findsOneWidget);
      expect(find.text('足迹记录'), findsOneWidget);
      // 复核曾丢后半句隐私承诺 —— 文案 1:1 属结构层,钉死。
      expect(find.text('回看每一次走过的城市片段。记录只保存在这台手机上。'), findsOneWidget);
      // 第三卡进带需先滑到尾部,文案/路由由 team_nearby_entry_test 逐字钉。
    });

    testWidgets('粗体文本档(textScale 1.3)+ 长章节名不撑破卡带(Row 不溢出不红屏)', (
      WidgetTester tester,
    ) async {
      await _pumpIntro(
        tester,
        textScale: 1.3,
        topics: const <RoamIntroTopic>[
          RoamIntroTopic(
            title: '超长章节名称超长章节名称超长章节名称超长章节名称',
            subtitle: '任选一处开始探索任选一处开始探索任选一处开始探索',
            route: '/play/9',
            freeExplore: true,
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      final Rect card = tester.getRect(
        find.byKey(const Key('roam-intro-topic-0')),
      );
      expect(
        card.height,
        closeTo(CyTokens.space5 * 4 + (1.3 - 1) * CyTokens.space8, 0.5),
        reason: '卡带高度已按 textScaler 让位,超出的字截断而不是溢出',
      );
    });
  });
}
