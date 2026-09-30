// 发布选择面 —— 对应小程序 components/cy/publish-sheet。
// Apple 原生化只负责 Sheet、关闭控件和交互反馈；四卡几何、插画、
// 顺序、文案、锁定态和点击目标一律以小程序为真源。

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import 'publish_capability.dart';

enum PublishCardArt { topic, template, activity, locked }

class PublishCard {
  const PublishCard({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.route,
    required this.unlocked,
    required this.art,
    this.lockedWhy,
    this.lockedHow,
  });

  final String title;
  final String subtitle;
  final String tag;
  final String route;
  final bool unlocked;
  final PublishCardArt art;
  final String? lockedWhy;
  final String? lockedHow;
}

List<PublishCard> publishCards(PublishCapability cap) => <PublishCard>[
  const PublishCard(
    title: '发布主题',
    subtitle: '一条城市路线',
    tag: '从灵感到可玩，只差一次发布',
    route: '/publish',
    unlocked: true,
    art: PublishCardArt.topic,
  ),
  const PublishCard(
    title: '发布模板',
    subtitle: '一个节点玩法',
    tag: '沉淀可复用的玩法，给路线当积木',
    route: '/template/intro',
    unlocked: true,
    art: PublishCardArt.template,
  ),
  PublishCard(
    title: '发布',
    subtitle: '单场活动',
    tag: '由俱乐部主理人发起的线下体验',
    route: '/publish/activity',
    unlocked: cap.isClubLeader,
    art: cap.isClubLeader ? PublishCardArt.activity : PublishCardArt.locked,
    lockedWhy: '仅俱乐部主理人可发布',
    lockedHow: '成为主理人后解锁',
  ),
  PublishCard(
    title: '创建',
    subtitle: '优惠券',
    tag: '先定义商家券，再配置到节点与主题奖励',
    route: '/merchant/coupons',
    unlocked: cap.isMerchant,
    art: cap.isMerchant ? PublishCardArt.template : PublishCardArt.locked,
    lockedWhy: '商家可创建与核销优惠券',
    lockedHow: '完成商家入驻后解锁',
  ),
];

Future<void>? _activePublishChooser;
BuildContext? _activePublishChooserContext;

Future<void> showPublishChooser(
  BuildContext context, {
  ValueChanged<String>? onNavigate,
}) {
  final Future<void>? active = _activePublishChooser;
  if (active != null && (_activePublishChooserContext?.mounted ?? false)) {
    return active;
  }

  final Future<void> operation = _showPublishChooser(
    context,
    onNavigate: onNavigate,
  );
  _activePublishChooser = operation;
  _activePublishChooserContext = context;
  return operation.whenComplete(() {
    if (identical(_activePublishChooser, operation)) {
      _activePublishChooser = null;
      _activePublishChooserContext = null;
    }
  });
}

Future<void> _showPublishChooser(
  BuildContext context, {
  ValueChanged<String>? onNavigate,
}) async {
  await ProviderScope.containerOf(
    context,
  ).read(publishCapabilityProvider.future);
  if (!context.mounted) return;

  await showCupertinoSheet<void>(
    context: context,
    enableDrag: true,
    showDragHandle: false,
    topGap: 0.3,
    scrollableBuilder:
        (BuildContext sheetContext, ScrollController scrollController) =>
            Material(
              color: Colors.transparent,
              child: PublishChooserView(
                onNavigate: (String route) {
                  Navigator.of(sheetContext).pop();
                  if (onNavigate != null) {
                    onNavigate(route);
                  } else if (context.mounted) {
                    context.push(route);
                  }
                },
              ),
            ),
  );
}

enum _ChooserLevel { cards, topicMode, topicAbility }

class PublishChooserView extends ConsumerStatefulWidget {
  const PublishChooserView({super.key, this.onNavigate});

  final ValueChanged<String>? onNavigate;

  @override
  ConsumerState<PublishChooserView> createState() => _PublishChooserViewState();
}

class _PublishChooserViewState extends ConsumerState<PublishChooserView> {
  _ChooserLevel _level = _ChooserLevel.cards;
  int _mode = 1;
  int _cardIndex = 0;

  void _navigate(String route) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(route);
      return;
    }
    Navigator.of(context).pop();
    context.push(route);
  }

  void _back() {
    setState(() {
      _level = _level == _ChooserLevel.topicAbility
          ? _ChooserLevel.topicMode
          : _ChooserLevel.cards;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final PublishCapability cap =
        ref.watch(publishCapabilityProvider).value ?? const PublishCapability();
    final List<PublishCard> cards = publishCards(cap);
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.7,
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CyTokens.radiusLg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Row(
                  children: <Widget>[
                    if (_level != _ChooserLevel.cards)
                      CyNativeIconButton(
                        key: const Key('publish-chooser-back'),
                        label: '返回',
                        icon: const CyNativeButtonIcon(
                          sfSymbol: 'chevron.left',
                          fallback: CupertinoIcons.chevron_back,
                        ),
                        onPressed: _back,
                      ),
                    const Spacer(),
                    _PublishCloseButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: switch (_level) {
                _ChooserLevel.cards => Column(
                  children: <Widget>[
                    Expanded(
                      child: PageView(
                        key: const Key('publish-chooser-cards'),
                        onPageChanged: (int value) =>
                            setState(() => _cardIndex = value),
                        children: <Widget>[
                          for (int i = 0; i < cards.length; i++)
                            _PublishCardView(
                              cards[i],
                              onPressed: () {
                                if (i == 0) {
                                  setState(
                                    () => _level = _ChooserLevel.topicMode,
                                  );
                                } else {
                                  _navigate(cards[i].route);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space3),
                      child: _PageDots(
                        current: _cardIndex,
                        count: cards.length,
                      ),
                    ),
                  ],
                ),
                _ChooserLevel.topicMode => _TopicModeStep(
                  onSelected: (int value) => setState(() {
                    _mode = value;
                    _level = _ChooserLevel.topicAbility;
                  }),
                ),
                _ChooserLevel.topicAbility => _TopicAbilityStep(
                  mode: _mode,
                  capability: cap,
                  onQuick: () => _navigate('/publish?mode=$_mode'),
                  onPro: () => _navigate('/publish/pro?mode=$_mode'),
                ),
              },
            ),
            const SizedBox(height: CyTokens.space3),
          ],
        ),
      ),
    );
  }
}

class _PublishCloseButton extends StatelessWidget {
  const _PublishCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CyNativeIconButton(
    key: const Key('publish-chooser-close'),
    label: '关闭发布选择',
    icon: const CyNativeButtonIcon(
      sfSymbol: 'xmark',
      fallback: CupertinoIcons.xmark,
    ),
    onPressed: onPressed,
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '第 ${current + 1} 张，共 $count 张',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            AnimatedContainer(
              key: Key('publish-chooser-dot-$i'),
              duration: reduceMotion
                  ? Duration.zero
                  : CyMotion.fast,
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? p.textPrimary : p.borderStrong,
              ),
            ),
        ],
      ),
    );
  }
}

class _PublishCardView extends StatelessWidget {
  const _PublishCardView(this.card, {required this.onPressed});

  final PublishCard card;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        0,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool needsScroll =
              MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
              constraints.maxHeight < 360;
          final Widget contents = _cardContents(
            context,
            p,
            flexibleArtwork: !needsScroll,
          );
          return needsScroll
              ? SingleChildScrollView(child: contents)
              : contents;
        },
      ),
    );
  }

  Widget _cardContents(
    BuildContext context,
    CyPalette p, {
    required bool flexibleArtwork,
  }) {
    final Widget artwork = Center(
      child: SizedBox(
        height: flexibleArtwork ? 150 : 112,
        child: AspectRatio(
          key: Key('publish-card-art-${card.subtitle}'),
          aspectRatio: 340 / 215,
          child: CustomPaint(
            painter: _PublishArtPainter(art: card.art, color: p.textPrimary),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          card.title,
          style: TextStyle(
            fontSize: CyTokens.typeDisplay,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        Text(
          card.subtitle,
          style: TextStyle(
            fontSize: CyTokens.typeDisplay,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        if (flexibleArtwork) Expanded(child: artwork) else artwork,
        if (card.unlocked)
          Text(
            card.tag,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: p.textSecondary,
            ),
          )
        else ...<Widget>[
          Text(
            card.lockedWhy!,
            key: Key('publish-card-locked-${card.subtitle}'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.lockedHow!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: p.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space4),
        Semantics(
          button: true,
          enabled: card.unlocked,
          label:
              '${card.title}，${card.subtitle}，${card.unlocked ? '开始创建' : '暂未解锁'}',
          onTap: card.unlocked ? onPressed : null,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 44,
              child: CupertinoButton.filled(
                key: Key('publish-card-cta-${card.subtitle}'),
                padding: EdgeInsets.zero,
                onPressed: card.unlocked ? onPressed : null,
                child: Text(card.unlocked ? '开始创建' : '暂未解锁'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PublishArtPainter extends CustomPainter {
  const _PublishArtPainter({required this.art, required this.color});

  final PublishCardArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 340, size.height / 215);
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (art) {
      case PublishCardArt.topic:
        canvas.drawCircle(const Offset(70, 80), 52, stroke);
        canvas.save();
        canvas.translate(168, 62);
        canvas.rotate(12 * math.pi / 180);
        canvas.translate(-168, -62);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(130, 24, 76, 76),
            const Radius.circular(14),
          ),
          stroke,
        );
        canvas.restore();
        canvas.drawPath(
          Path()
            ..moveTo(30, 158)
            ..lineTo(70, 128)
            ..lineTo(110, 158)
            ..lineTo(95, 203)
            ..lineTo(45, 203)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(220, 160), 18, stroke);
        canvas.drawCircle(const Offset(250, 132), 9, stroke);
        _drawDashedPath(
          canvas,
          Path()
            ..moveTo(122, 150)
            ..cubicTo(160, 120, 200, 120, 238, 96),
          stroke,
        );
      case PublishCardArt.template:
        for (final Rect rect in <Rect>[
          const Rect.fromLTWH(60, 24, 90, 70),
          const Rect.fromLTWH(190, 24, 90, 70),
          const Rect.fromLTWH(60, 124, 90, 70),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(14)),
            stroke,
          );
        }
        _drawDashedPath(
          canvas,
          Path()..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(190, 124, 90, 70),
              const Radius.circular(14),
            ),
          ),
          stroke,
        );
        final Paint fill = Paint()..color = color;
        canvas.drawCircle(const Offset(170, 59), 6, fill);
        canvas.drawCircle(const Offset(170, 159), 6, fill);
        canvas.drawLine(const Offset(105, 94), const Offset(105, 124), stroke);
        canvas.drawLine(const Offset(235, 94), const Offset(235, 124), stroke);
      case PublishCardArt.activity:
        canvas.drawPath(
          Path()
            ..moveTo(90, 52)
            ..lineTo(90, 26)
            ..lineTo(122, 35)
            ..lineTo(90, 44),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(50, 58, 240, 110),
            const Radius.circular(16),
          ),
          stroke,
        );
        _drawDashedPath(
          canvas,
          Path()
            ..moveTo(210, 58)
            ..lineTo(210, 168),
          stroke,
        );
        canvas.drawCircle(const Offset(250, 113), 14, stroke);
        canvas.drawLine(const Offset(80, 98), const Offset(160, 98), stroke);
        canvas.drawLine(const Offset(80, 128), const Offset(140, 128), stroke);
      case PublishCardArt.locked:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(120, 92, 100, 86),
            const Radius.circular(14),
          ),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(140, 92)
            ..lineTo(140, 68)
            ..arcToPoint(
              const Offset(200, 68),
              radius: const Radius.circular(30),
              clockwise: true,
            )
            ..lineTo(200, 92),
          stroke,
        );
        canvas.drawCircle(const Offset(170, 128), 10, stroke);
        canvas.drawLine(const Offset(170, 138), const Offset(170, 154), stroke);
    }
    canvas.restore();
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double offset = 0;
      while (offset < metric.length) {
        final double end = math.min(offset + 6, metric.length);
        canvas.drawPath(metric.extractPath(offset, end), paint);
        offset += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_PublishArtPainter oldDelegate) =>
      oldDelegate.art != art || oldDelegate.color != color;
}

class _TopicModeStep extends StatelessWidget {
  const _TopicModeStep({required this.onSelected});

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => _ChooserStep(
    kicker: '第一步',
    title: '选择主题类型',
    children: <Widget>[
      _ChooserOption(
        key: const Key('publish-topic-mode-1'),
        title: '城市定向',
        subtitle: '集合出发、按路线推进，适合带队与强节奏故事',
        onTap: () => onSelected(1),
      ),
      _ChooserOption(
        key: const Key('publish-topic-mode-2'),
        title: '自由探索',
        subtitle: '常设开放、自由前往，适合街区漫游与自助体验',
        onTap: () => onSelected(2),
      ),
    ],
  );
}

class _TopicAbilityStep extends StatelessWidget {
  const _TopicAbilityStep({
    required this.mode,
    required this.capability,
    required this.onQuick,
    required this.onPro,
  });

  final int mode;
  final PublishCapability capability;
  final VoidCallback onQuick;
  final VoidCallback onPro;

  @override
  Widget build(BuildContext context) => _ChooserStep(
    kicker: mode == 2 ? '自由探索' : '城市定向',
    title: '选择创建方式',
    children: <Widget>[
      _ChooserOption(
        key: const Key('publish-topic-quick'),
        title: '快速配置',
        subtitle: capability.canSimplePublish
            ? '说出想法，确认每个点位后生成可编辑草稿'
            : '当前身份不可发布主题',
        onTap: capability.canSimplePublish ? onQuick : null,
      ),
      _ChooserOption(
        key: const Key('publish-topic-pro'),
        title: '专业手动',
        subtitle: capability.canProPublish
            ? <String>[
                '章节·节点·剧情全掌控',
                if (capability.quotaExhausted) '在架已满，可先存草稿或下架旧项目',
              ].join('\n')
            : '当前身份不可发布主题',
        onTap: capability.canProPublish ? onPro : null,
      ),
    ],
  );
}

class _ChooserStep extends StatelessWidget {
  const _ChooserStep({
    required this.kicker,
    required this.title,
    required this.children,
  });

  final String kicker;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      children: <Widget>[
        Text(
          kicker,
          style: TextStyle(fontSize: CyTokens.typeLabel, color: p.textTertiary),
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          title,
          style: TextStyle(
            fontSize: CyTokens.typePageTitle,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        ...children,
      ],
    );
  }
}

class _ChooserOption extends StatelessWidget {
  const _ChooserOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: '$title，$subtitle',
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(CyTokens.space4),
            decoration: BoxDecoration(
              border: Border.all(color: p.borderSubtle),
              borderRadius: BorderRadius.circular(CyTokens.radiusSm),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: CyTokens.typeCardTitle,
                          fontWeight: FontWeight.w700,
                          color: onTap == null ? p.textTertiary : p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: CyTokens.typeCaption,
                          color: p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space3),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: onTap == null ? p.textTertiary : p.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
